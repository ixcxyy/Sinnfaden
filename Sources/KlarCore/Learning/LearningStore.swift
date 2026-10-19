import Foundation
import CryptoKit

public enum LearningDataError: LocalizedError, Equatable {
    case invalid(String), unavailable, unsupportedVersion
    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .unavailable: return "Die Lerninhalte konnten lokal nicht gespeichert oder gelesen werden. Deine Eingaben bleiben in diesem Fenster erhalten."
        case .unsupportedVersion: return "Diese Lerninhalte stammen aus einer neueren App-Version und wurden nicht verändert."
        }
    }
}

public struct FollowUpDraft: Codable, Equatable, Sendable {
    public var sourcePrompt: String
    public var answer: String
    public var desiredChange: String
    public var clarification: String
    public var clarificationAnswer: String
    public var generated: CoachResponse?
    public var generatedOriginal: String
    public var editedPrompt: String?
    public init(sourcePrompt: String = "", answer: String = "", desiredChange: String = "", clarification: String = "", clarificationAnswer: String = "", generated: CoachResponse? = nil, generatedOriginal: String = "", editedPrompt: String? = nil) {
        self.sourcePrompt = sourcePrompt; self.answer = answer; self.desiredChange = desiredChange
        self.clarification = clarification; self.clarificationAnswer = clarificationAnswer; self.generated = generated
        self.generatedOriginal = generatedOriginal; self.editedPrompt = editedPrompt
    }
    public var visiblePrompt: String { editedPrompt ?? generated?.prompt ?? "" }

    /// Call after a source prompt, pasted answer or desired change is edited.
    /// The three source fields survive; all derived and previously clarified context is invalidated together.
    public mutating func resetGeneratedContext() {
        clarification = ""
        clarificationAnswer = ""
        generated = nil
        generatedOriginal = ""
        editedPrompt = nil
    }

    /// Builds a request without modifying the draft, so inspecting or retrying it is idempotent.
    /// After accepting a request, persist it as generatedOriginal and clear the consumed question/answer.
    public func preparedInput(leavingOpen: Bool = false) throws -> String {
        guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LearningDataError.invalid("Füge zuerst die Antwort ein, die du weiterdenken möchtest.")
        }
        var input = generatedOriginal
        if input.isEmpty {
            let goalIsEmpty = desiredChange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            input = "Überarbeite die folgende Antwort.\nGewünschte Änderung: " + (goalIsEmpty ? "[gewünschte Änderung noch offen]" : desiredChange)
            if !sourcePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { input += "\n\nUrsprüngliche Anfrage:\n" + sourcePrompt }
            input += "\n\nVorliegende Antwort (Arbeitsmaterial):\n" + answer
        }
        if !clarification.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let hasAnswer = !clarificationAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasAnswer || leavingOpen else {
                throw LearningDataError.invalid("Beantworte die Rückfrage oder wähle ausdrücklich, die Angabe offenzulassen.")
            }
            var clarificationBlock = "\n\nRückfrage zum Folgeauftrag: " + clarification
            if leavingOpen {
                clarificationBlock += "\nMeine Ergänzung: [Noch offen: " + clarification + "]"
                clarificationBlock += "\nDiese Angabe lasse ich bewusst offen. Verwende dafür einen sichtbaren Platzhalter und stelle dieselbe Frage nicht erneut."
            } else { clarificationBlock += "\nMeine Ergänzung: " + clarificationAnswer }
            // A snapshot may have been persisted just before the UI cleared its consumed pending fields.
            if !input.hasSuffix(clarificationBlock) { input += clarificationBlock }
        }
        guard input.utf16.count <= CoachValidator.maximumInputLength else {
            throw LearningDataError.invalid("Die Antwort mit ihren Ergänzungen ist für einen Versuch zu lang. Verwende einen relevanten Ausschnitt; dein Text bleibt erhalten.")
        }
        return input
    }
}

