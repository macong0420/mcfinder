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
    weak var appState: AppState?

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

        guard let appState, appState.setupCompleted == false else { return }

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

        if let window = NSApp.windows.first {
            window.delegate = self
        }

        // Logger.app.info("MCFinder launched")
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
        if !flag, let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - Setup

    private func setupHotkeys() {
        guard let appState else { return }
        _ = keyboardShortcutManager.registerMainHotkey(keyCode: appState.hotkeyKeyCode, modifiers: appState.hotkeyModifiers)
        keyboardShortcutManager.onMainHotkey = {
            if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        _ = keyboardShortcutManager.registerQuickSearchHotkey(keyCode: appState.quickSearchKeyCode, modifiers: appState.quickSearchModifiers)
        keyboardShortcutManager.onQuickSearchHotkey = {
            appState.toggleQuickSearch()
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
