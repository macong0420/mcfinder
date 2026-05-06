import Foundation

struct FileEnumerator {
    let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
        .creationDateKey, .nameKey, .pathKey,
    ]

    func enumerate(at root: URL, includeHidden: Bool) -> AsyncThrowingStream<(URL, URLResourceValues), Error> {
        AsyncThrowingStream { continuation in
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: includeHidden ? [] : [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            guard let enumerator else {
                continuation.finish(throwing: EnumeratorError.cannotCreate(root.path))
                return
            }

            enumerator.skipDescendants()

            let task = Task.detached {
                for case let fileURL as URL in enumerator {
                    if Task.isCancelled { break }

                    guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                          let name = values.name else { continue }

                    if FileTypeDetector.isExcluded(url: fileURL) { continue }

                    continuation.yield((fileURL, values))
                    _ = name
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

enum EnumeratorError: Error, LocalizedError {
    case cannotCreate(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreate(let path): "Cannot create enumerator for \(path)"
        }
    }
}
