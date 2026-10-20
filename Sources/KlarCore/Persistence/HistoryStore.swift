import Foundation
import CryptoKit
import SQLite3
import OSLog

public struct HistoryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var original: String
    public var response: CoachResponse?
    public var editedPrompt: String?
    /// Nil denotes an older entry; an empty dictionary preserves deliberately cleared suggestions.
    public var inputValues: [String: String]?
    /// Exact multi-choice selections; the rendered sentence alone can be ambiguous.
    public var inputSelections: [String: [String]]?
    public var outcome: String
    public var practiceAttempts: [PracticeAttempt]
    public init(id: UUID = UUID(), createdAt: Date = Date(), original: String, response: CoachResponse? = nil, editedPrompt: String? = nil, inputValues: [String: String]? = nil, inputSelections: [String: [String]]? = nil, outcome: String = "completed", practiceAttempts: [PracticeAttempt] = []) {
        self.id = id; self.createdAt = createdAt; self.original = original; self.response = response
        self.editedPrompt = editedPrompt; self.outcome = outcome; self.practiceAttempts = practiceAttempts
        self.inputValues = inputValues
        self.inputSelections = inputSelections
    }
    public var visiblePrompt: String { editedPrompt ?? response.map { $0.filled(with: inputValues ?? $0.suggestedInputValues).prompt } ?? "" }
    public var annotationsAreCurrent: Bool { editedPrompt == nil }
}

public enum HistoryStoreError: LocalizedError {
    case unavailable, unsupportedVersion, invalidData
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "Der lokale Verlauf konnte nicht gespeichert oder gelesen werden. Dein Text bleibt in diesem Fenster erhalten."
        case .unsupportedVersion: return "Dieser Verlauf stammt aus einer neueren Sinnfaden-Version und wurde nicht verändert."
        case .invalidData: return "Ein lokaler Eintrag ist beschädigt. Die gespeicherten Daten wurden nicht verändert."
        }
    }
}

