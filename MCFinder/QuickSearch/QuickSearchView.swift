import SwiftUI
import AppKit

struct QuickSearchView: View {
    @ObservedObject var state: QuickSearchState
    var searchEngine: SearchEngine
    var onSelect: (SearchResultItem) -> Void
    var onDismiss: () -> Void

    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if !state.results.isEmpty {
                Divider()
                resultsList
            }
        }
        .frame(width: 600)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .onAppear {
            isSearchFieldFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFieldFocused = true
            }
        }
        .onChange(of: state.searchText) { _, newValue in
            performSearch(query: newValue)
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 18))

            TextField("Search files...", text: Binding(
                get: { state.searchText },
                set: { state.searchText = $0 }
            ))
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .regular))
                .focused($isSearchFieldFocused)
                .onSubmit {
                    if let result = state.highlightedResult {
                        onSelect(result)
                    }
                }

            if !state.searchText.isEmpty {
                Button(action: { state.reset(); isSearchFieldFocused = true }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    // MARK: - Results

    private var resultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(state.results.prefix(8).enumerated()), id: \.element.id) { index, item in
                Button(action: { onSelect(item) }) {
                    resultRow(item: item, isHighlighted: index == state.selectedIndex)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { state.selectedIndex = index }
                }

                if index < min(state.results.count, 8) - 1 {
                    Divider().padding(.leading, 56)
                }
            }

            if state.results.count > 8 {
                Divider()
                HStack {
                    Text("\(state.results.count - 8) more results...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Open MCFinder for all results")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
        }
    }

    private func resultRow(item: SearchResultItem, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: FileTypeDetector.systemIcon(for: URL(fileURLWithPath: item.path)))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                Text(item.path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isHighlighted {
                Text("↩")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(isHighlighted ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    // MARK: - Search

    private func performSearch(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state.results = []
            state.selectedIndex = 0
            return
        }

        do {
            let result = try searchEngine.search(text: query, mode: .fts5, limit: 8)
            state.results = result.items
            state.selectedIndex = 0
        } catch {
            // Logger.app.error("QuickSearch error: \(error)")
        }
    }
}
