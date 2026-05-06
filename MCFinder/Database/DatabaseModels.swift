import Foundation

struct FileRecord: Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let path: String
    let parentPath: String
    let `extension`: String
    let size: Int64
    let modifiedAt: Date
    let createdAt: Date
    let isDirectory: Bool

    init(id: Int64 = -1, name: String, path: String, parentPath: String, extension ext: String, size: Int64, modifiedAt: Date, createdAt: Date, isDirectory: Bool) {
        self.id = id
        self.name = name
        self.path = path
        self.parentPath = parentPath
        self.extension = ext
        self.size = size
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.isDirectory = isDirectory
    }
}

struct SearchResultItem: Identifiable, Hashable, Sendable {
    let id: Int64
    let name: String
    let path: String
    let parentPath: String
    let `extension`: String
    let size: Int64
    let modifiedAt: Date
    let createdAt: Date
    let isDirectory: Bool
    let rank: Double
}

enum DatabaseValue: Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)

    var sqliteValue: Any {
        switch self {
        case .null: return NSNull()
        case .integer(let v): return v
        case .real(let v): return v
        case .text(let v): return v
        }
    }
}
