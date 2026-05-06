import AppKit
import Foundation

final class BookmarkManager {
    private let defaultsKey = "MCFinder.securityScopedBookmarks"
    private let autoEntitlementKey = "MCFinder.autoEntitlementPaths"

    /// Paths that are automatically accessible via sandbox entitlements.
    /// No security-scoped bookmark is needed for these.
    private static let autoEntitlementRoots: Set<String> = {
        let fm = FileManager.default
        var paths: [String] = []
        if let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first {
            paths.append(desktop.path)
        }
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            paths.append(documents.path)
        }
        if let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            paths.append(downloads.path)
        }
        return Set(paths)
    }()

    /// Returns `true` if `url` is (or is inside) ~/Desktop, ~/Documents, or ~/Downloads.
    static func isAutoEntitlementPath(_ url: URL) -> Bool {
        let path = url.path
        for root in autoEntitlementRoots {
            if path == root || path.hasPrefix(root + "/") {
                return true
            }
        }
        return false
    }

    // MARK: - Auto-entitlement path tracking

    /// Stores paths that are indexed via entitlements (no bookmark needed).
    /// These are persisted so they appear in the settings UI across launches.
    private var autoEntitlementStore: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: autoEntitlementKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: autoEntitlementKey) }
    }

    func saveAutoEntitlementPath(_ path: String) {
        var current = autoEntitlementStore
        current.insert(path)
        autoEntitlementStore = current
    }

    func removeAutoEntitlementPath(_ path: String) {
        var current = autoEntitlementStore
        current.remove(path)
        autoEntitlementStore = current
    }

    func allAutoEntitlementPaths() -> [String] {
        Array(autoEntitlementStore)
    }

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
            // Skip auto-entitlement paths — they don't need bookmarks.
            // Also clean up any stale bookmarks that were saved before this check.
            let url = URL(fileURLWithPath: path)
            if Self.isAutoEntitlementPath(url) {
                removeBookmark(forPath: path)
                resolved.append(url)
                continue
            }
            do {
                let resolvedURL = try resolveAndStartAccessing(data)
                resolved.append(resolvedURL)
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
    static func promptUserToSelectFolders() async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Select folders to index"
        panel.prompt = "Add"

        let response = await panel.begin()
        guard response == .OK else { return [] }
        return panel.urls
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
