import SwiftUI

struct SearchBarView: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search files...", text: Binding(
                get: { appState.searchText },
                set: { appState.searchText = $0 }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 16))
            .focused($isFocused)
            .onSubmit { appState.performSearch() }
            .onChange(of: appState.searchText) { _, _ in
                appState.performSearch()
            }

            if !appState.searchText.isEmpty {
                Button(action: { appState.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }

            Picker("Mode", selection: Binding(
                get: { appState.searchMode },
                set: { appState.searchMode = $0; appState.performSearch() }
            )) {
                ForEach(SearchMode.allCases, id: \.self) { mode in
                    Text(modeLabel(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)

            Button(action: { appState.caseSensitive.toggle(); appState.performSearch() }) {
                Image(systemName: appState.caseSensitive ? "textformat.abc" : "textformat")
                    .foregroundColor(appState.caseSensitive ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Case sensitive")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .onAppear {
            isFocused = true
        }
        .onKeyPress(.escape) {
            if !appState.searchText.isEmpty {
                appState.searchText = ""
                return .handled
            }
            return .ignored
        }
    }

    private func modeLabel(_ mode: SearchMode) -> String {
        switch mode {
        case .fts5: "FTS"
        case .substring: "Substr"
        case .exact: "Exact"
        }
    }
}
