import SwiftUI
import KlarCore

/// Settings in four calm sections with a sidebar. Every control keeps its previous meaning;
/// only the arrangement changed: status first, then the one next step, details folded away.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var connection: ConnectionManager
    @Environment(\.dismiss) private var dismiss
    @State private var section: Section = .connection
    @State private var apiKey = ""
    @State private var showAPI = false
    @State private var consent = false
    @State private var connectingAPI = false
    @State private var deleteLearning = false
    @State private var deleteHistory = false
    @Namespace private var marker

    enum Section: String, CaseIterable, Identifiable {
        case connection, reading, data, maintenance, about
        var id: String { rawValue }
        var title: String {
            switch self { case .connection: "Verbindung"; case .reading: "Darstellung"; case .data: "Deine Daten"; case .maintenance: "Updates & Fehler"; case .about: "Über Sinnfaden" }
        }
        var symbol: String {
            switch self { case .connection: "link"; case .reading: "textformat.size"; case .data: "lock.shield"; case .maintenance: "arrow.triangle.2.circlepath"; case .about: "info.circle" }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Color.black.opacity(0.06)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(section.title).font(.system(size: 22, weight: .semibold))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.sinnInk)
                            .frame(width: 30, height: 30).background(Color.sinnStructure, in: Circle())
                    }
                    .buttonStyle(.plain).focusEffectDisabled().help("Schließen").accessibilityLabel("Einstellungen schließen")
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch section {
                        case .connection: connectionSection
                        case .reading: readingSection
                        case .data: dataSection
                        case .maintenance: MaintenanceSettingsView(updates: model.updates, diagnostics: model.diagnostics)
                        case .about: aboutSection
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 28).padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(width: 780, height: 600)
        .background(Color.sinnWindow)
        .tint(Color.sinnAnnotation)
        .animation(SinnMotion.selection, value: section)
        .alert("Lerndaten dieses Kontos löschen?", isPresented: $deleteLearning) {
            Button("Abbrechen", role: .cancel) {}
            Button("Lerndaten löschen", role: .destructive) { model.learning.deleteLearningData() }
        } message: { Text("Alle Vorlagen einschließlich früherer Versionen, Lernversuche, Antwortentwürfe und Vergleiche werden lokal entfernt. Dein Prompt-Verlauf bleibt erhalten.") }
        .alert("Verlauf dieses Kontos löschen?", isPresented: $deleteHistory) {
            Button("Abbrechen", role: .cancel) {}
            Button("Verlauf löschen", role: .destructive) { model.deleteHistory() }
        } message: { Text("Entwurf, gespeicherte Vorschläge und Übungsversuche dieses Kontos werden lokal entfernt.") }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                SinnfadenMark().frame(width: 22, height: 22)
                Text("Einstellungen").font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.top, 26).padding(.bottom, 18)
            ForEach(Section.allCases) { item in
                Button { section = item } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).font(.system(size: 13, weight: .semibold)).frame(width: 20)
                        Text(item.title).font(.system(size: 13, weight: .medium))
                        Spacer()
                        if item == .connection { statusDot }
                    }
                    .foregroundStyle(section == item ? Color.sinnInk : Color.sinnMuted)
                    .padding(.horizontal, 10).frame(height: 34)
                    .background {
                        if section == item {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white)
                                .shadow(color: Color.black.opacity(0.06), radius: 4, y: 1)
                                .matchedGeometryEffect(id: "section", in: marker)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Version \(DiagnosticsController.version)").font(.system(size: 11)).foregroundStyle(Color.sinnMuted).padding(10)
        }
        .padding(.horizontal, 12)
        .frame(width: 210)
        .background(Color.sinnStructure.opacity(0.55))
    }

    private var statusColor: Color {
        connection.canGenerate ? .green : model.isDemo ? .sinnAnnotation : connection.status == .connecting ? .orange : .red.opacity(0.8)
    }
    private var statusDot: some View { Circle().fill(statusColor).frame(width: 8, height: 8) }

    // MARK: - Connection

    @ViewBuilder private var connectionSection: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.14)).frame(width: 46, height: 46)
                    if connection.status == .connecting {
                        ProgressView().controlSize(.small)
                    } else {
                        ChatGPTMark(size: 22)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isDemo ? "Beispielmodus" : connection.canGenerate ? (connection.providerKind == .chatGPT ? "Mit ChatGPT verbunden" : "OpenAI API verbunden") : "Nicht verbunden")
                        .font(.system(size: 16, weight: .semibold))
                    Text(model.isDemo ? "Ohne KI-Anfragen, mit einer lokal hinterlegten Antwort." : connection.statusMessage)
                        .font(.system(size: 12)).foregroundStyle(Color.sinnMuted).textSelection(.enabled)
                    if !connection.savedAccounts.isEmpty && connection.accountID != nil {
                        Text(connection.activeAccountLabel).font(.system(size: 11)).foregroundStyle(Color.sinnMuted)
                    }
                }
                Spacer()
                if connection.canGenerate {
                    Button("Trennen") { model.cancel(); model.learning.cancelAll(); connection.disconnect() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        if !connection.canGenerate {
            SettingsCard(title: "Mit ChatGPT anmelden") {
                Text("Bei einer KI-Anfrage werden dein Text und deine Ergänzungen an OpenAI gesendet. Dein Verlauf bleibt auf diesem Mac.")
                    .font(.system(size: 13)).foregroundStyle(Color.sinnMuted).lineSpacing(3)
                consentToggle
                if connection.status == .connecting {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Anmeldung im Browser …").font(.system(size: 13))
                        Spacer()
                        Button("Abbrechen") { connection.cancelSignIn() }.buttonStyle(SecondaryButtonStyle())
                    }
                } else {
                    Button { Task { await connection.signIn() } } label: {
                        HStack(spacing: 10) {
                            ChatGPTMark(size: 22).environment(\.colorScheme, .dark)
                            Text("Mit ChatGPT fortfahren").font(.system(size: 15, weight: .semibold))
                        }
                        .padding(.horizontal, 6)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!consent || model.isDemo)
                }
                Text("Die Freigabe deines Plans wird bei der Anmeldung geprüft. Frühere ChatGPT-Chats und Memories werden nicht importiert.")
                    .font(.system(size: 11)).foregroundStyle(Color.sinnMuted).lineSpacing(2)
            }
        }
        if connection.status == .identityOnly {
            SettingsCard(title: "Plan-Nutzung freigeben") {
                Text("Die Anmeldung enthält noch keine Freigabe zur Plan-Nutzung. Es werden keine KI-Anfragen gesendet.").font(.system(size: 13))
                HStack {
                    Button("Plan-Nutzung freigeben") { Task { await connection.enablePlanUsage() } }.buttonStyle(PrimaryButtonStyle()).disabled(!consent)
                    Button("Abmelden") { connection.disconnect() }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        if connection.status == .error && connection.accountID != nil {
            SettingsCard {
                Button("Verbindung trennen und Abmeldung erneut versuchen") { model.cancel(); model.learning.cancelAll(); connection.disconnect() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        if !connection.models.isEmpty {
            SettingsCard(title: "Modell") {
                SettingsRow(label: "Für Vorschläge verwenden") {
                    Picker("", selection: $connection.selectedModel) {
                        if connection.providerKind == .apiKey { Text("Textmodell auswählen").tag("") }
                        ForEach(connection.models, id: \.self) { Text(connection.modelNames[$0] ?? $0).tag($0) }
                    }
                    .labelsHidden().frame(maxWidth: 240)
                }
                Text("Die Liste stammt aus dem Katalog deines verbundenen Kontos.").font(.system(size: 11)).foregroundStyle(Color.sinnMuted)
            }
        }
        if !connection.savedAccounts.isEmpty {
            SettingsCard(title: "Konten") {
                SettingsRow(label: "Gespeichertes Konto") {
                    Menu {
                        ForEach(connection.savedAccounts, id: \.id) { account in
                            Button(account.label) { model.cancel(); Task { await connection.selectAccount(account.id) } }
                        }
                    } label: {
                        Label(connection.activeAccountLabel, systemImage: "person.crop.circle")
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    .disabled(model.isDemo)
                }
                Button { model.cancel(); Task { await connection.addAccount() } } label: { Label("Weiteres ChatGPT-Konto verbinden", systemImage: "plus") }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled((!connection.canGenerate && !consent) || connection.status == .connecting || model.isDemo)
            }
        }
        SettingsCard {
            DisclosureGroup(isExpanded: $showAPI) {
                VStack(alignment: .leading, spacing: 11) {
                    Text("API-Nutzung wird separat über deinen OpenAI-Platform-Account abgerechnet. Sinnfaden wechselt bei einem ChatGPT-Limit niemals automatisch zur API.")
                        .font(.system(size: 12)).foregroundStyle(Color.sinnMuted).lineSpacing(3)
                    if connection.canGenerate { consentToggle }
                    SecureField("API-Schlüssel", text: $apiKey).textFieldStyle(SinnFieldStyle())
                    HStack {
                        Button(connectingAPI ? "Wird verbunden …" : "API bewusst verbinden") {
                            connectingAPI = true
                            let key = apiKey
                            apiKey = ""
                            Task { await connection.connectAPIKey(key); connectingAPI = false }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(apiKey.isEmpty || connectingAPI || !consent || model.isDemo)
                        if !consent { Text("Erst der Übermittlung zustimmen.").font(.system(size: 11)).foregroundStyle(Color.sinnMuted) }
                    }
                    Text("Dein Schlüssel wird ausschließlich im macOS-Schlüsselbund gespeichert.").font(.system(size: 11)).foregroundStyle(Color.sinnMuted)
                }
                .padding(.top, 12)
            } label: {
                Label("Eigener OpenAI-API-Zugang (optional)", systemImage: "key").font(.system(size: 13, weight: .semibold))
            }
        }
        HStack(spacing: 18) {
            Link("Über die ChatGPT-Anmeldung", destination: URL(string: "https://learn.chatgpt.com/docs/sign-in-with-chatgpt")!)
            Link("Plan-Nutzung", destination: URL(string: "https://chatgpt.com/codex/settings/usage")!)
        }
        .font(.system(size: 12)).padding(.horizontal, 4)
    }

    private var consentToggle: some View {
        Toggle(isOn: $consent) {
            Text("Ich habe verstanden, dass meine Texte für KI-Anfragen an OpenAI gesendet werden.").font(.system(size: 13))
        }
        .toggleStyle(.checkbox)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sinnAnnotationWash.opacity(consent ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Reading

    @ViewBuilder private var readingSection: some View {
        SettingsCard(title: "Textgröße") {
            HStack(spacing: 14) {
                Text("A").font(.system(size: 13, weight: .semibold))
                Slider(value: $model.fontSize, in: 16...24, step: 1)
                Text("A").font(.system(size: 22, weight: .semibold))
                Text("\(Int(model.fontSize)) pt").font(.system(size: 12, weight: .medium)).monospacedDigit().frame(width: 40)
            }
            Text("So sieht dein Prompt aus: Schreib eine kurze, freundliche E-Mail an Frau Berger.")
                .font(.system(size: model.fontSize)).lineSpacing(5)
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sinnStructure.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .animation(SinnMotion.selection, value: model.fontSize)
        }
        SettingsCard(title: "Bewegung und Kontrast") {
            Text("Sinnfaden folgt den macOS-Einstellungen für reduzierte Bewegung, reduzierte Transparenz und erhöhten Kontrast. Erklärungen sind auch über die beschrifteten Schaltflächen erreichbar.")
                .font(.system(size: 13)).foregroundStyle(Color.sinnMuted).lineSpacing(3)
        }
    }

    // MARK: - Data

    @ViewBuilder private var dataSection: some View {
        SettingsCard {
            Label("Deine Lerninhalte bleiben auf diesem Mac, getrennt nach Konto. Fehlerberichte sind separat freigebbar.", systemImage: "lock.fill")
                .font(.system(size: 13, weight: .medium))
        }
        SettingsCard(title: "Prompt-Verlauf") {
            Text("Deine Entwürfe, Vorschläge und Übungsversuche. \(model.history.count) Einträge.").font(.system(size: 13)).foregroundStyle(Color.sinnMuted)
            HStack {
                Button { model.exportHistory() } label: { Label("Exportieren", systemImage: "square.and.arrow.up") }.buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button(role: .destructive) { deleteHistory = true } label: { Label("Löschen", systemImage: "trash") }
                    .buttonStyle(.plain).foregroundStyle(Color.red.opacity(0.85)).font(.system(size: 13, weight: .medium))
            }
        }
        SettingsCard(title: "Lerndaten") {
            Text("Vorlagen, Lernversuche, eingefügte Antworten und Vergleiche.").font(.system(size: 13)).foregroundStyle(Color.sinnMuted)
            HStack {
                Button { model.learning.export() } label: { Label("Exportieren", systemImage: "square.and.arrow.up") }.buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button(role: .destructive) { deleteLearning = true } label: { Label("Löschen", systemImage: "trash") }
                    .buttonStyle(.plain).foregroundStyle(Color.red.opacity(0.85)).font(.system(size: 13, weight: .medium))
            }
        }
    }

    // MARK: - About

    @ViewBuilder private var aboutSection: some View {
        SettingsCard {
            HStack(spacing: 16) {
                SinnfadenMark().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    SinnfadenWordmark(size: 20)
                    Text("Version \(DiagnosticsController.version) (\(DiagnosticsController.build))").font(.system(size: 12)).foregroundStyle(Color.sinnMuted)
                }
            }
            Text("Forschungsinformiert. Jeder KI-Vorschlag bleibt ein Vorschlag. Sein Nutzen hängt von deinem Anliegen, dem Modell und der tatsächlichen Antwort ab.")
                .font(.system(size: 13)).foregroundStyle(Color.sinnMuted).lineSpacing(3)
        }
        SettingsCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text("App-Zustand: \(model.phase.rawValue)")
                    Text("Anmeldung: \(String(describing: connection.status))")
                    Text("Antwortformat: JSON-Textadapter mit lokaler Bereinigung und strenger Prüfung, Version 1.")
                    Text("Optionale technische Fehlerberichte unter Updates & Fehler. Keine Promptinhalte in Diagnoselogs.")
                }
                .font(.system(size: 11)).textSelection(.enabled).padding(.top, 10)
            } label: {
                Label("Diagnose", systemImage: "stethoscope").font(.system(size: 13, weight: .semibold))
            }
        }
    }
}

/// A white card with an optional small heading.
private struct SettingsCard<Content: View>: View {
    var title: String?
    let content: Content
    init(title: String? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title.uppercased()).font(SinnType.eyebrow).tracking(1.3).foregroundStyle(Color.sinnMuted) }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.black.opacity(0.05)))
        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }
}

/// Label on the left, control on the right.
private struct SettingsRow<Control: View>: View {
    let label: String
    let control: Control
    init(label: String, @ViewBuilder control: () -> Control) { self.label = label; self.control = control() }
    var body: some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            control
        }
    }
}
