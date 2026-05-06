import SwiftUI

struct ResultsListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            if appState.isLoading {
                ProgressView("Searching...").padding()
            } else if appState.searchResults.isEmpty && !appState.searchText.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
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
                        withAnimation {
                            proxy.scrollTo(item.id, anchor: .center)
                        }
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
                    if let item = appState.selectedItem {
                        appState.openFile(item)
                    }
                    return .handled
                }
                .onKeyPress(.space) {
                    if let item = appState.selectedItem {
                        appState.toggleQuickLook(for: item)
                    }
                    return .handled
                }
            }
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