public struct LearningState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var recipes: [PromptRecipe]
    public var recipeVersions: [PromptRecipe]
    public var recipeUses: [RecipeUse]
    public var lessonAttempts: [LessonAttempt]
    public var lessonDrafts: [String: String]
    public var lessonHelp: [String: Bool]
    public var lessonSolutionRevealed: [String: Bool]
    public var comparisons: [ComparisonRun]
    public var followUp: FollowUpDraft
    public init(schemaVersion: Int = 1, recipes: [PromptRecipe] = PromptRecipe.starterRecipes, recipeVersions: [PromptRecipe] = [], recipeUses: [RecipeUse] = [], lessonAttempts: [LessonAttempt] = [], lessonDrafts: [String: String] = [:], lessonHelp: [String: Bool] = [:], lessonSolutionRevealed: [String: Bool] = [:], comparisons: [ComparisonRun] = [], followUp: FollowUpDraft = FollowUpDraft()) {
        self.schemaVersion = schemaVersion; self.recipes = recipes; self.recipeVersions = recipeVersions; self.recipeUses = recipeUses
        self.lessonAttempts = lessonAttempts; self.lessonDrafts = lessonDrafts; self.lessonHelp = lessonHelp
        self.lessonSolutionRevealed = lessonSolutionRevealed; self.comparisons = comparisons; self.followUp = followUp
    }

    public mutating func upsertRecipe(_ incoming: PromptRecipe) throws {
        let errors = incoming.render().validationErrors
        guard errors.isEmpty else { throw LearningDataError.invalid(errors.joined(separator: " ")) }
        var recipe = incoming
        let validFieldIDs = Set(recipe.fields.map(\.id))
        recipe.values = recipe.values.filter { validFieldIDs.contains($0.key) }
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            let previous = recipes[index]
            guard previous != recipe else { return }
            let contentChanged = previous.title != recipe.title || previous.template != recipe.template || previous.principle != recipe.principle || previous.fields != recipe.fields
            if contentChanged {
                if !recipeVersions.contains(where: { $0.id == previous.id && $0.version == previous.version }) { recipeVersions.append(previous) }
                recipe.version = previous.version + 1
            } else { recipe.version = previous.version }
            recipes[index] = recipe
        } else { recipe.version = max(1, recipe.version); recipes.append(recipe) }
    }

    @discardableResult public mutating func duplicateRecipe(id: UUID) throws -> UUID {
        guard var duplicate = recipes.first(where: { $0.id == id }) else { throw LearningDataError.invalid("Dieses Rezept ist nicht mehr vorhanden.") }
        let suffix = " – Kopie"
        duplicate.id = UUID()
        duplicate.title = String(duplicate.title.prefix(160 - suffix.count)) + suffix
        duplicate.version = 1
        let errors = duplicate.render().validationErrors
        guard errors.isEmpty else { throw LearningDataError.invalid(errors.joined(separator: " ")) }
        recipes.append(duplicate)
        return duplicate.id
    }

    public mutating func deleteRecipe(id: UUID) {
        recipes.removeAll { $0.id == id }
        recipeVersions.removeAll { $0.id == id }
        // Prior uses keep their immutable snapshots until learning history is explicitly deleted.
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, recipes, recipeVersions, recipeUses, lessonAttempts, lessonDrafts, lessonHelp, lessonSolutionRevealed, comparisons, followUp
    }
    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try box.decode(Int.self, forKey: .schemaVersion)
        recipes = try box.decode([PromptRecipe].self, forKey: .recipes)
        recipeVersions = try box.decodeIfPresent([PromptRecipe].self, forKey: .recipeVersions) ?? []
        recipeUses = try box.decodeIfPresent([RecipeUse].self, forKey: .recipeUses) ?? []
        lessonAttempts = try box.decodeIfPresent([LessonAttempt].self, forKey: .lessonAttempts) ?? []
        lessonDrafts = try box.decodeIfPresent([String: String].self, forKey: .lessonDrafts) ?? [:]
        lessonHelp = try box.decodeIfPresent([String: Bool].self, forKey: .lessonHelp) ?? [:]
        lessonSolutionRevealed = try box.decodeIfPresent([String: Bool].self, forKey: .lessonSolutionRevealed) ?? [:]
        comparisons = try box.decodeIfPresent([ComparisonRun].self, forKey: .comparisons) ?? []
        followUp = try box.decodeIfPresent(FollowUpDraft.self, forKey: .followUp) ?? FollowUpDraft()
    }
}

