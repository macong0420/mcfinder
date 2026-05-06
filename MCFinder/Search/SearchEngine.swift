import Foundation
import SQLite3

final class SearchEngine {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    struct SearchResult {
        let items: [SearchResultItem]
        let totalCount: Int
        let searchTime: TimeInterval
    }

    func search(
        text: String,
        filter: SearchFilter = SearchFilter(),
        sort: SortField = .date,
        ascending: Bool = false,
        mode: SearchMode = .fts5,
        limit: Int = 200
    ) throws -> SearchResult {
        let startTime = Date()
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let (query, params) = buildQuery(text: trimmedText, filter: filter, sort: sort, ascending: ascending, mode: mode, limit: limit)

        let items: [SearchResultItem] = try databaseManager.executeQuery(query, parameters: params) { stmt in
            SearchResultItem(
                id: sqlite3_column_int64(stmt, 0),
                name: String(cString: sqlite3_column_text(stmt, 1)),
                path: String(cString: sqlite3_column_text(stmt, 2)),
                parentPath: String(cString: sqlite3_column_text(stmt, 3)),
                extension: String(cString: sqlite3_column_text(stmt, 4)),
                size: sqlite3_column_int64(stmt, 5),
                modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
                isDirectory: sqlite3_column_int(stmt, 8) != 0,
                rank: sqlite3_column_double(stmt, 9)
            )
        }

        let elapsed = Date().timeIntervalSince(startTime)
        return SearchResult(items: items, totalCount: items.count, searchTime: elapsed)
    }

    // MARK: - Query Building

    private func buildQuery(
        text: String,
        filter: SearchFilter,
        sort: SortField,
        ascending: Bool,
        mode: SearchMode,
        limit: Int
    ) -> (String, [DatabaseValue]) {
        var params: [DatabaseValue] = []

        let rankExpr = rankScoringExpression(text: text, mode: mode, params: &params)
        let selectClause = """
        SELECT f.id, f.name, f.path, f.parent_path, f.extension, f.size, f.modified_at, f.created_at, f.is_directory, (\(rankExpr)) AS rank
        """

        var fromClause = "FROM files f"
        var whereClauses: [String] = []

        if !text.isEmpty {
            let (ftsClause, ftsParams) = buildFTSMatch(text: text, mode: mode)
            fromClause += " LEFT JOIN files_fts ON f.id = files_fts.rowid"
            whereClauses.append(ftsClause)
            params.append(contentsOf: ftsParams)
        }

        let filterResult = buildFilterClause(filter: filter)
        if !filterResult.clause.isEmpty {
            whereClauses.append(filterResult.clause)
            params.append(contentsOf: filterResult.params)
        }

        let whereClause = whereClauses.isEmpty ? "" : "WHERE " + whereClauses.joined(separator: " AND ")
        let orderClause = buildOrderClause(sort: sort, ascending: ascending)

        return ("\(selectClause) \(fromClause) \(whereClause) \(orderClause) LIMIT \(limit)", params)
    }

    private func buildFTSMatch(text: String, mode: SearchMode) -> (String, [DatabaseValue]) {
        switch mode {
        case .fts5:
            return ("files_fts MATCH ?", [.text(buildFTS5Query(from: text))])
        case .substring:
            return ("(LOWER(f.name) LIKE ? ESCAPE '\\' OR LOWER(f.path) LIKE ? ESCAPE '\\')", [
                .text("%" + escapeLikeWildcards(text.lowercased()) + "%"),
                .text("%" + escapeLikeWildcards(text.lowercased()) + "%"),
            ])
        case .exact:
            return ("(LOWER(f.name) = ? OR LOWER(f.path) = ?)", [
                .text(text.lowercased()),
                .text(text.lowercased()),
            ])
        }
    }

