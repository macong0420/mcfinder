import AppKit
import Foundation
import OSLog
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var setupCompleted = false

    // MARK: - Managers

    var databaseManager: DatabaseManager?
    var bookmarkManager: BookmarkManager?
    var indexManager: IndexManager?
    var searchEngine: SearchEngine?
    var fsEventsMonitor: FSEventsMonitor?
    var keyboardShortcutManager: KeyboardShortcutManager?
    var quickSearchPanel: QuickSearchPanel?
    var quickLookCoordinator: QuickLookCoordinator?

    // MARK: - Search State

    @Published var searchText = ""
    @Published var searchResults: [SearchResultItem] = []
    @Published var searchCount = 0
    @Published var searchTime: TimeInterval = 0
    @Published var searchMode: SearchMode = .contains
    @Published var caseSensitive = false
    private var searchTask: Task<Void, Never>?

    // MARK: - Filter State

    @Published var filterExtension = ""
    @Published var filterFileType: FileTypeFilter = .all
    @Published var filterSizeMin: Int64?
    @Published var filterSizeMax: Int64?
    @Published var filterModifiedAfter: Date?

    // MARK: - Sort State

    @Published var sortBy: SortField = .date
    @Published var sortAscending = false

    // MARK: - Scan State

    @Published var isScanning = false
    @Published var scannedCount = 0
    @Published var totalIndexed = 0
    @Published var scanHiddenFiles = false
    private var scanTask: Task<Void, Never>?

    // MARK: - Hotkey State

    // Defaults: ⌥⌘F (main) and ⇧⌥⌘F (quick search). The previous default
    // (⌘⇧Space) is bound to "Select previous input source" on a stock macOS
    // install, so RegisterEventHotKey would silently fail with
    // eventHotKeyExistsErr — i.e. the user saw a configured shortcut that
    // didn't actually work. Letter `F` (keyCode 3) with ⌥⌘ has no default
    // system binding.
    @Published var hotkeyKeyCode = 3
    @Published var hotkeyModifiers: NSEvent.ModifierFlags = [.command, .option]
    @Published var quickSearchKeyCode = 3
    @Published var quickSearchModifiers: NSEvent.ModifierFlags = [.command, .option, .shift]

    /// Last registration outcome per hotkey, surfaced under each recorder so
    /// users immediately see when their chosen combo conflicts.
    @Published var hotkeyErrors: [HotkeyType: String] = [:]

    // MARK: - Login Item

    /// Backs the "Launch at Login" toggle in Settings. Wraps SMAppService.
    let launchAtLoginManager = LaunchAtLoginManager()

    // MARK: - UI State

    @Published var selectedIndex: Int?
    @Published var selectedItem: SearchResultItem?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var recentFiles: [SearchResultItem] = []

    // MARK: - Computed

    var isFiltering: Bool {
        !filterExtension.isEmpty || filterFileType != .all || filterSizeMin != nil || filterSizeMax != nil || filterModifiedAfter != nil
    }

    var currentFilter: SearchFilter {
        SearchFilter(fileExtension: filterExtension, fileType: filterFileType, sizeMin: filterSizeMin, sizeMax: filterSizeMax, modifiedAfter: filterModifiedAfter)
    }

    var scanPaths: [String] {
        let bookmarked = bookmarkManager?.allBookmarkedPaths() ?? []
        let autoEntitlement = bookmarkManager?.allAutoEntitlementPaths() ?? []
        return Array(Set(bookmarked + autoEntitlement)).sorted()
    }

    // MARK: - Setup

    func registerWithDelegate() {
        AppDelegate.shared?.appState = self
        AppDelegate.shared?.performSetupIfNeeded()
    }

    func setup(
        databaseManager: DatabaseManager,
        bookmarkManager: BookmarkManager,
        indexManager: IndexManager,
        searchEngine: SearchEngine,
        fsEventsMonitor: FSEventsMonitor,
        keyboardShortcutManager: KeyboardShortcutManager,
        quickSearchPanel: QuickSearchPanel,
        quickLookCoordinator: QuickLookCoordinator
    ) {
        self.databaseManager = databaseManager
        self.bookmarkManager = bookmarkManager
        self.indexManager = indexManager
        self.searchEngine = searchEngine
        self.fsEventsMonitor = fsEventsMonitor
        self.keyboardShortcutManager = keyboardShortcutManager
        self.quickSearchPanel = quickSearchPanel
        self.quickLookCoordinator = quickLookCoordinator

        quickSearchPanel.searchEngine = searchEngine
        quickSearchPanel.createContentView { [weak self] item in self?.openFile(item) }

        fsEventsMonitor.onChangeDetected = { [weak self] paths in
            Task { @MainActor in
                do {
                    try await self?.indexManager?.processFSEventChanges(paths)
                    self?.updateTotalIndexed()
                } catch {
                    // Logger.app.error("FSEvents change processing failed: \(error)")
                }
            }
        }

        loadHotkeyPreferences()
        loadRecentFiles()
        setupCompleted = true
    }

    // MARK: - Search

    func performSearch() {
        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            guard let self, let engine = self.searchEngine else { return }

            let text = self.searchText
            let filter = self.currentFilter
            let sortBy = self.sortBy
            let sortAscending = self.sortAscending
            let searchMode = self.searchMode

            isLoading = true
            errorMessage = nil

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try engine.search(text: text, filter: filter, sort: sortBy, ascending: sortAscending, mode: searchMode, limit: 500)
                }.value

                if Task.isCancelled { return }
                searchResults = result.items
                searchCount = result.totalCount
                searchTime = result.searchTime
                selectedIndex = searchResults.isEmpty ? nil : 0
                selectedItem = searchResults[safe: selectedIndex ?? -1]
            } catch is CancellationError {
                // Ignore cancellation.
            } catch {
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }

    // MARK: - Scan

    func startScan(paths: [URL]) {
        guard let bookmarkManager, let indexManager else { return }
        scanTask?.cancel()
        isScanning = true
        scannedCount = 0
        isLoading = true

        let includeHidden = scanHiddenFiles
        scanTask = Task { @MainActor [weak self] in
            guard let self else { return }

            var resolved: [URL] = []
            // Only track URLs that actually need security-scoped cleanup.
            var bookmarkedURLs: [URL] = []
            for url in paths {
                if BookmarkManager.isAutoEntitlementPath(url) {
                    // ~/Desktop, ~/Documents, ~/Downloads — access granted by
                    // entitlements, no security-scoped bookmark needed.
                    bookmarkManager.saveAutoEntitlementPath(url.path)
                    resolved.append(url)
                } else {
                    do {
                        let data = try bookmarkManager.createBookmark(for: url)
                        bookmarkManager.saveBookmark(data, forPath: url.path)
                        let r = try bookmarkManager.resolveAndStartAccessing(data)
                        resolved.append(r)
                        bookmarkedURLs.append(r)
                    } catch {
                        // Logger.app.error("Bookmark error for \(url.path): \(error)")
                    }
                }
            }

            do {
                let count = try await Task.detached(priority: .utility) { [weak self] in
                    try await indexManager.scanDirectories(paths: resolved, includeHidden: includeHidden) { n in
                        Task { @MainActor in self?.scannedCount = n }
                    }
                }.value

                if Task.isCancelled {
                    bookmarkManager.stopAllAccess(urls: bookmarkedURLs)
                    return
                }

                totalIndexed = count
                bookmarkManager.stopAllAccess(urls: bookmarkedURLs)
                fsEventsMonitor?.startWatching(paths: resolved.map { $0.path })
            } catch is CancellationError {
                bookmarkManager.stopAllAccess(urls: bookmarkedURLs)
            } catch {
                bookmarkManager.stopAllAccess(urls: bookmarkedURLs)
                errorMessage = error.localizedDescription
            }

            isScanning = false
            isLoading = false
        }
    }

    func stopScan() { scanTask?.cancel(); isScanning = false; isLoading = false }

    func deleteAllFiles() {
        do {
            try indexManager?.deleteAll()
            totalIndexed = 0; searchResults = []; searchCount = 0
        } catch {
            // Logger.app.error("deleteAllFiles FAILED: \(error)")
        }
    }

    func clearFilters() {
        filterExtension = ""; filterFileType = .all; filterSizeMin = nil; filterSizeMax = nil; filterModifiedAfter = nil
        performSearch()
    }

    func updateTotalIndexed() {
        guard let db = databaseManager else { return }
        Task.detached {
            if let count = try? db.totalFileCount() {
                await MainActor.run { self.totalIndexed = count }
            }
        }
    }

    func toggleQuickSearch() { quickSearchPanel?.toggle() }

    func openSettings() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // NSWindow defaults `isReleasedWhenClosed` to `true` — a non-ARC era
        // legacy that, when combined with a Swift-managed local reference like
        // ours, leaves SwiftUI/AppKit holding zombie pointers after the
        // settings window is closed and re-opened. Disabling it lets ARC own
        // the lifecycle cleanly.
        window.isReleasedWhenClosed = false
        window.title = "Settings"
        window.contentView = NSHostingView(rootView: SettingsView().environmentObject(self))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func openFile(_ item: SearchResultItem) {
        NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
        addToRecent(item)
    }

    func revealInFinder(_ item: SearchResultItem) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }

    func copyPath(_ item: SearchResultItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.path, forType: .string)
    }

    func addFolderToIndex() async {
        let urls = await BookmarkManager.promptUserToSelectFolders()
        guard !urls.isEmpty else { return }
        startScan(paths: urls)
    }

    /// Show preview for a file (single-click). Always opens, never toggles.
    func showQuickLook(for item: SearchResultItem) {
        quickLookCoordinator?.showPreview(for: [URL(fileURLWithPath: item.path)])
    }

    /// Toggle preview visibility (keyboard shortcut).
    func toggleQuickLook(for item: SearchResultItem) {
        quickLookCoordinator?.togglePreview(for: [URL(fileURLWithPath: item.path)])
    }

    func onHotkeyChanged(type: HotkeyType, keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        // Defense in depth — the recorder already filters bare keys, but this
        // also catches values arriving from older builds or programmatic edits.
        let modifierMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        guard !modifiers.intersection(modifierMask).isEmpty else {
            hotkeyErrors[type] = "Add a modifier (⌘ ⌥ ⌃ ⇧) to make this a global shortcut."
            return
        }

        let d = UserDefaults.standard
        switch type {
        case .main:
            hotkeyKeyCode = keyCode
            hotkeyModifiers = modifiers
            d.set(keyCode, forKey: "hotkeyKeyCode")
            d.set(modifiers.rawValue, forKey: "hotkeyModifiers")
        case .quickSearch:
            quickSearchKeyCode = keyCode
            quickSearchModifiers = modifiers
            d.set(keyCode, forKey: "quickSearchHotkeyKeyCode")
            d.set(modifiers.rawValue, forKey: "quickSearchHotkeyModifiers")
        }
        applyHotkey(type)
    }

    /// Re-registers a single hotkey from the current AppState values and
    /// records the outcome (so the UI can show "shortcut taken" etc.).
    func applyHotkey(_ type: HotkeyType) {
        guard let manager = keyboardShortcutManager else { return }
        let result: HotkeyRegistrationResult
        switch type {
        case .main:
            result = manager.registerMainHotkey(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
        case .quickSearch:
            result = manager.registerQuickSearchHotkey(keyCode: quickSearchKeyCode, modifiers: quickSearchModifiers)
        }
        if let msg = result.errorMessage {
            hotkeyErrors[type] = msg
        } else {
            hotkeyErrors.removeValue(forKey: type)
        }
    }

    /// Convenience for the AppDelegate's startup path.
    func applyAllHotkeys() {
        applyHotkey(.main)
        applyHotkey(.quickSearch)
    }

    private func loadHotkeyPreferences() {
        let d = UserDefaults.standard
        // If a previous build (with the broken ModifierFlags init) wrote a
        // zero-modifier value, ignore the persisted entry entirely and keep
        // the in-code default. Otherwise the bare key (e.g. Space) would be
        // re-registered as a global hotkey and hijack the keyboard.
        if d.object(forKey: "hotkeyKeyCode") != nil {
            let code = d.integer(forKey: "hotkeyKeyCode")
            let mods = NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: "hotkeyModifiers")))
            if code > 0, !mods.isEmpty {
                hotkeyKeyCode = code
                hotkeyModifiers = mods
            }
        }
        if d.object(forKey: "quickSearchHotkeyKeyCode") != nil {
            let code = d.integer(forKey: "quickSearchHotkeyKeyCode")
            let mods = NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: "quickSearchHotkeyModifiers")))
            if code > 0, !mods.isEmpty {
                quickSearchKeyCode = code
                quickSearchModifiers = mods
            }
        }
    }

    private func addToRecent(_ item: SearchResultItem) {
        var r = recentFiles; r.removeAll { $0.path == item.path }; r.insert(item, at: 0)
        recentFiles = Array(r.prefix(50))
        UserDefaults.standard.set(recentFiles.map { $0.path }, forKey: "MCFinder.recentFiles")
    }

    private func loadRecentFiles() {
        guard let e = searchEngine else { return }
        let paths = UserDefaults.standard.stringArray(forKey: "MCFinder.recentFiles") ?? []
        Task.detached { [weak self] in
            do {
                let result = try e.search(text: "", sort: .date, ascending: false, limit: 200)
                let pathSet = Set(paths)
                let filtered = result.items.filter { pathSet.contains($0.path) }
                await MainActor.run {
                    self?.recentFiles = filtered
                }
            } catch {
                // Logger.app.error("Failed to load recent files: \(error)")
            }
        }
    }
}

