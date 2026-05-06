import AppKit
import Combine

final class QuickSearchState: ObservableObject {
    @Published var searchText = ""
    @Published var results: [SearchResultItem] = []
    @Published var selectedIndex: Int = 0
    @Published var isVisible: Bool = false

    var highlightedResult: SearchResultItem? {
        guard !results.isEmpty else { return nil }
        let idx = min(max(0, selectedIndex), results.count - 1)
        return results[idx]
    }

    func reset() {
        searchText = ""
        results = []
        selectedIndex = 0
    }

    func navigateUp() {
        guard !results.isEmpty else { return }
        selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : results.count - 1
    }

    func navigateDown() {
        guard !results.isEmpty else { return }
        selectedIndex = selectedIndex < results.count - 1 ? selectedIndex + 1 : 0
    }
}