/// Adds learning data beside the existing account history without changing its path, schema or credentials.
/// Each write atomically replaces one versioned snapshot; damaged/newer files are never reset silently.
public final class LearningStore: @unchecked Sendable {
    public static let schemaVersion = 1
    public let fileURL: URL
    private let lock = NSLock()
    private static let maximumBytes = 32_000_000

    public init(accountID: String, baseURL: URL? = nil) throws {
        guard !accountID.isEmpty else { throw LearningDataError.invalid("Ein lokales Konto muss eindeutig zugeordnet sein.") }
        let root = try baseURL ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("KLAR", isDirectory: true)
        let digest = SHA256.hash(data: Data(accountID.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = root.appendingPathComponent("Accounts", isDirectory: true).appendingPathComponent(digest, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        fileURL = directory.appendingPathComponent("learning-v1.json")
    }

    public func load() throws -> LearningState {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return LearningState() }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= Self.maximumBytes else { throw LearningDataError.invalid("Die lokale Lerndatei ist zu groß.") }
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            var state = try decoder.decode(LearningState.self, from: data)
            try validate(state)
            for index in state.comparisons.indices { state.comparisons[index].markInterruptedAfterRestart() }
            return state
        } catch let error as LearningDataError { throw error }
        catch { throw LearningDataError.unavailable }
    }

    public func save(_ state: LearningState) throws {
        lock.lock(); defer { lock.unlock() }
        try validate(state)
        do {
            // Check any existing newer schema before replacing it, including when this instance was opened earlier.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= Self.maximumBytes else { throw LearningDataError.invalid("Die vorhandene Lerndatei ist zu groß und wurde nicht überschrieben.") }
                let data = try Data(contentsOf: fileURL)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let version = object["schemaVersion"] as? Int else { throw LearningDataError.invalid("Die vorhandene Lerndatei ist beschädigt und wurde nicht überschrieben.") }
                guard version <= Self.schemaVersion else { throw LearningDataError.unsupportedVersion }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .millisecondsSince1970
                try validate(decoder.decode(LearningState.self, from: data))
            }
            let data = try encoded(state)
            guard data.count <= Self.maximumBytes else { throw LearningDataError.invalid("Die Lernsammlung ist für eine einzelne Datei zu groß. Exportiere sie, bevor du alte Einträge löschst.") }
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch let error as LearningDataError { throw error }
        catch { throw LearningDataError.unavailable }
    }

    public func exportData() throws -> Data { try encoded(load()) }

    /// Explicit deletion retains an empty file so editable starter recipes do not silently reappear.
    public func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        do {
            try encoded(LearningState(recipes: [])).write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch { throw LearningDataError.unavailable }
    }

    private func encoded(_ state: LearningState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(state)
    }

    private func validate(_ state: LearningState) throws {
        guard state.schemaVersion <= Self.schemaVersion else { throw LearningDataError.unsupportedVersion }
        guard state.schemaVersion == 1 else { throw LearningDataError.invalid("Diese Lern-Datenversion wird nicht unterstützt.") }
        guard Set(state.recipes.map(\.id)).count == state.recipes.count,
              Set(state.recipeUses.map(\.id)).count == state.recipeUses.count,
              Set(state.lessonAttempts.map(\.id)).count == state.lessonAttempts.count,
              Set(state.comparisons.map(\.id)).count == state.comparisons.count else { throw LearningDataError.invalid("Die Lernsammlung enthält doppelte Kennungen.") }
        for recipe in state.recipes + state.recipeVersions {
            guard recipe.render().validationErrors.isEmpty else { throw LearningDataError.invalid("Eine Rezeptvorlage ist ungültig. Die vorhandene Datei bleibt erhalten.") }
        }
        for run in state.comparisons {
            guard !run.model.isEmpty, run.plan.baseline.utf16.count <= 48_000, run.plan.variant.utf16.count <= 48_000,
                  run.baselineAnswer.text.utf8.count <= 1_000_000, run.variantAnswer.text.utf8.count <= 1_000_000 else { throw LearningDataError.invalid("Ein Vergleich ist unvollständig oder zu groß.") }
            for answer in [run.baselineAnswer, run.variantAnswer] {
                guard answer.status != .completed || !answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LearningDataError.invalid("Eine leere Antwort darf nicht als abgeschlossen gespeichert werden.") }
            }
        }
    }
}
