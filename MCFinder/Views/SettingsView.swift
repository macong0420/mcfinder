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
                        let urls = appState.bookmarkManager?.allBookmarkedPaths().map { URL(fileURLWithPath: $0) } ?? []
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
        VStack(alignment: .leading, spacing: 16) {
            Text("General")
                .font(.headline)

            Toggle("Launch at Login", isOn: .constant(false))

            Text("MCFinder v1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Copyright (c) 2026 MCFinder. All rights reserved.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