enum HotkeyType { case main; case quickSearch }

// MARK: - Launch at Login

/// Thin wrapper around `SMAppService.mainApp` that powers the
/// "Launch at Login" toggle in Settings. The previous build hard-coded the
/// toggle to `.constant(false)`, so the option appeared in the UI but was
/// inert.
///
/// Sandboxing notes: `SMAppService.mainApp` works for sandboxed apps and
/// requires no extra entitlement, but the user must approve the login item in
/// System Settings → General → Login Items. We surface that requirement
/// through `lastError` and open the relevant settings pane on the first
/// successful `register()` that lands in the `.requiresApproval` state.
@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var lastError: String?

    init() {
        refresh()
    }

    /// Re-reads the current login-item status from the system. Cheap; safe to
    /// call from `onAppear` / window focus handlers if needed.
    func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    /// Toggles the login-item registration. Idempotent — no-ops if the system
    /// is already in the requested state.
    ///
    /// Hops to the next main-thread tick before doing any work. The Toggle's
    /// `set` closure runs synchronously during a SwiftUI gesture, and calling
    /// `SMAppService.register()` + `openSystemSettingsLoginItems()` inside
    /// that same call frame has been observed to crash in `objc_release`
    /// (use-after-free on an AppKit/SwiftUI internal object) — focus changes
    /// to System Settings while SwiftUI is still mid-update through our
    /// `@Published` writes. A single run-loop hop breaks that re-entrancy.
    func setEnabled(_ enable: Bool) {
        Task { @MainActor [weak self] in
            self?.performSetEnabled(enable)
        }
    }

    /// Opens "System Settings → General → Login Items" so the user can
    /// approve our app. Exposed separately (instead of being called
    /// automatically from `setEnabled`) so the focus change happens on a
    /// distinct user gesture, not interleaved with binding mutations.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func performSetEnabled(_ enable: Bool) {
        let service = SMAppService.mainApp
        var caught: String?
        do {
            if enable {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            caught = error.localizedDescription
        }

        let status = service.status
        isEnabled = (status == .enabled)

        if let caught {
            lastError = caught
        } else if enable && status == .requiresApproval {
            lastError = "Approval required — open System Settings → General → Login Items and enable MCFinder."
        } else {
            lastError = nil
        }
    }
}
