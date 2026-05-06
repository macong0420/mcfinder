import AppKit
import UniformTypeIdentifiers

enum FileKind: String {
    case document = "Document"
    case image = "Image"
    case audio = "Audio"
    case video = "Video"
    case archive = "Archive"
    case application = "Application"
    case folder = "Folder"
    case other = "Other"
}

struct FileTypeDetector {
    private static let kindMap: [String: FileKind] = {
        let mappings: [(FileKind, [String])] = [
            (.document, ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "csv", "md", "markdown", "json", "xml", "yaml", "yml", "plist", "strings", "log", "pages", "numbers", "key"]),
            (.image, ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "svg", "heic", "heif", "ico", "icns", "psd", "ai", "raw", "cr2", "nef"]),
            (.audio, ["mp3", "aac", "wav", "flac", "ogg", "wma", "m4a", "aiff", "alac", "mid", "midi"]),
            (.video, ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v", "3gp"]),
            (.archive, ["zip", "tar", "gz", "bz2", "xz", "7z", "rar", "dmg", "iso", "pkg", "tgz"]),
            (.application, ["app", "dylib", "framework", "bundle", "xip"]),
            (.folder, [""]),
        ]
        var map: [String: FileKind] = [:]
        for (kind, exts) in mappings {
            for ext in exts {
                map[ext] = kind
            }
        }
        return map
    }()

    static let excludedNames: Set<String> = [
        ".DS_Store", ".localized", ".fseventsd", ".Spotlight-V100",
        ".Trashes", ".TemporaryItems", "__pycache__", ".git"
    ]

    static func detect(extension ext: String) -> FileKind {
        kindMap[ext.lowercased()] ?? .other
    }

    static func detect(url: URL) -> FileKind {
        let ext = url.pathExtension
        return detect(extension: ext)
    }

    static func systemIcon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    static func isExcluded(url: URL) -> Bool {
        excludedNames.contains(url.lastPathComponent)
    }
}
