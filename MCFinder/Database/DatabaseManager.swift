import Foundation
import SQLite3
import OSLog

/// `SQLITE_TRANSIENT` tells SQLite to copy the bound string immediately.
/// We must use this — not `nil` (== `SQLITE_STATIC`) — because the bound
/// pointer comes from a temporary `NSString` bridge that is released as
/// soon as `bind_text` returns. Using `SQLITE_STATIC` writes dangling
/// memory into the row and is the reason previously-indexed files
/// looked "stored" but were unsearchable.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thread-safe wrapper around a single SQLite connection.
///
/// All sqlite3_* calls are funneled through `dbQueue` so we never violate
/// the connection's "one thread at a time" invariant. The crash
/// `BUG IN CLIENT OF libsqlite3.dylib: illegal multi-threaded access to
/// database connection` is what happens when this rule is broken.
///
/// Public methods are safe to call from any thread/queue. Re-entrant calls
/// from inside the queue must use the private `_unsafe*` helpers — calling
/// a public method recursively from within `dbQueue` would deadlock.
final class DatabaseManager: @unchecked Sendable {
    private let dbQueue: DispatchQueue
    private var db: OpaquePointer?

    init() {
        dbQueue = DispatchQueue(label: "com.mcfinder.db", qos: .userInitiated)
        dbQueue.sync {
            self._openDatabase()
            self._configureDatabase()
            self._createSchema()
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Open / Configure (must run on dbQueue)

    private func _openDatabase() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("MCFinder")
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        let dbPath = dbDir.appendingPathComponent("mcfinder.db").path

        // Open in full-mutex (serialized) mode. We additionally serialize
        // through `dbQueue`, but FULLMUTEX is a defense-in-depth measure
        // against any Apple-framework code that touches the handle.
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(dbPath, &db, flags, nil) != SQLITE_OK {
            db = nil
            return
        }
    }

    private func _configureDatabase() {
        guard let db else { return }
        let pragmas: [(String, String)] = [
            ("journal_mode", "WAL"),
            ("synchronous", "NORMAL"),
            ("cache_size", "-20000"),
            ("mmap_size", "268435456"),
            ("temp_store", "MEMORY"),
            ("foreign_keys", "ON"),
            ("busy_timeout", "5000"),
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
        dbQueue.sync { _createSchema() }
    }

    private func _createSchema() {
        guard db != nil else { return }

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

        _executeRaw(createFiles)
        _executeRaw(createFTS)
        _executeRaw(triggerInsert)
        _executeRaw(triggerDelete)
        _executeRaw(triggerUpdate)
        for idx in indexes { _executeRaw(idx) }
    }

    // MARK: - Public Execute API (thread-safe)

    func execute<T>(_ sql: String, parameters: [DatabaseValue] = [], body: (OpaquePointer) throws -> T) throws -> T {
        try dbQueue.sync { try _execute(sql, parameters: parameters, body: body) }
    }

    func executeWrite(_ sql: String, parameters: [DatabaseValue] = []) throws {
        try dbQueue.sync { try _executeWrite(sql, parameters: parameters) }
    }

    func executeQuery<T>(_ sql: String, parameters: [DatabaseValue] = [], mapper: (OpaquePointer) throws -> T) throws -> [T] {
        try dbQueue.sync { try _executeQuery(sql, parameters: parameters, mapper: mapper) }
    }

    func executeBatchWrite(_ statements: [(sql: String, params: [DatabaseValue])]) throws {
        try dbQueue.sync {
            _executeRaw("BEGIN TRANSACTION")
            do {
                for (sql, params) in statements {
                    try _executeWrite(sql, parameters: params)
                }
                _executeRaw("COMMIT")
            } catch {
                _executeRaw("ROLLBACK")
                throw error
            }
        }
    }

    // MARK: - Internal Execute (caller must already hold dbQueue)

    private func _execute<T>(_ sql: String, parameters: [DatabaseValue], body: (OpaquePointer) throws -> T) throws -> T {
        guard let db else { throw DatabaseError.notOpen }

        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK, let statement = stmt else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(errorMsg)
        }
        defer { sqlite3_finalize(statement) }

        try _bind(parameters, to: statement)

        let stepResult = sqlite3_step(statement)
        if stepResult == SQLITE_ROW || stepResult == SQLITE_DONE {
            return try body(statement)
        }

        let errorMsg = String(cString: sqlite3_errmsg(db))
        throw DatabaseError.executionFailed(errorMsg)
    }

    private func _executeWrite(_ sql: String, parameters: [DatabaseValue]) throws {
        guard let db else { throw DatabaseError.notOpen }

        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK, let statement = stmt else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(errorMsg)
        }
        defer { sqlite3_finalize(statement) }

        try _bind(parameters, to: statement)

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE || stepResult == SQLITE_ROW else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.executionFailed(errorMsg)
        }
    }

    private func _executeQuery<T>(_ sql: String, parameters: [DatabaseValue], mapper: (OpaquePointer) throws -> T) throws -> [T] {
        guard let db else { throw DatabaseError.notOpen }

        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard result == SQLITE_OK, let statement = stmt else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.prepareFailed(errorMsg)
        }
        defer { sqlite3_finalize(statement) }

        try _bind(parameters, to: statement)

        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(try mapper(statement))
        }
        return results
    }

    private func _bind(_ parameters: [DatabaseValue], to statement: OpaquePointer) throws {
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
                // SQLITE_TRANSIENT: SQLite copies the bytes immediately.
                // Required because the UTF-8 buffer below is owned by a
                // temporary; using SQLITE_STATIC (nil) corrupts the row.
                sqlite3_bind_text(statement, idx, v, -1, SQLITE_TRANSIENT)
            }
        }
    }

    private func _executeRaw(_ sql: String) {
        guard let db else { return }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let msg = errMsg {
                sqlite3_free(msg)
            }
        }
    }

    // MARK: - File Operations (thread-safe)

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
        guard !paths.isEmpty else { return }
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
        try dbQueue.sync {
            try _executeWrite("DELETE FROM files", parameters: [])
            try _executeWrite("INSERT INTO files_fts(files_fts) VALUES('rebuild')", parameters: [])
        }
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
            return try execute(
                "SELECT (SELECT COUNT(*) FROM files), (SELECT COUNT(*) FROM files_fts)", parameters: []
            ) { stmt in
                (Int(sqlite3_column_int(stmt, 0)), Int(sqlite3_column_int(stmt, 1)))
            }
        } catch {
            return (0, 0)
        }
    }

    // MARK: - Thread-Safe Execution Helpers

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
