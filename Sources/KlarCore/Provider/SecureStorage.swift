import Foundation
import Security
import Darwin

struct SecureStorage: Sendable {
    private let service = "de.klar.promptcoach.credentials.v1"
    private let readData: (@Sendable (String) throws -> Data?)?
    init(readData: (@Sendable (String) throws -> Data?)? = nil) { self.readData = readData }
    func save<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if result == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw failure }
        } else if result != errSecSuccess { throw failure }
    }
    func load<T: Decodable & Sendable>(_ type: T.Type, account: String) async throws -> T? {
        try Task.checkCancellation()
        // Security may wait for a permission dialog. Do not block MainActor or Swift's cooperative pool.
        let data: Data? = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try read(account: account) })
            }
        }
        try Task.checkCancellation()
        guard let data else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }
    private func read(account: String) throws -> Data? {
        if let readData { return try readData(account) }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw failure }
        return data
    }
    func delete(account: String) throws {
        let result = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw failure }
    }
    private var failure: ProviderFailure { .init(.storage, "Der macOS-Schlüsselbund ist nicht zugänglich. Bitte entsperre ihn und versuche es erneut.") }
}

struct RegistrationStore: Codable {
    var version = 1
    var hostID: String
    var accounts: [SavedAccount] = []
    var selectedID: String?
    var pendingClientID: String?
    var lastSignedOutID: String?
    mutating func markSignedOut(_ id: String) {
        if selectedID == id { selectedID = nil }
        lastSignedOutID = id
    }
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("KLAR", isDirectory: true).appendingPathComponent("Connection", isDirectory: true)
    }
    static var url: URL { directory.appendingPathComponent("registrations.json") }
    static func load() throws -> RegistrationStore {
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            let value = try JSONDecoder().decode(Self.self, from: data)
            guard value.version == 1 else { throw ProviderFailure(.storage, "Diese Verbindungsdaten benötigen eine neuere Sinnfaden-Version.") }
            return value
        }
        let value = RegistrationStore(hostID: "urn:uuid:" + UUID().uuidString.lowercased())
        try value.save(); return value
    }
    func save() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: Self.url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
    }
}

/// Shared by the application and probe so rotating refresh tokens cannot race.
final class SessionFileLock {
    private var descriptor: Int32 = -1
    func acquire() async throws {
        let path = RegistrationStore.directory.appendingPathComponent("session.lock").path
        descriptor = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw ProviderFailure(.storage, "Die Verbindung konnte nicht sicher gesperrt werden.") }
        for _ in 0..<600 {
            try Task.checkCancellation()
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ProviderFailure(.unavailable, "Ein anderes Sinnfaden-Fenster erneuert gerade die Verbindung. Bitte versuche es gleich noch einmal.")
    }
    func release() { if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor); descriptor = -1 } }
    deinit { release() }
}
