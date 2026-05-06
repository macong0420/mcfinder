import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            indexedFoldersTab
                .tabItem { Label("Folders", systemImage: "folder") }

            hotkeysTab
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }

            generalTab
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Folders

    private var indexedFoldersTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Indexed Folders")
                .font(.headline)

            if appState.scanPaths.isEmpty {
                Text("No folders indexed. Add folders to start searching.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                List {
                    ForEach(appState.scanPaths, id: \.self) { path in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                            Text(path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) {
                                appState.bookmarkManager?.removeBookmark(forPath: path)
                                appState.bookmarkManager?.removeAutoEntitlementPath(path)
                                do {
                                    try appState.indexManager?.cleanupRemovedDirectory(at: path)
                                } catch {
                                }
                                appState.updateTotalIndexed()
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 100)
            }

            HStack {
                Button("Add Folder...") {
                    Task { await appState.addFolderToIndex() }
                }
                Spacer()
                if !appState.scanPaths.isEmpty {
                    Button("Rescan All") {
                        let urls = appState.scanPaths.map { URL(fileURLWithPath: $0) }
                        appState.startScan(paths: urls)
                    }
                    Button("Clear All", role: .destructive) {
                        appState.deleteAllFiles()
                    }
                }
            }

        }
        .padding()
    }

    // MARK: - Hotkeys

    private var hotkeysTab: some View {
        HotkeySettingsView()
    }

    // MARK: - General

    private var generalTab: some View {
        GeneralTabView(loginManager: appState.launchAtLoginManager)
    }
}

/// Extracted as its own view so we can attach `@ObservedObject` to the
/// LaunchAtLoginManager — necessary for the toggle to update reactively when
/// macOS reports a state change (or `requiresApproval`) back to us.
private struct GeneralTabView: View {
    @ObservedObject var loginManager: LaunchAtLoginManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.headline)

            Toggle("Launch at Login", isOn: Binding(
                get: { loginManager.isEnabled },
                set: { loginManager.setEnabled($0) }
            ))

            if let error = loginManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)

                // Surfaced as a separate user gesture so the focus change
                // doesn't race the Toggle binding's @Published mutations.
                Button("Open Login Items in System Settings…") {
                    loginManager.openLoginItemsSettings()
                }
                .buttonStyle(.link)
            }

            Divider()

            Text("MCFinder v1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Copyright (c) 2026 MCFinder. All rights reserved.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .onAppear { loginManager.refresh() }
    }
}
