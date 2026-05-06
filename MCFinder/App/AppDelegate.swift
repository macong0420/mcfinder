import AppKit
import OSLog
import Quartz
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    let databaseManager: DatabaseManager
    let bookmarkManager: BookmarkManager
    let searchEngine: SearchEngine
    let fsEventsMonitor: FSEventsMonitor
    let keyboardShortcutManager: KeyboardShortcutManager
    let quickLookCoordinator: QuickLookCoordinator
    let quickSearchPanel: QuickSearchPanel
    let indexManager: IndexManager
    private var localEventMonitor: Any?
    private weak var cachedMainWindow: NSWindow?
    weak var appState: AppState?

    /// Resolves the SwiftUI `WindowGroup` main window — the one the user
    /// thinks of as "MCFinder". `NSApp.windows.first` is unreliable here:
    /// `QuickSearchPanel` is created in `init` *before* SwiftUI builds its
    /// scene, so it lands first in the windows list and `.first` would
    /// happily return that panel, making the main hotkey accidentally
    /// activate the QuickSearch overlay. Filtering on "not an NSPanel + has
    /// a titlebar" pins it to the WindowGroup window. Result is cached so a
    /// later-opened About window can't shadow it.
    private var mainAppWindow: NSWindow? {
        if let w = cachedMainWindow, NSApp.windows.contains(w) { return w }
        let found = NSApp.windows.first { window in
            !(window is NSPanel) && window.styleMask.contains(.titled)
        }
        cachedMainWindow = found
        return found
    }

    override init() {
        let db = DatabaseManager()
        let bookmarkMgr = BookmarkManager()
        let searchEng = SearchEngine(databaseManager: db)
        let fseMon = FSEventsMonitor()
        let ksManager = KeyboardShortcutManager()
        let qlCoordinator = QuickLookCoordinator()
        let qsPanel = QuickSearchPanel()

        databaseManager = db
        bookmarkManager = bookmarkMgr
        searchEngine = searchEng
        fsEventsMonitor = fseMon
        keyboardShortcutManager = ksManager
        quickLookCoordinator = qlCoordinator
        quickSearchPanel = qsPanel

        indexManager = IndexManager(
            databaseManager: db,
            searchEngine: searchEng,
            fsEventsMonitor: fseMon,
            bookmarkManager: bookmarkMgr
        )

        super.init()
        Self.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func performSetupIfNeeded() {
        guard let appState, !appState.setupCompleted else { return }

        appState.setup(
            databaseManager: databaseManager,
            bookmarkManager: bookmarkManager,
            indexManager: indexManager,
            searchEngine: searchEngine,
            fsEventsMonitor: fsEventsMonitor,
            keyboardShortcutManager: keyboardShortcutManager,
            quickSearchPanel: quickSearchPanel,
            quickLookCoordinator: quickLookCoordinator
        )

        setupHotkeys()
        setupLocalEventMonitor()
        restoreBookmarksAndWatch()

        if let window = mainAppWindow {
            window.delegate = self
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardShortcutManager.unregisterAll()
        fsEventsMonitor.stopWatching()
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, let window = mainAppWindow {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - Setup

    private func setupHotkeys() {
        guard let appState else { return }
        // Install the callbacks first, so even a hot-key press that races the
        // `RegisterEventHotKey` call has a handler ready.
        keyboardShortcutManager.onMainHotkey = { [weak self] in
            self?.toggleMainWindow()
        }
        keyboardShortcutManager.onQuickSearchHotkey = { [weak appState] in
            appState?.toggleQuickSearch()
        }
        // Single unified registration path — also surfaces conflicts in
        // `appState.hotkeyErrors` so the UI can display them.
        appState.applyAllHotkeys()
    }

    /// Show / hide the main window in response to the global "Main Window"
    /// hotkey. Behaviour matches Spotlight-style overlays:
    ///   - Hidden / not key  → bring to front + activate the app.
    ///   - Visible & focused → hide the whole app (returns focus to whatever
    ///     the user came from). `orderOut` on a single window would leave
    ///     other MCFinder windows on screen and feel half-finished.
    private func toggleMainWindow() {
        guard let window = mainAppWindow else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if window.isVisible && window.isKeyWindow && NSApp.isActive {
            NSApp.hide(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func setupLocalEventMonitor() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53,
               QLPreviewPanel.sharedPreviewPanelExists(),
               QLPreviewPanel.shared().isVisible {
                QLPreviewPanel.shared().orderOut(nil)
            }
            return event
        }
    }

    private func restoreBookmarksAndWatch() {
        guard let appState else { return }
        let resolvedURLs = bookmarkManager.restoreAllBookmarks()
        let pathStrings = resolvedURLs.map { $0.path }
        if !pathStrings.isEmpty {
            fsEventsMonitor.startWatching(paths: pathStrings)
            appState.updateTotalIndexed()
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {}
}
