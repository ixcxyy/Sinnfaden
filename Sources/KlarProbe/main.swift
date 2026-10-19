import Foundation
import KlarCore

@main
struct KlarProbe {
    @MainActor static func main() async {
        let arguments = Set(CommandLine.arguments.dropFirst())
        guard !arguments.isDisjoint(with: ["--login", "--probe", "--structured-probe", "--coach-suite"]) else {
            print("KLAR Verbindungsprüfung\n--login  Eigene KLAR-Anmeldung im Systembrowser starten\n--probe  Eine kurze Textantwort vollständig empfangen\n--structured-probe  Ein winziges Strict-JSON-Schema testen (eine Anfrage)\n--coach-suite  Sechs synthetische Alltagstasks prüfen (maximal ein Format-Reparaturversuch pro Task)\nKeine bestehenden Sitzungen anderer Apps werden verwendet.")
            return
        }
        let manager = ConnectionManager(restore: false)
        if arguments.contains("--login") { await manager.signIn() }
        else if await manager.restoreSelectedAccount() { }
        else {
            print("NICHT AUSGEFÜHRT: Kein von KLAR registriertes ChatGPT-Konto vorhanden. Zuerst KLAR öffnen und bewusst anmelden, oder KlarProbe --login verwenden.")
            Foundation.exit(2)
        }
        guard manager.canGenerate, manager.providerKind == .chatGPT else { print("NICHT BESTANDEN: " + manager.statusMessage); Foundation.exit(3) }
        do {
            if arguments.contains("--structured-probe") {
                let supported = try await manager.probeStructuredOutput()
                print(supported ? "BESTANDEN: Strict json_schema und response.completed für tatsächliches SIWC-Modell beobachtet." : "NICHT BESTANDEN: Schemaantwort passt nicht zum Prüfmuster.")
                print("Modell: " + manager.selectedModel)
                if !supported { Foundation.exit(4) }
            } else if arguments.contains("--coach-suite") {
                try await runCoachSuite(manager)
            } else {
                let response = try await manager.generate(instructions: "Dies ist ein Verbindungstest. Antworte nur mit dem Wort KLAR.", input: "Bitte bestätige die Verbindung.", onProgress: { _ in })
                guard response.trimmingCharacters(in: .whitespacesAndNewlines) == "KLAR" else {
                    print("ABSCHLUSS EMPFANGEN: response.completed beobachtet; Text wich vom erwarteten Prüfmuster ab."); Foundation.exit(4)
                }
                print("BESTANDEN: Freigegebener Zugang, tatsächlicher Modellkatalog und response.completed mit erwarteter Textantwort beobachtet.")
                print("Modell: " + manager.selectedModel)
                print("Structured Outputs und Tutorqualität sind durch diesen Verbindungstest nicht bestätigt.")
            }
        } catch { reportFailure(error); Foundation.exit(5) }
    }
    static func reportFailure(_ error: Error) {
        print("NICHT BESTANDEN: " + ((error as? ProviderFailure)?.message ?? "Verbindung unterbrochen oder Antwort ungültig."))
        if let failure = error as? ProviderFailure {
            print("Diagnose: HTTP " + (failure.status.map(String.init) ?? "–") + ", Code " + (failure.code ?? "–") + ", Form " + (failure.bodyShape ?? "–"))
        } else { let detail = error as NSError; print("Transportdiagnose: " + detail.domain + " · " + String(detail.code)) }
    }

