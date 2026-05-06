import Foundation
import SQLite3
import OSLog

final class DatabaseManager: @unchecked Sendable {
    private let dbQueue: DispatchQueue
    private var db: OpaquePointer?

    init() {
        dbQueue = DispatchQueue(label: "com.mcfinder.db", qos: .userInitiated)
        dbQueue.sync {
            self.openDatabase()
            self.configureDatabase()
            self.createSchema()
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Open / Configure

    private func openDatabase() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("MCFinder")
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("mcfinder.db").path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            // Logger.database.error("Failed to open database at \(dbPath)")
            return
        }
        // Logger.database.info("Database opened at \(dbPath)")
    }

    private func configureDatabase() {
        guard let db else { return }
        let pragmas: [(String, String)] = [
            ("journal_mode", "WAL"),
            ("synchronous", "NORMAL"),
            ("cache_size", "-20000"),
            ("mmap_size", "268435456"),
            ("temp_store", "MEMORY"),
            ("foreign_keys", "ON"),
        ]
        for (key, value) in pragmas {
            var stmt: OpaquePointer?
            let sql = "PRAGMA \(key)=\(value)"
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }
    }

    // MARK: - Schema

    func createSchema() {
        guard let db else { return }

        let createFiles = """
        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            parent_path TEXT NOT NULL,
            extension TEXT NOT NULL DEFAULT '',
            size INTEGER NOT NULL DEFAULT 0,
            modified_at REAL NOT NULL DEFAULT 0,
            created_at REAL NOT NULL DEFAULT 0,
            is_directory INTEGER NOT NULL DEFAULT 0
        );
        """

        let createFTS = """
        CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
            name, path, content=files, content_rowid=id
        );
        """

        let triggerInsert = """
        CREATE TRIGGER IF NOT EXISTS files_ai AFTER INSERT ON files BEGIN
            INSERT INTO files_fts(rowid, name, path) VALUES (new.id, new.name, new.path);
        END;
        """

        let triggerDelete = """
        CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN
            INSERT INTO files_fts(files_fts, rowid, name, path) VALUES ('delete', old.id, old.name, old.path);
        END;
        """

        let triggerUpdate = """
        CREATE TRIGGER IF NOT EXISTS files_au AFTER UPDATE ON files BEGIN
            INSERT INTO files_fts(files_fts, rowid, name, path) VALUES ('delete', old.id, old.name, old.path);
            INSERT INTO files_fts(rowid, name, path) VALUES (new.id, new.name, new.path);
        END;
        """

        let indexes = [
            "CREATE INDEX IF NOT EXISTS idx_extension ON files(extension);",
            "CREATE INDEX IF NOT EXISTS idx_files_name_lower ON files(name COLLATE NOCASE);",
            "CREATE INDEX IF NOT EXISTS idx_is_directory ON files(is_directory);",
            "CREATE INDEX IF NOT EXISTS idx_modified_at ON files(modified_at);",
            "CREATE INDEX IF NOT EXISTS idx_parent_path ON files(parent_path);",
            "CREATE INDEX IF NOT EXISTS idx_size ON files(size);",
        ]

        executeRaw(createFiles)
        executeRaw(createFTS)
        executeRaw(triggerInsert)
        executeRaw(triggerDelete)
        executeRaw(triggerUpdate)
        for idx in indexes { executeRaw(idx) }
    }

    // MARK: - Core Execute Methods

    func execute<T>(_ sql: String, parameters: [DatabaseValue] = [], body: (OpaquePointer) throws -> T) throws -> T {
        guard let db else { throw DatabaseError.notOpen }

        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK, let statement = stmt else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(errorMsg)
        }
        defer { sqlite3_finalize(statement) }

        for (index, param) in parameters.enumerated() {
            let idx = Int32(index + 1)
            switch param {
            case .null:
                sqlite3_bind_null(statement, idx)
            case .integer(let v):
                sqlite3_bind_int64(statement, idx, v)
            case .real(let v):
                sqlite3_bind_double(statement, idx, v)
            case .text(let v):
                sqlite3_bind_text(statement, idx, (v as NSString).utf8String, -1, nil)
            }
        }

        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW || stepResult == SQLITE_DONE {
            return try body(statement)
        }

