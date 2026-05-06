import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            VStack(spacing: 0) {
                SearchBarView()
                FilterBarView()
                if let error = appState.errorMessage {
                    ErrorBanner(message: error)
                }
                ResultsListView()
                statusBar
            }
        }
        .onAppear {
            if appState.scanPaths.isEmpty {
                // Trigger a first-time folder selection or just show empty state
            }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        List(selection: Binding(
            get: { appState.selectedIndex },
            set: { appState.selectedIndex = $0 }
        )) {
            Section("Search") {
                Label("All Files", systemImage: "doc.text.magnifyingglass")
                    .tag(nil as Int?)
                Label("Recent", systemImage: "clock")
                    .tag(-1)
            }
            Section("Indexed Folders") {
                if appState.scanPaths.isEmpty {
                    Text("No folders indexed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                ForEach(appState.scanPaths, id: \.self) { path in
                    Label(
                        URL(fileURLWithPath: path).lastPathComponent,
                        systemImage: "folder"
                    )
                }
                Button(action: { Task { await appState.addFolderToIndex() } }) {
                    Label("Add Folder...", systemImage: "plus")
                }
            }
            Section {
                if appState.isScanning {
                    HStack {
                        ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
                        Text("Scanning...")
                    }
                    Text("\(appState.scannedCount) files").font(.caption).foregroundColor(.secondary)
                } else {
                    Label("Rescan All", systemImage: "arrow.clockwise")
                        .onTapGesture {
                            let urls = appState.bookmarkManager?.allBookmarkedPaths().map { URL(fileURLWithPath: $0) } ?? []
                            appState.startScan(paths: urls)
                        }
                }
            }
            Section {
                Button(action: { /* open settings */ }) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 16) {
            if appState.isLoading {
                ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
                Text("Searching...")
            } else if appState.searchCount > 0 {
                Text("\(appState.searchCount) results")
                Text("(\(String(format: "%.3f", appState.searchTime))s)")
                    .foregroundColor(.secondary)
            } else if !appState.searchText.isEmpty {
                Text("No results")
            }
            Spacer()
            Text("\(appState.totalIndexed) files indexed")
                .foregroundColor(.secondary)
            if appState.isScanning {
                ProgressView().scaleEffect(0.5).frame(width: 16, height: 16)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text(message)
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.1))
    }
}
