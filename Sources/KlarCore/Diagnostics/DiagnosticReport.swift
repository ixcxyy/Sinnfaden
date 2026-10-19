import Foundation
import Combine

public enum DiagnosticArea: String, Codable, Sendable {
    case connection, coach, comparison, followUp, history, learning, updater
}

public enum DiagnosticCategory: String, Codable, Sendable {
    case authentication, permission, unavailable, interrupted, incomplete, invalidResponse, storage, validation, unexpected
}

/// Deliberately contains no free-form error messages, prompts, paths, account identifiers or tokens.
public struct DiagnosticReport: Codable, Identifiable, Equatable, Sendable {
    public enum Delivery: String, Codable, Sendable { case local, pending, sent }
    public let id: UUID
    public let firstSeen: Date
    public var lastSeen: Date
    public var occurrences: Int
    public let area: DiagnosticArea
    public let category: DiagnosticCategory
    public let httpStatus: Int?
    public let version: String
    public let build: String
    public var delivery: Delivery = .local
    public var attempts: Int = 0
    public var retryAfter: Date?
    public var fingerprint: String { [area.rawValue, category.rawValue, httpStatus.map(String.init) ?? "none", version, build].joined(separator: ".") }
    public var summary: String { "\(area.rawValue) · \(category.rawValue)" }

    public init?(error: Error, area: DiagnosticArea, version: String, build: String, now: Date = Date()) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return nil }
        var status: Int?
        let category: DiagnosticCategory
        if let failure = error as? ProviderFailure {
            guard failure.kind != .cancelled && failure.kind != .limit else { return nil }
            category = DiagnosticCategory(rawValue: failure.kind.rawValue) ?? .unexpected
            status = failure.status.flatMap { (100...599).contains($0) ? $0 : nil }
        } else if error is CoachValidationError { category = .validation }
        else if error is HistoryStoreError || error is LearningDataError { category = .storage }
        else if error is URLError { category = .unavailable }
        else { category = .unexpected }
        self.id = UUID(); firstSeen = now; lastSeen = now; occurrences = 1
        self.area = area; self.category = category; httpStatus = status
        // Release values originate in the bundle; restrict them again before export.
        self.version = Self.releaseValue(version); self.build = Self.releaseValue(build)
    }

    private static func releaseValue(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-+")
        guard !value.isEmpty, value.utf8.count <= 64, value.unicodeScalars.allSatisfy(allowed.contains) else { return "unknown" }
        return value
    }
}

@MainActor
public final class DiagnosticJournal: ObservableObject {
    @Published public private(set) var reports: [DiagnosticReport] = []
    @Published public private(set) var storageError: String?
    public var onNewReport: ((DiagnosticReport) -> Void)?
    public var automaticReportingEnabled = false {
        didSet {
            if !automaticReportingEnabled {
                for index in reports.indices where reports[index].delivery == .pending { reports[index].delivery = .local }
                persist()
            }
        }
    }
    public static let maximumReports = 100
    private let fileURL: URL
    private let version: String
    private let build: String
    private var writable = true
    private let retention: TimeInterval = 30 * 24 * 60 * 60

    public init(directory: URL, version: String, build: String) {
        fileURL = directory.appendingPathComponent("reports-v1.json")
        self.version = version; self.build = build
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let size = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber
                guard (size?.intValue ?? Int.max) <= 256_000 else { throw HistoryStoreError.invalidData }
                reports = try JSONDecoder().decode([DiagnosticReport].self, from: Data(contentsOf: fileURL))
                guard reports.count <= Self.maximumReports, Set(reports.map(\.id)).count == reports.count,
                      reports.allSatisfy({ (1...1_000_000).contains($0.occurrences) && (0...16).contains($0.attempts) }) else { throw HistoryStoreError.invalidData }
                reports.removeAll { $0.lastSeen < Date().addingTimeInterval(-retention) }
            }
        } catch {
            writable = false
            reports = []
            storageError = "Die lokale Diagnosedatei konnte nicht geladen werden und wurde nicht überschrieben."
        }
    }

    public func record(_ error: Error, area: DiagnosticArea, now: Date = Date()) {
        guard var report = DiagnosticReport(error: error, area: area, version: version, build: build, now: now) else { return }
        reports.removeAll { $0.lastSeen < now.addingTimeInterval(-retention) }
        // At most one remotely queued event per category/build/day. Local counts retain repetitions.
        if let index = reports.firstIndex(where: { $0.fingerprint == report.fingerprint && now.timeIntervalSince($0.firstSeen) < 86_400 }) {
            reports[index].lastSeen = now
            reports[index].occurrences = min(1_000_000, reports[index].occurrences + 1)
        } else {
            report.delivery = automaticReportingEnabled ? .pending : .local
            reports.insert(report, at: 0)
            if reports.count > Self.maximumReports { reports.removeLast(reports.count - Self.maximumReports) }
            onNewReport?(report)
        }
        persist()
    }

    public func exportData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(reports)
    }

    public func markSent(_ id: UUID) {
        guard let index = reports.firstIndex(where: { $0.id == id && $0.delivery == .pending }) else { return }
        reports[index].delivery = .sent; reports[index].retryAfter = nil; persist()
    }

    public func deferDelivery(_ id: UUID, now: Date = Date(), minimumDelay: TimeInterval = 0) {
        guard let index = reports.firstIndex(where: { $0.id == id && $0.delivery == .pending }) else { return }
        reports[index].attempts = min(16, reports[index].attempts + 1)
        let delay = max(min(86_400, minimumDelay), min(21_600, 60 * pow(2, Double(reports[index].attempts))))
        reports[index].retryAfter = now.addingTimeInterval(delay); persist()
    }

    public func clear() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
            reports = []; writable = true; storageError = nil
        } catch { storageError = "Die lokalen Diagnoseberichte konnten nicht gelöscht werden." }
    }

    private func persist() {
        guard writable else { return }
        do {
            try JSONEncoder().encode(reports).write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            storageError = nil
        } catch { storageError = "Der Diagnosebericht bleibt nur bis zum Schließen im Fenster." }
    }
}