    @MainActor static func runCoachSuite(_ manager: ConnectionManager) async throws {
        let cases: [(String, String, [String])] = [
            ("E-Mail", "Schreib eine kurze, freundliche E-Mail an Frau Berger. Ich kann am 24. Oktober um 14 Uhr nicht und möchte einen neuen Termin. Höchstens 80 Wörter. Erfinde keinen Grund für die Absage.", ["Frau Berger", "24. Oktober", "14 Uhr", "80"]),
            ("Erklärung", "Erkläre Photosynthese für jemanden ohne Vorwissen in genau fünf kurzen Sätzen. Verwende einen Alltagsvergleich und erkläre notwendige Fachbegriffe direkt. Gib nur die Erklärung aus.", ["Photosynthese", "fünf", "Alltagsvergleich"]),
            ("Planung", "Plane einen Ausflug für Anna und mich am 3. November. Wir haben höchstens 60 Euro und müssen um 18 Uhr zurück sein.", ["Anna", "3. November", "60", "18 Uhr"]),
            ("Zusammenfassung", "Fasse den folgenden Text in genau drei Stichpunkten zusammen. Erhalte Namen und Zahlen und füge keine Informationen hinzu. Text: Mira hat am 12. Mai 18 Bücher an die Stadtbibliothek gespendet. Davon waren 7 Kinderbücher. Die Übergabe dauerte 20 Minuten.", ["Mira", "12. Mai", "18", "7", "20"]),
            ("Kreatives Schreiben", "Schreib eine Geschichte über Lina und ihren Hund Komet. Sie finden eine blaue Tür im Wald. Höchstens 120 Wörter und kein trauriges Ende.", ["Lina", "Komet", "120"]),
            ("Wiederverwendbare Aufgabe", "Ich brauche eine wiederverwendbare Vorlage, mit der ich jeden Freitag einen Workshop für ein Team mit 6 Personen planen kann. Dauer immer 45 Minuten. Das Thema setze ich später ein. Ausgabe: Titel, Ablauf mit Minuten, benötigtes Material und eine Abschlussfrage. Keine kostenpflichtigen Werkzeuge empfehlen.", ["Freitag", "6", "45"])
        ]
        var results = [[String: Any]]()
        var failures = 0
        let destination = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Artifacts/live-coach-suite.json")
        for (name, prompt, literals) in cases {
            let counter = ProbeCounter()
            do {
                let response = try await CoachPipeline.run(original: prompt, generate: { instructions, input in
                    counter.increment()
                    return try await manager.generate(instructions: instructions, input: input, onProgress: { _ in })
                }, onStage: { stage in if stage == .repairing { print("Format-Reparatur für synthetischen Fall wird einmal ausgeführt.") } })
                let clarification = response.status == .needs_clarification
                let checks = Dictionary(uniqueKeysWithValues: literals.map { ($0, clarification ? true : response.prompt.contains($0)) })
                let literalPass = checks.values.allSatisfy { $0 }
                if !literalPass { failures += 1 }
                let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(response))
                results.append(["case": name, "synthetic_prompt": prompt, "model": manager.selectedModel, "requests": counter.value, "status": response.status.rawValue, "contract_validated": true, "literal_checks": checks, "literal_checks_deferred_for_clarification": clarification, "response": encoded])
                print(name + ": " + response.status.rawValue + ", Vertrag gültig, Faktenprüfung " + (clarification ? "nach Rückfrage offen" : literalPass ? "bestanden" : "PRÜFEN") + ", Anfragen " + String(counter.value))
            } catch {
                failures += 1
                results.append(["case": name, "synthetic_prompt": prompt, "model": manager.selectedModel, "requests": counter.value, "contract_validated": false, "error_type": (error as? ProviderFailure)?.kind.rawValue ?? "validation"])
                print(name + ": nicht bestanden; kein fertiger Vorschlag übernommen.")
                try writeReport(results, to: destination)
                if let failure = error as? ProviderFailure, [.authentication, .permission, .limit].contains(failure.kind) { throw error }
            }
            try writeReport(results, to: destination)
        }
        print("Synthetische Fälle: " + String(cases.count) + ", auffällige Fälle: " + String(failures))
        print("Prüfbericht: " + destination.path)
        print("Dies ist kein Lerntest mit der Nutzerin und keine Wirksamkeitsmessung.")
        if failures > 0 { Foundation.exit(6) }
    }
    static func writeReport(_ results: [[String: Any]], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let report: [String: Any] = ["generated_at": ISO8601DateFormatter().string(from: Date()), "synthetic_data_only": true, "cases": results]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
}

final class ProbeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
