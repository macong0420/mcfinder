import SwiftUI

@main
struct MCFinderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear { appState.registerWithDelegate() }
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MCFinder") { openAboutWindow() }
            }
            CommandMenu("File") {
                Button("Add Folder to Index...") {
                    Task { await appState.addFolderToIndex() }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Settings...") {
                    appState.openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
                Divider()
                Button("Rescan All") {
                    let urls = appState.scanPaths.map { URL(fileURLWithPath: $0) }
                    appState.startScan(paths: urls)
                }
                Divider()
                Button("Clear All Index") {
                    appState.deleteAllFiles()
                }
            }
            CommandMenu("View") {
                Button("Toggle Quick Look") {
                    if let item = appState.selectedItem {
                        appState.toggleQuickLook(for: item)
                    }
                }
            }
            CommandGroup(replacing: .help) {
                Button("MCFinder Help") {
                    if let url = URL(string: "https://mcfinder.app/help") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func openAboutWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        // See AppState.openSettings — NSWindow's legacy `isReleasedWhenClosed`
        // default fights ARC and produces zombie references on reopen.
        window.isReleasedWhenClosed = false
        window.title = "About MCFinder"
        window.contentView = NSHostingView(rootView: AboutView())
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