    private func buildFilterClause(filter: SearchFilter) -> (clause: String, params: [DatabaseValue]) {
        var clauses: [String] = []
        var params: [DatabaseValue] = []

        if !filter.fileExtension.isEmpty {
            clauses.append("LOWER(f.extension) = LOWER(?)")
            params.append(.text(filter.fileExtension))
        }

        if filter.fileType != .all {
            switch filter.fileType {
            case .folders:
                clauses.append("f.is_directory = 1")
            default:
                clauses.append("f.is_directory = 0")
                let exts = fileTypeExtensions(filter.fileType)
                if !exts.isEmpty {
                    let placeholders = exts.map { _ in "LOWER(?)" }.joined(separator: ",")
                    clauses.append("LOWER(f.extension) IN (\(placeholders))")
                    params.append(contentsOf: exts.map { .text($0) })
                }
            }
        }

        if let minSize = filter.sizeMin {
            clauses.append("f.size >= ?")
            params.append(.integer(minSize))
        }
        if let maxSize = filter.sizeMax {
            clauses.append("f.size <= ?")
            params.append(.integer(maxSize))
        }
        if let after = filter.modifiedAfter {
            clauses.append("f.modified_at >= ?")
            params.append(.real(after.timeIntervalSince1970))
        }

        return (clauses.joined(separator: " AND "), params)
    }

    private func fileTypeExtensions(_ type: FileTypeFilter) -> [String] {
        switch type {
        case .documents: return ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "csv", "md", "json", "xml", "yaml", "yml", "pages", "numbers", "key"]
        case .images: return ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "svg", "heic", "heif", "ico", "icns", "psd"]
        case .audio: return ["mp3", "aac", "wav", "flac", "ogg", "m4a", "aiff", "mid"]
        case .video: return ["mp4", "mov", "avi", "mkv", "wmv", "webm", "m4v"]
        case .archives: return ["zip", "tar", "gz", "bz2", "xz", "7z", "rar", "dmg", "iso", "pkg", "tgz"]
        case .applications: return ["app"]
        default: return []
        }
    }

    private func buildOrderClause(sort: SortField, ascending: Bool) -> String {
        let direction = ascending ? "ASC" : "DESC"
        switch sort {
        case .name: return "ORDER BY LOWER(f.name) \(direction), rank DESC"
        case .date: return "ORDER BY f.modified_at \(direction), rank DESC"
        case .size: return "ORDER BY f.size \(direction), rank DESC"
        case .kind: return "ORDER BY f.extension \(direction), LOWER(f.name) ASC, rank DESC"
        }
    }

    // MARK: - FTS5 Query

    func buildFTS5Query(from text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }

        var tokens: [String] = []
        var inQuote = false
        var current = ""

        for char in cleaned {
            if char == "\"" {
                inQuote.toggle()
                if !inQuote, !current.isEmpty {
                    tokens.append("\"" + escapeFTS5Phrase(current) + "\"")
                    current = ""
                }
            } else if char.isWhitespace, !inQuote {
                if !current.isEmpty {
                    tokens.append(sanitizeFTS5Token(current) + "*")
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            if inQuote {
                tokens.append("\"" + escapeFTS5Phrase(current) + "\"")
            } else {
                tokens.append(sanitizeFTS5Token(current) + "*")
            }
        }

        return tokens.isEmpty ? "" : tokens.joined(separator: " AND ")
    }

    private func sanitizeFTS5Token(_ token: String) -> String {
        token.replacingOccurrences(of: "\"", with: "\"\"")
    }

    private func escapeFTS5Phrase(_ phrase: String) -> String {
        phrase.replacingOccurrences(of: "\"", with: "\"\"")
    }

    private func escapeLikeWildcards(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: - Ranking

    private func rankScoringExpression(text: String, mode: SearchMode, params: inout [DatabaseValue]) -> String {
        if text.isEmpty { return "1.0" }

        let lowerText = text.lowercased()
        params.append(.text(lowerText))
        params.append(.text(lowerText + "%"))

        switch mode {
        case .exact:
            return "CASE WHEN LOWER(f.name) = ? THEN 100 WHEN LOWER(f.name) LIKE ? ESCAPE '\\' THEN 60 ELSE 1 END"
        case .substring:
            return "CASE WHEN LOWER(f.name) = ? THEN 100 WHEN LOWER(f.name) LIKE ? ESCAPE '\\' THEN 60 ELSE 10 END"
        case .fts5:
            return "CASE WHEN LOWER(f.name) = ? THEN 100 WHEN LOWER(f.name) LIKE ? ESCAPE '\\' THEN 80 ELSE 0 END + COALESCE(files_fts.rank, 0.0)"
        }
    }
}
