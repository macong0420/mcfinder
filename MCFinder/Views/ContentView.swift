import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            SearchBarView()
            FilterToolbarView()
            if let error = appState.errorMessage {
                ErrorBanner(message: error)
            }
            ResultsHeaderView()
            ResultsListView()
            statusBar
        }
        .frame(minWidth: 700, minHeight: 500)
        .onKeyPress(.escape) {
            if !appState.searchText.isEmpty {
                appState.searchText = ""
                return .handled
            }
            return .ignored
        }
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

// MARK: - Search Bar

struct SearchBarView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 15))

            TextField("Search files...", text: Binding(
                get: { appState.searchText },
                set: { appState.searchText = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 16))
            .focused($isSearchFocused)
            .onSubmit { appState.performSearch() }
            .onChange(of: appState.searchText) { _, _ in
                appState.performSearch()
            }
            .onAppear { isSearchFocused = true }

            if !appState.searchText.isEmpty {
                Button(action: { appState.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - Filter Toolbar

struct FilterToolbarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(SearchMode.allCases, id: \.self) { mode in
                        Button(action: { appState.searchMode = mode; appState.performSearch() }) {
                            HStack {
                                Text(modeLabel(mode))
                                if appState.searchMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(appState.searchMode == .exact ? "Exact" :
                               appState.searchMode == .contains ? "Contains" :
                               appState.searchMode == .prefix ? "Prefix" : "Path",
                               systemImage: "text.magnifyingglass")
                }
                .menuIndicator(.hidden)

                Button(action: { appState.caseSensitive.toggle(); appState.performSearch() }) {
                    filterChip("Aa",
                               systemImage: appState.caseSensitive ? "textformat.abc" : "textformat",
                               active: appState.caseSensitive)
                }
                .buttonStyle(.plain)
                .help("Case sensitive")

                Divider().frame(height: 16).padding(.horizontal, 4)

                Menu {
                    Button(action: { appState.filterExtension = ""; appState.performSearch() }) {
                        HStack {
                            Text("Any")
                            if appState.filterExtension.isEmpty { Image(systemName: "checkmark") }
                        }
                    }
                    Divider()
                    ForEach(commonExtensions, id: \.self) { ext in
                        Button(action: { appState.filterExtension = ext; appState.performSearch() }) {
                            HStack {
                                Text(ext)
                                if appState.filterExtension == ext { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    filterChip(appState.filterExtension.isEmpty ? "Extension" : appState.filterExtension,
                               systemImage: "doc")
                }
                .menuIndicator(.hidden)

                Menu {
                    Button(action: { appState.filterSizeMin = nil; appState.filterSizeMax = nil; appState.performSearch() }) {
                        HStack {
                            Text("Any")
                            if appState.filterSizeMin == nil && appState.filterSizeMax == nil { Image(systemName: "checkmark") }
                        }
                    }
                    Divider()
                    ForEach(sizePresets, id: \.label) { preset in
                        Button(action: {
                            appState.filterSizeMin = preset.min
                            appState.filterSizeMax = preset.max
                            appState.performSearch()
                        }) {
                            HStack {
                                Text(preset.label)
                                if appState.filterSizeMin == preset.min && appState.filterSizeMax == preset.max {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(sizeLabel, systemImage: "internaldrive")
                }
                .menuIndicator(.hidden)

                Menu {
                    Button(action: { appState.filterModifiedAfter = nil; appState.performSearch() }) {
                        HStack {
                            Text("Any")
                            if appState.filterModifiedAfter == nil { Image(systemName: "checkmark") }
                        }
                    }
                    Divider()
                    ForEach(datePresets, id: \.label) { preset in
                        Button(action: { appState.filterModifiedAfter = preset.date; appState.performSearch() }) {
                            HStack {
                                Text(preset.label)
                                if let current = appState.filterModifiedAfter,
                                   abs(current.timeIntervalSince(preset.date)) < 1 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterChip(dateLabel, systemImage: "calendar")
                }
                .menuIndicator(.hidden)

                Menu {
                    ForEach(FileTypeFilter.allCases, id: \.self) { type in
                        Button(action: { appState.filterFileType = type; appState.performSearch() }) {
                            HStack {
                                Text(type.label)
                                if appState.filterFileType == type { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    filterChip(appState.filterFileType == .all ? "File + Dir" : appState.filterFileType.label,
                               systemImage: "folder")
                }
                .menuIndicator(.hidden)

                if appState.isFiltering {
                    Button("Clear") { appState.clearFilters() }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                        .font(.caption)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private func filterChip(_ text: String, systemImage: String, active: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 12))
            Image(systemName: "chevron.down")
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(active ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
        .cornerRadius(4)
    }

    private var sizeLabel: String {
        if appState.filterSizeMin == nil && appState.filterSizeMax == nil { return "Size" }
        if let min = appState.filterSizeMin, let max = appState.filterSizeMax {
            return "\(formatBytes(min))-\(formatBytes(max))"
        }
        if let min = appState.filterSizeMin { return "> \(formatBytes(min))" }
        if let max = appState.filterSizeMax { return "< \(formatBytes(max))" }
        return "Size"
    }

    private var dateLabel: String {
        guard let after = appState.filterModifiedAfter else { return "Date" }
        if Calendar.current.isDateInToday(after) { return "Today" }
        if Calendar.current.isDateInYesterday(after) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .none
        return "Since \(fmt.string(from: after))"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func modeLabel(_ mode: SearchMode) -> String {
        switch mode {
        case .exact: "Exact"
        case .contains: "Contains"
        case .prefix: "Prefix"
        case .pathContains: "Path"
        }
    }

    private let commonExtensions = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "txt", "md", "json", "xml", "csv",
        "png", "jpg", "jpeg", "gif", "svg", "heic", "webp",
        "mp3", "wav", "flac", "m4a", "aac",
        "mp4", "mov", "avi", "mkv", "webm",
        "zip", "tar", "gz", "dmg", "pkg",
        "swift", "py", "js", "ts", "jsx", "tsx", "html", "css",
    ]

    private let sizePresets: [(label: String, min: Int64?, max: Int64?)] = [
        ("Tiny (< 10 KB)", nil, 10_000),
        ("Small (< 1 MB)", nil, 1_000_000),
        ("Medium (1-10 MB)", 1_000_000, 10_000_000),
        ("Large (10-100 MB)", 10_000_000, 100_000_000),
        ("Huge (> 100 MB)", 100_000_000, nil),
    ]

    private let datePresets: [(label: String, date: Date)] = [
        ("Today", Calendar.current.startOfDay(for: Date())),
        ("Past 7 days", Calendar.current.date(byAdding: .day, value: -7, to: Date())!),
        ("Past 30 days", Calendar.current.date(byAdding: .day, value: -30, to: Date())!),
        ("This year", Calendar.current.date(from: Calendar.current.dateComponents([.year], from: Date()))!),
    ]
}

// MARK: - Results Header

struct ResultsHeaderView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            sortableColumn("Name", field: .name, width: 200)
            sortableColumn("Path", field: nil, width: nil)
            Spacer()
            sortableColumn("Size", field: .size, width: 80)
            sortableColumn("Modified", field: .date, width: 140)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
        .background(Color.primary.opacity(0.04))
    }

    private func sortableColumn(_ title: String, field: SortField?, width: CGFloat?) -> some View {
        HStack(spacing: 4) {
            if let field {
                Button(action: {
                    if appState.sortBy == field {
                        appState.sortAscending.toggle()
                    } else {
                        appState.sortBy = field
                        appState.sortAscending = false
                    }
                    appState.performSearch()
                }) {
                    HStack(spacing: 2) {
                        Text(title)
                        if appState.sortBy == field {
                            Image(systemName: appState.sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(title)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

// MARK: - Results List

struct ResultsListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            if appState.isLoading && appState.searchResults.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Searching...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 60)
            } else if appState.searchResults.isEmpty && !appState.searchText.isEmpty {
                emptyState
            } else if appState.searchResults.isEmpty && appState.scanPaths.isEmpty {
                welcomeState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if appState.searchText.isEmpty && !appState.recentFiles.isEmpty {
                            recentSection
                        }

                        ForEach(Array(appState.searchResults.enumerated()), id: \.element.id) { index, item in
                            ResultRowView(
                                item: item,
                                isSelected: appState.selectedIndex == index,
                                onOpen: { appState.openFile(item) },
                                onReveal: { appState.revealInFinder(item) },
                                onCopyPath: { appState.copyPath(item) },
                                onQuickLook: { appState.toggleQuickLook(for: item) }
                            )
                            .id(item.id)
                            .onTapGesture {
                                appState.selectedIndex = index
                                appState.selectedItem = item
                            }
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .onChange(of: appState.selectedIndex) { _, newIndex in
                    if let idx = newIndex, let item = appState.searchResults[safe: idx] {
                        withAnimation { proxy.scrollTo(item.id, anchor: .center) }
                    }
                }
                .onKeyPress(.upArrow) {
                    navigateUp()
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    navigateDown()
                    return .handled
                }
                .onKeyPress(.return) {
                    if let item = appState.selectedItem { appState.openFile(item) }
                    return .handled
                }
                .onKeyPress(.space) {
                    if let item = appState.selectedItem { appState.toggleQuickLook(for: item) }
                    return .handled
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Text("Recent Files")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            ForEach(Array(appState.recentFiles.prefix(5).enumerated()), id: \.element.id) { index, item in
                ResultRowView(
                    item: item,
                    isSelected: false,
                    onOpen: { appState.openFile(item) },
                    onReveal: { appState.revealInFinder(item) },
                    onCopyPath: { appState.copyPath(item) },
                    onQuickLook: { appState.toggleQuickLook(for: item) }
                )
                .onTapGesture {
                    appState.selectedItem = item
                }
                if index < min(appState.recentFiles.count, 5) - 1 {
                    Divider().padding(.leading, 50)
                }
            }
            Divider()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No results found")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Try adjusting your search terms or filters")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 80)
    }

    private var welcomeState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Welcome to MCFinder")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Add folders to start searching your files instantly.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button(action: { Task { await appState.addFolderToIndex() } }) {
                    Label("Add Folder...", systemImage: "plus")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                Button(action: { appState.openSettings() }) {
                    Label("Settings", systemImage: "gear")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    private func navigateUp() {
        guard !appState.searchResults.isEmpty else { return }
        let current = appState.selectedIndex ?? 0
        appState.selectedIndex = current > 0 ? current - 1 : appState.searchResults.count - 1
        appState.selectedItem = appState.searchResults[safe: appState.selectedIndex!]
    }

    private func navigateDown() {
        guard !appState.searchResults.isEmpty else { return }
        let current = appState.selectedIndex ?? -1
        appState.selectedIndex = current < appState.searchResults.count - 1 ? current + 1 : 0
        appState.selectedItem = appState.searchResults[safe: appState.selectedIndex!]
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