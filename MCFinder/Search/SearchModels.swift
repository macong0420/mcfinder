import Foundation

enum SearchMode: String, CaseIterable {
    case fts5
    case substring
    case exact
}

enum FileTypeFilter: String, CaseIterable {
    case all
    case documents
    case images
    case audio
    case video
    case archives
    case applications
    case folders
    case other

    var label: String {
        switch self {
        case .all: "All"
        case .documents: "Documents"
        case .images: "Images"
        case .audio: "Audio"
        case .video: "Video"
        case .archives: "Archives"
        case .applications: "Apps"
        case .folders: "Folders"
        case .other: "Other"
        }
    }
}

enum SortField: String, CaseIterable {
    case name
    case date
    case size
    case kind

    var label: String {
        switch self {
        case .name: "Name"
        case .date: "Date"
        case .size: "Size"
        case .kind: "Kind"
        }
    }
}

struct SearchFilter: Equatable, Sendable {
    var fileExtension: String = ""
    var fileType: FileTypeFilter = .all
    var sizeMin: Int64?
    var sizeMax: Int64?
    var modifiedAfter: Date?

    var isEmpty: Bool {
        fileExtension.isEmpty && fileType == .all && sizeMin == nil && sizeMax == nil && modifiedAfter == nil
    }

    var requiresFileTableFilter: Bool {
        fileExtension.isEmpty == false || fileType != .all || sizeMin != nil || sizeMax != nil || modifiedAfter != nil
    }
}
