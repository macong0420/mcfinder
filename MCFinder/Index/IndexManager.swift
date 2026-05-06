import Foundation
import OSLog

final class IndexManager {
    private let databaseManager: DatabaseManager
    private let searchEngine: SearchEngine
    private let fsEventsMonitor: FSEventsMonitor
    private let bookmarkManager: BookmarkManager
    private let batchSize = 500

    init(
        databaseManager: DatabaseManager,
        searchEngine: SearchEngine,
        fsEventsMonitor: FSEventsMonitor,
        bookmarkManager: BookmarkManager
    ) {
        self.databaseManager = databaseManager
        self.searchEngine = searchEngine
        self.fsEventsMonitor = fsEventsMonitor
        self.bookmarkManager = bookmarkManager
    }

    // MARK: - Full Scan

    func scanDirectories(
        paths: [URL],
        excludedPaths _: [String] = [],
        includeHidden: Bool = false,
        onProgress: (@Sendable (Int) -> Void)?
    ) async throws -> Int {
        var total = 0
        var batch: [FileRecord] = []

        for rootURL in paths {
            let enumerator = FileEnumerator()
            let stream = enumerator.enumerate(at: rootURL, includeHidden: includeHidden)

            do {
                for try await (url, values) in stream {
                    if Task.isCancelled { break }

                    let record = createFileRecord(url: url, values: values)
                    batch.append(record)
                    total += 1

                    if batch.count >= batchSize {
                        try databaseManager.insertFiles(batch)
                        batch.removeAll(keepingCapacity: true)
                        onProgress?(total)
                        await Task.yield()
                    }
                }

                if !batch.isEmpty {
                    try databaseManager.insertFiles(batch)
                    onProgress?(total)
                }
            } catch {
                // Logger.index.error("scanDirectories error: \(error.localizedDescription)")
            }
        }

        if let dbCount = try? databaseManager.totalFileCount() {
            // Logger.index.info("Scan complete. \(total) files processed, \(dbCount) in database")
        } else {
            // Logger.index.info("Scan complete. \(total) files processed")
        }

        return total
    }

    // MARK: - Incremental Update

    func processFSEventChanges(_ changedPaths: Set<String>) async throws {
        let fileManager = FileManager.default

        for path in changedPaths {
            let url = URL(fileURLWithPath: path)

            if fileManager.fileExists(atPath: path) {
                if FileTypeDetector.isExcluded(url: url) { continue }
                guard let values = try? url.resourceValues(forKeys: [
                    .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                    .creationDateKey, .nameKey,
                ]) else { continue }

                let record = createFileRecord(url: url, values: values)
                try databaseManager.insertFiles([record])
            } else {
                try databaseManager.deleteFiles(inPaths: [path])
            }
        }
    }

    // MARK: - Cleanup

    func deleteOrphanedFiles(in rootPaths: [URL]) async throws {
        let fileManager = FileManager.default

        for root in rootPaths {
            let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            let endPrefix = prefix + "\u{FFFF}"

            guard let existing = try? databaseManager.getPathsInRange(start: prefix, end: endPrefix) else {
                continue
            }

            var orphaned: [String] = []
            for (path, _) in existing {
                if !fileManager.fileExists(atPath: path) {
                    orphaned.append(path)
                }
            }

            if !orphaned.isEmpty {
                try databaseManager.deleteFiles(inPaths: orphaned)
                // Logger.index.info("Cleaned up \(orphaned.count) orphaned files from \(root.path)")
            }
        }
    }

    func deleteAll() throws {
        try databaseManager.deleteAllFiles()
    }

    func cleanupRemovedDirectory(at path: String) throws {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        try databaseManager.deleteFiles(inPathPrefix: prefix)
    }

    // MARK: - Helpers

    private func createFileRecord(url: URL, values: URLResourceValues) -> FileRecord {
        FileRecord(
            name: values.name ?? url.lastPathComponent,
            path: url.path,
            parentPath: url.deletingLastPathComponent().path,
            extension: url.pathExtension,
            size: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? Date.distantPast,
            createdAt: values.creationDate ?? Date.distantPast,
            isDirectory: values.isDirectory ?? false
        )
    }
}
