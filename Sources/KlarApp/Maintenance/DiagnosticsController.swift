import Foundation
import Combine
import AppKit
import KlarCore

@MainActor
final class DiagnosticsController: ObservableObject {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    let journal: DiagnosticJournal
    let configured: Bool
    @Published var automaticReporting: Bool {
        didSet {
            UserDefaults.standard.set(automaticReporting, forKey: "sinnfadenBugReportsEnabled")
            journal.automaticReportingEnabled = automaticReporting && configured
            deliveryTask?.cancel(); deliveryTask = nil
            revision = UUID()
            if automaticReporting { scheduleDelivery() }
        }
    }
    @Published private(set) var deliveryMessage = ""
    private let delivery: BugReportDelivery?
    private var deliveryTask: Task<Void, Never>?
    private var revision = UUID()
    private var subscription: AnyCancellable?

    init(isDemo: Bool) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KLAR/Diagnostics", isDirectory: true)
        journal = DiagnosticJournal(directory: isDemo ? directory.appendingPathComponent("Demo") : directory, version: Self.version, build: Self.build)
        let endpoint = isDemo ? nil : MaintenanceConfiguration.validFeed(Bundle.main.object(forInfoDictionaryKey: "SinnfadenBugReportURL") as? String)
        configured = endpoint != nil
        delivery = endpoint.map(BugReportDelivery.init(endpoint:))
        automaticReporting = !isDemo && UserDefaults.standard.bool(forKey: "sinnfadenBugReportsEnabled")
        journal.automaticReportingEnabled = automaticReporting && configured
        subscription = journal.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        journal.onNewReport = { [weak self] _ in self?.scheduleDelivery() }
        scheduleDelivery()
    }

    func record(_ error: Error, area: DiagnosticArea) { journal.record(error, area: area) }

    private func scheduleDelivery() {
        guard automaticReporting, let delivery, deliveryTask == nil else { return }
        let attempt = revision
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.revision == attempt { self.deliveryTask = nil } }
            while self.automaticReporting, self.revision == attempt, !Task.isCancelled {
                guard let report = self.journal.reports.filter({ $0.delivery == .pending }).min(by: { ($0.retryAfter ?? .distantPast) < ($1.retryAfter ?? .distantPast) }) else { return }
                let delay = report.retryAfter?.timeIntervalSinceNow ?? 0
                if delay > 0 {
                    do { try await Task.sleep(for: .seconds(min(delay, 60))) } catch { return }
                    continue
                }
                do {
                    try await delivery.send(report)
                    guard self.revision == attempt, !Task.isCancelled else { return }
                    self.journal.markSent(report.id)
                    self.deliveryMessage = "Bericht an die Entwicklung übermittelt."
                } catch {
                    guard self.revision == attempt, !Task.isCancelled else { return }
                    self.journal.deferDelivery(report.id, minimumDelay: (error as? BugReportDelivery.Failure)?.retryAfter ?? 0)
                    self.deliveryMessage = "Noch nicht übermittelt. Sinnfaden versucht es später erneut."
                }
            }
        }
    }

    func clear() {
        revision = UUID(); deliveryTask?.cancel(); deliveryTask = nil
        journal.clear(); deliveryMessage = ""
    }

    func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Sinnfaden-Diagnose.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try journal.exportData().write(to: url, options: .atomic) }
        catch { deliveryMessage = "Die Diagnose konnte nicht exportiert werden." }
    }
}
