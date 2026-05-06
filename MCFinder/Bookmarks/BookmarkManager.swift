import AppKit
import Foundation

final class BookmarkManager {
    private let defaultsKey = "MCFinder.securityScopedBookmarks"

    // MARK: - Persistence

    private var store: [String: Data] {
        get { UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Data] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    func saveBookmark(_ data: Data, forPath path: String) {
        var current = store
        current[path] = data
        store = current
    }

    func removeBookmark(forPath path: String) {
        var current = store
        current.removeValue(forKey: path)
        store = current
    }

    func allBookmarkedPaths() -> [String] {
        Array(store.keys)
    }

    func allBookmarkData() -> [Data] {
        Array(store.values)
    }

    // MARK: - Create / Resolve

    func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    func resolveAndStartAccessing(_ data: Data) throws -> URL {
        let (url, isStale) = try resolveBookmark(data)
        if isStale {
            let newData = try createBookmark(for: url)
            saveBookmark(newData, forPath: url.path)
        }
        guard url.startAccessingSecurityScopedResource() else {
            throw BookmarkError.accessDenied(url.path)
        }
        return url
    }

    func restoreAllBookmarks() -> [URL] {
        var resolved: [URL] = []
        for (path, data) in store {
            do {
                let url = try resolveAndStartAccessing(data)
                resolved.append(url)
            } catch {
            }
        }
        return resolved
    }

    func stopAllAccess(urls: [URL]) {
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - UI

    @MainActor
    static func promptUserToSelectFolder() async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Select folders to index"
        panel.prompt = "Add"

        let response = await panel.begin()
        guard response == .OK else { return nil }
        return panel.url
    }
}

enum BookmarkError: Error, LocalizedError {
    case accessDenied(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied(let path): "Cannot access \(path)"
        }
    }
}
