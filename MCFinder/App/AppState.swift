import AppKit
import Foundation
import OSLog
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var setupCompleted = false

    // MARK: - Managers

    @Published var databaseManager: DatabaseManager?
    @Published var bookmarkManager: BookmarkManager?
    @Published var indexManager: IndexManager?
    @Published var searchEngine: SearchEngine?
    @Published var fsEventsMonitor: FSEventsMonitor?
    @Published var keyboardShortcutManager: KeyboardShortcutManager?
    @Published var quickSearchPanel: QuickSearchPanel?
    @Published var quickLookCoordinator: QuickLookCoordinator?

    // MARK: - Search State

    @Published var searchText = ""
    @Published var searchResults: [SearchResultItem] = []
    @Published var searchCount = 0
    @Published var searchTime: TimeInterval = 0
    @Published var searchMode: SearchMode = .fts5
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

    @Published var hotkeyKeyCode = 49
    @Published var hotkeyModifiers: NSEvent.ModifierFlags = [.command, .shift]
    @Published var quickSearchKeyCode = 49
    @Published var quickSearchModifiers: NSEvent.ModifierFlags = [.command, .shift]

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
        bookmarkManager?.allBookmarkedPaths() ?? []
    }

    // MARK: - Setup

    func registerWithDelegate() {
        AppDelegate.shared?.appState = self
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
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            guard let engine = searchEngine else { return }
            isLoading = true
            errorMessage = nil
            do {
                let result = try engine.search(text: searchText, filter: currentFilter, sort: sortBy, ascending: sortAscending, mode: searchMode, limit: 500)
                searchResults = result.items
                searchCount = result.totalCount
                searchTime = result.searchTime
                selectedIndex = searchResults.isEmpty ? nil : 0
            } catch {
                errorMessage = error.localizedDescription
                // Logger.app.error("Search failed: \(error)")
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

        scanTask = Task { @MainActor in
            var resolved: [URL] = []
            for url in paths {
                do {
                    let data = try bookmarkManager.createBookmark(for: url)
                    bookmarkManager.saveBookmark(data, forPath: url.path)
                    let r = try bookmarkManager.resolveAndStartAccessing(data)
                    resolved.append(r)
                } catch {
                    // Logger.app.error("Bookmark error for \(url.path): \(error)")
                }
            }
            do {
                let count = try await indexManager.scanDirectories(paths: resolved, includeHidden: scanHiddenFiles) { [weak self] n in
                    Task { @MainActor in self?.scannedCount = n }
                }
                totalIndexed = count
                bookmarkManager.stopAllAccess(urls: resolved)
                fsEventsMonitor?.startWatching(paths: resolved.map { $0.path })
            } catch {
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
        guard let url = await BookmarkManager.promptUserToSelectFolder() else { return }
        startScan(paths: [url])
    }

    func toggleQuickLook(for item: SearchResultItem) {
        quickLookCoordinator?.togglePreview(for: [URL(fileURLWithPath: item.path)])
    }

    func onHotkeyChanged(type: HotkeyType, keyCode: Int, modifiers: NSEvent.ModifierFlags) {
        let d = UserDefaults.standard
        switch type {
        case .main:
            hotkeyKeyCode = keyCode; hotkeyModifiers = modifiers
            d.set(keyCode, forKey: "hotkeyKeyCode"); d.set(modifiers.rawValue, forKey: "hotkeyModifiers")
            _ = keyboardShortcutManager?.registerMainHotkey(keyCode: keyCode, modifiers: modifiers)
        case .quickSearch:
            quickSearchKeyCode = keyCode; quickSearchModifiers = modifiers
            d.set(keyCode, forKey: "quickSearchHotkeyKeyCode"); d.set(modifiers.rawValue, forKey: "quickSearchHotkeyModifiers")
            _ = keyboardShortcutManager?.registerQuickSearchHotkey(keyCode: keyCode, modifiers: modifiers)
        }
    }

    private func loadHotkeyPreferences() {
        let d = UserDefaults.standard
        hotkeyKeyCode = d.integer(forKey: "hotkeyKeyCode")
        hotkeyModifiers = NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: "hotkeyModifiers")))
        quickSearchKeyCode = d.integer(forKey: "quickSearchHotkeyKeyCode")
        quickSearchModifiers = NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: "quickSearchHotkeyModifiers")))
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
