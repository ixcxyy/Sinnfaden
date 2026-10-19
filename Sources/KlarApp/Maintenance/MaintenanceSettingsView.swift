import SwiftUI
import KlarCore

struct MaintenanceSettingsView: View {
    @ObservedObject var updates: UpdateController
    @ObservedObject var diagnostics: DiagnosticsController
    @State private var confirmClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Updates").font(.headline)
                Text("Version \(DiagnosticsController.version) (\(DiagnosticsController.build))").font(.subheadline)
                Text(updates.message).foregroundStyle(.secondary)
                Button("Nach Updates suchen …") { updates.checkForUpdates() }
                    .disabled(updates.configured && !updates.canCheck)
                Toggle("Automatisch nach neuen Versionen suchen", isOn: $updates.automaticallyChecks)
                    .disabled(!updates.configured)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Fehlerberichte").font(.headline)
                Text("Technische Fehler werden lokal gesammelt. Mit deiner Freigabe werden neue Berichte an die Entwicklung gesendet und dort als private GitHub-Issues gebündelt. Prompts, Antworten, Namen und Anmeldedaten sind nicht enthalten.")
                    .foregroundStyle(.secondary)
                Toggle("Fehlerberichte automatisch senden", isOn: $diagnostics.automaticReporting)
                    .disabled(!diagnostics.configured)
                if !diagnostics.configured {
                    Text("Der private Meldekanal ist noch nicht eingerichtet. Berichte bleiben auf diesem Mac.").foregroundStyle(.secondary)
                }
                Text("Bei der Übermittlung sieht der Meldedienst die IP-Adresse deiner Verbindung. Bereits übermittelte Berichte werden durch Ausschalten oder lokales Löschen nicht zurückgerufen.")
                    .font(.caption).foregroundStyle(.secondary)
                if !diagnostics.deliveryMessage.isEmpty { Text(diagnostics.deliveryMessage).font(.caption) }
                if let error = diagnostics.journal.storageError { Text(error).foregroundStyle(.red) }
                HStack {
                    Button("Berichte exportieren …") { diagnostics.export() }.disabled(diagnostics.journal.reports.isEmpty)
                    Button("Lokal löschen …", role: .destructive) { confirmClear = true }
                }
                if diagnostics.journal.reports.isEmpty {
                    Text("Noch keine Fehlerberichte.").foregroundStyle(.secondary)
                } else {
                    ForEach(diagnostics.journal.reports.prefix(20)) { report in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.summary).font(.system(.body, design: .monospaced))
                            Text("\(report.lastSeen.formatted(date: .abbreviated, time: .shortened)) · \(report.occurrences)× · \(deliveryLabel(report.delivery))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("Bericht \(report.id.uuidString)").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .font(.system(size: 13)).padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .alert("Lokale Fehlerberichte löschen?", isPresented: $confirmClear) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { diagnostics.clear() }
        } message: { Text("Ausstehende Übermittlungen werden abgebrochen. Bereits angelegte GitHub-Issues bleiben bestehen.") }
    }

    private func deliveryLabel(_ delivery: DiagnosticReport.Delivery) -> String {
        switch delivery { case .local: "nur lokal"; case .pending: "Übermittlung ausstehend"; case .sent: "übermittelt" }
    }
}