        let errorMsg = String(cString: sqlite3_errmsg(db))
        throw DatabaseError.executionFailed(errorMsg)
    }

    func executeWrite(_ sql: String, parameters: [DatabaseValue] = []) throws {
        guard let db else { throw DatabaseError.notOpen }

        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK, let statement = stmt else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(errorMsg)
        }
        defer { sqlite3_finalize(statement) }

        for (index, param) in parameters.enumerated() {
            let idx = Int32(index + 1)
            switch param {
            case .null: sqlite3_bind_null(statement, idx)
            case .integer(let v): sqlite3_bind_int64(statement, idx, v)
            case .real(let v): sqlite3_bind_double(statement, idx, v)
            case .text(let v): sqlite3_bind_text(statement, idx, (v as NSString).utf8String, -1, nil)
            }
        }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE || stepResult == SQLITE_ROW else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed(errorMsg)
        }
    }

    func executeQuery<T>(_ sql: String, parameters: [DatabaseValue] = [], mapper: (OpaquePointer) throws -> T) throws -> [T] {
        guard let db else { throw DatabaseError.notOpen }

        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK, let statement = stmt else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(errorMsg)
        }
        defer { sqlite3_finalize(statement) }

        for (index, param) in parameters.enumerated() {
            let idx = Int32(index + 1)
            switch param {
            case .null: sqlite3_bind_null(statement, idx)
            case .integer(let v): sqlite3_bind_int64(statement, idx, v)
            case .real(let v): sqlite3_bind_double(statement, idx, v)
            case .text(let v): sqlite3_bind_text(statement, idx, (v as NSString).utf8String, -1, nil)
            }
        }

        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(try mapper(statement))
        }
        return results
    }

    func executeBatchWrite(_ statements: [(sql: String, params: [DatabaseValue])]) throws {
        guard let db else { throw DatabaseError.notOpen }

        executeRaw("BEGIN TRANSACTION")
        do {
            for (sql, params) in statements {
                try executeWrite(sql, parameters: params)
            }
            executeRaw("COMMIT")
        } catch {
            executeRaw("ROLLBACK")
            throw error
        }
    }

    private func executeRaw(_ sql: String) {
        guard let db else { return }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let msg = errMsg {
                // Logger.database.error("SQL error: \(String(cString: msg))")
                sqlite3_free(msg)
            }
        }
    }

    // MARK: - File Operations

    func insertFiles(_ files: [FileRecord]) throws {
        let sql = """
        INSERT OR REPLACE INTO files (name, path, parent_path, extension, size, modified_at, created_at, is_directory)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        let statements = files.map { f in
            (sql, [
                DatabaseValue.text(f.name),
                DatabaseValue.text(f.path),
                DatabaseValue.text(f.parentPath),
                DatabaseValue.text(f.extension),
                DatabaseValue.integer(f.size),
                DatabaseValue.real(f.modifiedAt.timeIntervalSince1970),
                DatabaseValue.real(f.createdAt.timeIntervalSince1970),
                DatabaseValue.integer(f.isDirectory ? 1 : 0),
            ] as [DatabaseValue])
        }
        try executeBatchWrite(statements)
    }

    func deleteFiles(inPaths paths: [String]) throws {
        let placeholders = paths.map { _ in "?" }.joined(separator: ",")
        let params = paths.map { DatabaseValue.text($0) }
        try executeWrite("DELETE FROM files WHERE path IN (\(placeholders))", parameters: params)
    }

    func deleteFiles(inPathPrefix prefix: String) throws {
        try executeWrite("DELETE FROM files WHERE path >= ? AND path < ?", parameters: [
            .text(prefix),
            .text(prefix + "\u{FFFF}"),
        ])
    }

    func deleteAllFiles() throws {
        try executeWrite("DELETE FROM files", parameters: [])
        try executeWrite("INSERT INTO files_fts(files_fts) VALUES('rebuild')", parameters: [])
    }

    func getPathsInRange(start: String, end: String) throws -> [(path: String, modifiedAt: Double)] {
        try executeQuery(
            "SELECT path, modified_at FROM files WHERE path >= ? AND path < ?",
            parameters: [.text(start), .text(end)]
        ) { stmt in
            let path = String(cString: sqlite3_column_text(stmt, 0))
            let mtime = sqlite3_column_double(stmt, 1)
            return (path, mtime)
        }
    }

    func getAllPathsBatch(limit: Int, offset: Int) throws -> [String] {
        try executeQuery(
            "SELECT path FROM files LIMIT ? OFFSET ?",
            parameters: [.integer(Int64(limit)), .integer(Int64(offset))]
        ) { stmt in
            String(cString: sqlite3_column_text(stmt, 0))
        }
    }

    func totalFileCount() throws -> Int {
        try execute("SELECT COUNT(*) FROM files", parameters: []) { stmt in
            Int(sqlite3_column_int(stmt, 0))
        }
    }

    func checkFTSIntegrity() -> (fileCount: Int, ftsCount: Int) {
        do {
            let fc = try execute(
                "SELECT (SELECT COUNT(*) FROM files), (SELECT COUNT(*) FROM files_fts)", parameters: []
            ) { stmt in
                (Int(sqlite3_column_int(stmt, 0)), Int(sqlite3_column_int(stmt, 1)))
            }
            return fc
        } catch {
            return (0, 0)
        }
    }

    // MARK: - Thread-Safe Execution

    func sync<T>(_ block: () throws -> T) rethrows -> T {
        try dbQueue.sync(execute: block)
    }

    func async(_ block: @escaping () -> Void) {
        dbQueue.async(execute: block)
    }
}

// MARK: - Errors

enum DatabaseError: Error, LocalizedError {
    case notOpen
    case prepareFailed(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notOpen: "Database is not open"
        case .prepareFailed(let msg): "Prepare failed: \(msg)"
        case .executionFailed(let msg): "Execution failed: \(msg)"
        }
    }
}
