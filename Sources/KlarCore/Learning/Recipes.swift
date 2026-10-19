import Foundation

public struct RecipeField: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var required: Bool
    public init(id: String, label: String, required: Bool = true) { self.id = id; self.label = label; self.required = required }
}

public struct RecipeRender: Equatable, Sendable {
    public let text: String
    public let missingRequired: [String]
    public let unknownFields: [String]
    public let validationErrors: [String]
    public var isReady: Bool { missingRequired.isEmpty && validationErrors.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

public struct PromptRecipe: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var template: String
    public var principle: String
    public var fields: [RecipeField]
    public var values: [String: String]
    public var version: Int
    public init(id: UUID = UUID(), title: String, template: String, principle: String = "Verändere nur die Angaben, die für diese Aufgabe wichtig sind.", fields: [RecipeField] = [], values: [String: String] = [:], version: Int = 1) {
        self.id = id; self.title = title; self.template = template; self.principle = principle
        self.fields = fields; self.values = values; self.version = version
    }

    public func render() -> RecipeRender {
        var errors: [String] = []
        let ids = fields.map(\.id)
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Gib dem Rezept einen Namen.") }
        if title.count > 160 || principle.count > 1_000 || template.utf16.count > 48_000 { errors.append("Name, Erklärung oder Vorlage ist zu lang.") }
        if template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { errors.append("Die Vorlage ist noch leer.") }
        if fields.count > 30 || Set(ids).count != ids.count { errors.append("Felder müssen eindeutige Kennungen haben; höchstens 30 sind möglich.") }
        if version < 1 { errors.append("Die Rezeptversion ist ungültig.") }
        for field in fields {
            if field.id.range(of: "^[a-z][a-z0-9_]{0,39}$", options: .regularExpression) == nil || field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || field.label.count > 120 {
                errors.append("Eine Feldkennung oder Feldbezeichnung ist ungültig.")
            }
        }
        let expression = try! NSRegularExpression(pattern: "\\{\\{([^{}]+)\\}\\}")
        let source = template as NSString
        let matches = expression.matches(in: template, range: NSRange(location: 0, length: source.length))
        let referenced = matches.map { source.substring(with: $0.range(at: 1)) }
        let definitions = fields.reduce(into: [String: RecipeField]()) { result, field in result[field.id] = field }
        for reference in Set(referenced) where definitions[reference] == nil { errors.append("Für {{\(reference)}} fehlt ein Feld.") }
        for field in fields where !referenced.contains(field.id) { errors.append("Das Feld „\(field.label)“ kommt in der Vorlage nicht vor.") }
        var output = ""
        var offset = 0
        var missing: [String] = []
        var unknown: [String] = []
        for match in matches {
            output += source.substring(with: NSRange(location: offset, length: match.range.location - offset))
            let id = source.substring(with: match.range(at: 1))
            if let field = definitions[id] {
                let raw = values[id] ?? ""
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.isEmpty {
                    output += "[\(field.label) noch offen]"
                    if field.required && !missing.contains(field.label) { missing.append(field.label) }
                    if !unknown.contains(field.label) { unknown.append(field.label) }
                } else {
                    output += raw
                    if value.hasPrefix("[") && value.hasSuffix("]") && !unknown.contains(field.label) { unknown.append(field.label) }
                }
            } else { output += source.substring(with: match.range) }
            offset = NSMaxRange(match.range)
        }
        output += source.substring(from: offset)
        let scrubbed = expression.stringByReplacingMatches(in: template, range: NSRange(location: 0, length: source.length), withTemplate: "")
        if scrubbed.contains("{{") || scrubbed.contains("}}") { errors.append("Ein Platzhalter ist unvollständig. Verwende zum Beispiel {{ziel}}.") }
        if output.utf16.count > 48_000 || values.values.contains(where: { $0.utf16.count > 24_000 }) { errors.append("Der ausgefüllte Prompt ist zu lang.") }
        return RecipeRender(text: output, missingRequired: missing, unknownFields: unknown, validationErrors: errors)
    }

    public static let starterRecipes: [PromptRecipe] = [
        PromptRecipe(id: UUID(uuidString: "1680AE25-52AB-40B8-9374-C0659D631101")!, title: "Eine freundliche E-Mail", template: "Schreibe eine E-Mail an {{empfaenger}}.\nZiel: {{ziel}}\nWichtiger Kontext: {{kontext}}\nTon: {{ton}}\nErfinde keine fehlenden Namen, Gründe oder Termine. Markiere unbekannte Angaben als Platzhalter.", principle: "Empfänger und Ziel helfen, eine E-Mail passend zu formulieren.", fields: [RecipeField(id: "empfaenger", label: "Empfänger"), RecipeField(id: "ziel", label: "Ziel"), RecipeField(id: "kontext", label: "Wichtiger Kontext", required: false), RecipeField(id: "ton", label: "Ton")], values: ["ton": "kurz und freundlich"]),
        PromptRecipe(id: UUID(uuidString: "1680AE25-52AB-40B8-9374-C0659D631102")!, title: "Etwas verstehen", template: "Erkläre {{thema}} für {{person}}.\nGewünschte Form: {{format}}\nNutze ein passendes Beispiel. Kennzeichne Unsicherheit, statt eine Antwort zu erfinden.", principle: "Eine Zielgruppe und ein Beispiel helfen, die Erklärung auf die Situation abzustimmen.", fields: [RecipeField(id: "thema", label: "Thema"), RecipeField(id: "person", label: "Für wen?"), RecipeField(id: "format", label: "Form und Länge")], values: ["person": "eine Person ohne Vorkenntnisse", "format": "drei kurze Absätze"]),
        PromptRecipe(id: UUID(uuidString: "1680AE25-52AB-40B8-9374-C0659D631103")!, title: "Einen Text zusammenfassen", template: "Fasse den folgenden Text für {{ziel}} zusammen.\nForm und Länge: {{format}}\nBewahre wichtige Einschränkungen und erfinde keine zusätzlichen Fakten.\n\nText:\n{{text}}", principle: "Der Zweck entscheidet mit, welche Informationen in einer Zusammenfassung wichtig sind.", fields: [RecipeField(id: "ziel", label: "Zweck"), RecipeField(id: "format", label: "Form und Länge"), RecipeField(id: "text", label: "Ausgangstext")], values: ["format": "fünf Stichpunkte"]),
        PromptRecipe(id: UUID(uuidString: "1680AE25-52AB-40B8-9374-C0659D631104")!, title: "Ein Vorhaben Schritt für Schritt", template: "Ziel:\n{{ziel}}\n\nVorhandene Informationen:\n{{kontext}}\n\nGrenzen:\n{{grenzen}}\n\nVorgehen:\nPrüfe zuerst, ob eine entscheidende Information fehlt, und stelle dann eine gezielte Frage. Zerlege das Vorhaben in sinnvolle Schritte. Erfinde keine Ressourcen oder Termine.\n\nErgebnis:\n{{format}}\n\nPrüfung:\nZeige offene Punkte und prüfe, ob der Plan die genannten Grenzen einhält.", principle: "Wiederkehrende Aufgaben profitieren von klar getrennten Eingaben, Vorgehen und Ergebnisprüfung.", fields: [RecipeField(id: "ziel", label: "Ziel"), RecipeField(id: "kontext", label: "Wichtiger Kontext"), RecipeField(id: "grenzen", label: "Grenzen", required: false), RecipeField(id: "format", label: "Gewünschtes Ergebnis")], values: ["format": "eine übersichtliche Liste mit Schritten und offenen Fragen"])
    ]
}

public struct RecipeUse: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let recipe: PromptRecipe
    public let renderedText: String
    public init(id: UUID = UUID(), createdAt: Date = Date(), recipe: PromptRecipe, renderedText: String) {
        self.id = id; self.createdAt = createdAt; self.recipe = recipe; self.renderedText = renderedText
    }
}