/// One SQLite file per stable provider/account identity. No credentials are accepted by this type.
public final class HistoryStore: @unchecked Sendable {
    public static let schemaVersion = 1
    private static let log = Logger(subsystem: "at.klar.promptcoach", category: "history-storage")
    public let databaseURL: URL
    private var database: OpaquePointer?
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(accountID: String, baseURL: URL? = nil) throws {
        guard !accountID.isEmpty else { throw HistoryStoreError.invalidData }
        encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let root = try baseURL ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("KLAR", isDirectory: true)
        let digest = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = root.appendingPathComponent("Accounts", isDirectory: true).appendingPathComponent(digest, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        databaseURL = directory.appendingPathComponent("history.sqlite")
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            database = nil
            throw HistoryStoreError.unavailable
        }
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
            sqlite3_busy_timeout(database, 3_000)
            try execute("PRAGMA secure_delete=ON")
            let version = try scalarInteger("PRAGMA user_version")
            guard version <= Self.schemaVersion else { throw HistoryStoreError.unsupportedVersion }
            if version == 0 {
                try execute("BEGIN IMMEDIATE")
                do {
                    try execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY NOT NULL, value BLOB NOT NULL)")
                    try execute("CREATE TABLE IF NOT EXISTS history (id TEXT PRIMARY KEY NOT NULL, created_at REAL NOT NULL, payload BLOB NOT NULL)")
                    try execute("PRAGMA user_version=1")
                    try execute("COMMIT")
                } catch { try? execute("ROLLBACK"); throw error }
            }
        } catch {
            sqlite3_close(database); database = nil; throw error
        }
    }
    deinit { if let database { sqlite3_close(database) } }

    public func loadDraft() throws -> String {
        try synchronized {
            let statement = try prepare("SELECT value FROM metadata WHERE key='draft'")
            defer { sqlite3_finalize(statement) }
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return "" }
            guard status == SQLITE_ROW, let value = String(data: data(statement, column: 0), encoding: .utf8) else { throw HistoryStoreError.invalidData }
            return value
        }
    }

    public func saveDraft(_ text: String) throws {
        try synchronized {
            guard text.utf8.count <= 512_000 else { throw HistoryStoreError.invalidData }
            let statement = try prepare("INSERT INTO metadata(key,value) VALUES('draft',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
            defer { sqlite3_finalize(statement) }
            try bind(Data(text.utf8), to: statement, index: 1)
            try finish(statement)
        }
    }

    public func entries() throws -> [HistoryEntry] {
        try synchronized { try readEntries() }
    }

    public func save(_ entry: HistoryEntry) throws {
        try synchronized {
            let payload = try encoder.encode(entry)
            guard payload.count <= 2_000_000 else { throw HistoryStoreError.invalidData }
            let statement = try prepare("INSERT INTO history(id,created_at,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET created_at=excluded.created_at,payload=excluded.payload")
            defer { sqlite3_finalize(statement) }
            guard sqlite3_bind_text(statement, 1, entry.id.uuidString, -1, transient) == SQLITE_OK,
                  sqlite3_bind_double(statement, 2, entry.createdAt.timeIntervalSince1970) == SQLITE_OK else { throw HistoryStoreError.unavailable }
            try bind(payload, to: statement, index: 3)
            try finish(statement)
        }
    }

    /// Clears this account's draft, attempts and history. Does not touch another account or the Keychain.
    public func deleteAll() throws {
        try synchronized {
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("DELETE FROM history")
                try execute("DELETE FROM metadata")
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
            // Deletion is already committed, with secure_delete enabled. Compaction is
            // optional maintenance: reporting it as a failed deletion can resurrect
            // the caller's pending entries on its next save.
            do { try execute("VACUUM") }
            catch { Self.log.warning("history_compaction_failed_after_delete") }
        }
    }

    public func exportData() throws -> Data {
        try synchronized {
            let statement = try prepare("SELECT value FROM metadata WHERE key='draft'")
            defer { sqlite3_finalize(statement) }
            let status = sqlite3_step(statement)
            guard status == SQLITE_ROW || status == SQLITE_DONE else { throw HistoryStoreError.unavailable }
            let draft = status == SQLITE_ROW ? String(data: data(statement, column: 0), encoding: .utf8) : ""
            guard let draft else { throw HistoryStoreError.invalidData }
            return try Self.exportData(draft: draft, entries: readEntries())
        }
    }

    /// Also exports recoverable in-memory edits when disk writes are unavailable.
    public static func exportData(draft: String, entries: [HistoryEntry], includesCompleteStoredHistory: Bool = true) throws -> Data {
        struct Export: Encodable {
            let schemaVersion: Int
            let exportedAt: Date
            let draft: String
            let entries: [HistoryEntry]
            let includesCompleteStoredHistory: Bool
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Export(schemaVersion: schemaVersion, exportedAt: Date(), draft: draft,
                                         entries: entries, includesCompleteStoredHistory: includesCompleteStoredHistory))
    }

    private func synchronized<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }
    private func readEntries() throws -> [HistoryEntry] {
        let statement = try prepare("SELECT payload FROM history ORDER BY created_at DESC,id DESC")
        defer { sqlite3_finalize(statement) }
        var result: [HistoryEntry] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw HistoryStoreError.unavailable }
            do { result.append(try decoder.decode(HistoryEntry.self, from: data(statement, column: 0))) }
            catch { throw HistoryStoreError.invalidData }
        }
        return result
    }
    private func data(_ statement: OpaquePointer, column: Int32) -> Data {
        guard let pointer = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: pointer, count: Int(sqlite3_column_bytes(statement, column)))
    }
    private func bind(_ data: Data, to statement: OpaquePointer, index: Int32) throws {
        let status = data.withUnsafeBytes { bytes in sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), transient) }
        guard status == SQLITE_OK else { throw HistoryStoreError.unavailable }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw HistoryStoreError.unavailable }
        return statement
    }
    private func finish(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw HistoryStoreError.unavailable }
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw HistoryStoreError.unavailable }
    }
    private func scalarInteger(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw HistoryStoreError.unavailable }
        return Int(sqlite3_column_int(statement, 0))
    }
}
