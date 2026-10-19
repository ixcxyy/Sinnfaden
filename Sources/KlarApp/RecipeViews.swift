import SwiftUI
import KlarCore

/// "Meine Vorlagen": the template you used last waits as a hero, the rest in a grid.
/// A template opens as fill-in on the left and a live preview on the right, where your own
/// words light up in blue and open gaps in orange.
struct RecipesView: View {
    @ObservedObject var model: LearningWorkspace
    @ObservedObject var handoff: ChatGPTHandoff
    let fontSize: Double
    @State private var editing: PromptRecipe?
    @State private var deleting: UUID?
    @State private var editingEpoch: UUID?
    @State private var deletingEpoch: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let storageError = model.storageError { LearningNotice(text: storageError) }
            if let recipe = model.state.recipes.first(where: { $0.id == model.selectedRecipe }) {
                recipeDetail(recipe)
            } else {
                LearningPageHeader(eyebrow: "Gute Ideen wiederverwenden", title: "Meine Vorlagen",
                                   subtitle: "Ein vertrauter Ausgangspunkt für Wiederkehrendes. Du füllst nur aus, was heute anders ist.")
                if model.state.recipes.isEmpty {
                    GuidedEmptyState(symbol: "square.stack", title: "Noch keine Vorlage",
                                     text: "Eine Vorlage hält fest, was bei einer Aufgabe immer gleich bleibt. Die wechselnden Angaben werden zu Feldern.",
                                     steps: ["Lass einen Prompt verbessern oder schreib einen eigenen.", "Wähle „Als Vorlage“ oder lege hier eine neue an.", "Beim nächsten Mal nur die Felder ausfüllen."],
                                     actionTitle: "Neue Vorlage anlegen", actionSymbol: "plus", action: { beginEditing(newRecipe) })
                        .sinnReveal(1)
                } else {
                    overview
                }
            }
            if let error = model.errorMessage { LearningNotice(text: error) }
        }
        .sheet(item: $editing) { recipe in RecipeEditor(recipe: recipe) { if editingEpoch == model.accountEpoch { model.saveRecipe($0) } } }
        .onChange(of: model.accountEpoch) { _, _ in editing = nil; deleting = nil; editingEpoch = nil; deletingEpoch = nil }
        .alert("Diese Vorlage löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Abbrechen", role: .cancel) { deleting = nil }
            Button("Vorlage löschen", role: .destructive) { if let id = deleting, deletingEpoch == model.accountEpoch { model.deleteRecipe(id) }; deleting = nil }
        } message: { Text("Frühere verwendete Versionen bleiben im lokalen Nutzungsverlauf nachvollziehbar. Über „Lerndaten löschen“ entfernst du auch diese.") }
    }

    private var newRecipe: PromptRecipe { PromptRecipe(title: "Meine Vorlage", template: "", fields: []) }

    // MARK: Overview

    @ViewBuilder private var overview: some View {
        let recipes = model.state.recipes
        let lastUsed = model.state.recipeUses.last.flatMap { use in recipes.first { $0.id == use.recipe.id } }
        let featured = lastUsed ?? recipes[0]
        hero(featured, recentlyUsed: lastUsed != nil).sinnReveal(1)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionEyebrow(text: recipes.count > 1 ? "Weitere Vorlagen · \(recipes.count - 1)" : "Deine Vorlagen")
                Spacer()
                Button { beginEditing(newRecipe) } label: { Label("Neue Vorlage", systemImage: "plus") }.buttonStyle(SecondaryButtonStyle())
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                ForEach(recipes.filter { $0.id != featured.id }) { recipe in card(recipe) }
            }
        }
        .padding(.top, 6)
        .sinnReveal(2)
    }

    private func hero(_ recipe: PromptRecipe, recentlyUsed: Bool) -> some View {
        let uses = useCount(recipe)
        return HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                SectionEyebrow(text: recentlyUsed ? "Zuletzt verwendet" : "Schnellstart", tint: .sinnAnnotation)
                Text(recipe.title).font(SinnType.title(28)).tracking(-0.4)
                Text(recipe.principle).font(.system(size: 14)).foregroundStyle(Color.sinnMuted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                fieldChips(recipe, limit: 6).padding(.top, 2)
                HStack(spacing: 14) {
                    Button { open(recipe) } label: { Label("Ausfüllen", systemImage: "pencil.line") }.buttonStyle(PrimaryButtonStyle())
                    Text(uses == 0 ? "\(recipe.fields.count) Felder" : "\(recipe.fields.count) Felder · \(uses)× verwendet")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sinnMuted)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            Text(recipe.template.replacingOccurrences(of: "{{", with: "[").replacingOccurrences(of: "}}", with: "]"))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.sinnMuted).lineSpacing(3).lineLimit(8)
                .padding(16).frame(width: 260, alignment: .topLeading)
                .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.05)))
                .rotationEffect(.degrees(1.5))
                .accessibilityHidden(true)
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 28, elevated: true)
    }

    private func card(_ recipe: PromptRecipe) -> some View {
        Button { open(recipe) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(recipe.title).font(.system(size: 18, weight: .semibold)).multilineTextAlignment(.leading).padding(.trailing, 18)
                Text(recipe.principle).font(.system(size: 13)).foregroundStyle(Color.sinnMuted).multilineTextAlignment(.leading).lineSpacing(3).lineLimit(3)
                Spacer(minLength: 0)
                fieldChips(recipe, limit: 3)
            }
            .padding(22).frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        }
        .buttonStyle(LiftCardStyle())
    }

    private func fieldChips(_ recipe: PromptRecipe, limit: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(recipe.fields.prefix(limit)) { field in
                Text(field.label).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.sinnAnnotation)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.sinnAnnotationWash, in: Capsule())
            }
            if recipe.fields.count > limit { Text("+\(recipe.fields.count - limit)").font(.system(size: 11)).foregroundStyle(Color.sinnMuted) }
        }
    }

    // MARK: Detail

    private func recipeDetail(_ recipe: PromptRecipe) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Button { withAnimation(SinnMotion.page) { model.selectedRecipe = nil } } label: { Label("Alle Vorlagen", systemImage: "chevron.left") }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button { beginEditing(recipe) } label: { Label("Vorlage bearbeiten", systemImage: "slider.horizontal.3") }.buttonStyle(SecondaryButtonStyle())
                Menu {
                    Button { model.duplicateRecipe(recipe.id) } label: { Label("Duplizieren", systemImage: "plus.square.on.square") }
                    Button { model.export(recipe) } label: { Label("Exportieren", systemImage: "square.and.arrow.up") }
                    Divider()
                    Button(role: .destructive) { deletingEpoch = model.accountEpoch; deleting = recipe.id } label: { Label("Löschen", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .bold)).frame(width: 42, height: 42)
                        .background(Color.sinnStructure.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Weitere Aktionen").accessibilityLabel("Weitere Aktionen")
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionEyebrow(text: "Vorlage · Version \(recipe.version)", tint: .sinnAnnotation)
                Text(recipe.title).font(SinnType.display(38)).tracking(-1).fixedSize(horizontal: false, vertical: true)
                Text(recipe.principle).font(.system(size: 16)).foregroundStyle(Color.sinnMuted).lineSpacing(4).frame(maxWidth: 640, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 16) {
                fieldsCard(recipe).frame(maxWidth: .infinity)
                previewCard(recipe).frame(maxWidth: .infinity)
            }
            historyCard(recipe)
        }
    }

    private func fieldsCard(_ recipe: PromptRecipe) -> some View {
        let filled = recipe.fields.filter { !(recipe.values[$0.id] ?? "").isBlank }.count
        return VStack(alignment: .leading, spacing: 16) {
            StepHeading(number: 1, title: "Ausfüllen", done: !recipe.fields.isEmpty && filled == recipe.fields.count)
            if recipe.fields.isEmpty {
                Text("Diese Vorlage hat noch keine Felder. Unter „Vorlage bearbeiten“ ersetzt du wechselnde Angaben durch benannte Felder.")
                    .font(.system(size: 13)).foregroundStyle(Color.sinnMuted).lineSpacing(3)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(filled), total: Double(recipe.fields.count)).tint(Color.sinnAnnotation)
                    Text("\(filled) von \(recipe.fields.count) Feldern ausgefüllt").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.sinnMuted)
                }
                ForEach(recipe.fields) { field in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(field.label).font(.system(size: 13, weight: .semibold))
                            Text(field.required ? "benötigt" : "freiwillig").font(.system(size: 11)).foregroundStyle(Color.sinnMuted)
                            Spacer()
                            Button("Offenlassen") { setValue("[\(field.label) noch offen]", field: field.id, recipe: recipe.id) }
                                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.sinnMuted)
                        }
                        TextField(field.label, text: Binding(get: { recipe.values[field.id] ?? "" }, set: { setValue($0, field: field.id, recipe: recipe.id) }), axis: .vertical)
                            .font(.system(size: fontSize)).textFieldStyle(SinnFieldStyle()).lineLimit(1...6)
                    }
                }
            }
        }
        .paperCard(radius: 24, padding: 22)
    }

    private func previewCard(_ recipe: PromptRecipe) -> some View {
        let rendered = recipe.render()
        return VStack(alignment: .leading, spacing: 16) {
            StepHeading(number: 2, title: "Dein fertiger Prompt", done: rendered.isReady)
            preview(recipe, rendered: rendered)
                .font(.system(size: fontSize)).lineSpacing(5).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            if !rendered.missingRequired.isEmpty {
                Label("Ergänze noch: " + rendered.missingRequired.joined(separator: ", ") + ". Oder wähle bewusst „Offenlassen“ für einen sichtbaren Platzhalter.", systemImage: "arrow.left")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.orange).lineSpacing(2)
            }
            if !rendered.validationErrors.isEmpty { LearningNotice(text: rendered.validationErrors.joined(separator: "\n")) }
            if !rendered.unknownFields.isEmpty {
                Text("Als Platzhalter erkennbar: " + rendered.unknownFields.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Color.sinnMuted)
            }
            HandoffButton(service: handoff, prompt: rendered.text, beforeOpen: { model.recordUse(recipe) }, expanded: true).disabled(!rendered.isReady)
            HandoffStatus(service: handoff, prompt: rendered.text)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 26, elevated: true)
    }

    /// The rendered prompt with your values in blue and open gaps in orange. Falls back to the
    /// plain render when the template has errors, so the preview never disagrees with the handoff.
    private func preview(_ recipe: PromptRecipe, rendered: RecipeRender) -> Text {
        guard rendered.validationErrors.isEmpty, let expression = try? NSRegularExpression(pattern: "\\{\\{([^{}]+)\\}\\}") else { return Text(rendered.text) }
        let source = recipe.template as NSString
        let labels = Dictionary(recipe.fields.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        var result = Text("")
        var offset = 0
        for match in expression.matches(in: recipe.template, range: NSRange(location: 0, length: source.length)) {
            result = result + Text(source.substring(with: NSRange(location: offset, length: match.range.location - offset)))
            let id = source.substring(with: match.range(at: 1))
            let raw = recipe.values[id] ?? ""
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                result = result + Text("[\(labels[id] ?? id) noch offen]").foregroundColor(.orange).fontWeight(.semibold)
            } else if value.hasPrefix("[") && value.hasSuffix("]") {
                result = result + Text(raw).foregroundColor(.orange).fontWeight(.semibold)
            } else {
                result = result + Text(raw).foregroundColor(Color.sinnAnnotation).fontWeight(.semibold)
            }
            offset = NSMaxRange(match.range)
        }
        return result + Text(source.substring(from: offset))
    }

    @ViewBuilder private func historyCard(_ recipe: PromptRecipe) -> some View {
        let uses = model.state.recipeUses.filter { $0.recipe.id == recipe.id }
        let versions = model.state.recipeVersions.filter { $0.id == recipe.id }
        if !uses.isEmpty || !versions.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(uses.reversed()) { use in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Verwendet: \(use.createdAt.formatted(date: .abbreviated, time: .shortened)) · Version \(use.recipe.version)").font(.system(size: 12, weight: .medium))
                            Text(use.renderedText).font(.system(size: 13)).foregroundStyle(Color.sinnMuted).textSelection(.enabled)
                        }
                        .padding(.vertical, 10)
                    }
                    ForEach(versions, id: \.version) { version in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Vorlage Version \(version.version): \(version.title)").font(.system(size: 12, weight: .medium))
                            Text(version.template).font(.system(size: 12)).foregroundStyle(Color.sinnMuted).textSelection(.enabled)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.top, 6)
            } label: {
                Label("Frühere Versionen und Verwendungen (\(uses.count + versions.count))", systemImage: "clock.arrow.circlepath").font(.system(size: 13, weight: .semibold))
            }
            .tint(Color.sinnInk)
            .paperCard(radius: 20, padding: 18)
        }
    }

    // MARK: Helpers

    private func useCount(_ recipe: PromptRecipe) -> Int { model.state.recipeUses.filter { $0.recipe.id == recipe.id }.count }
    private func open(_ recipe: PromptRecipe) { withAnimation(SinnMotion.page) { model.selectedRecipe = recipe.id } }
    private func beginEditing(_ recipe: PromptRecipe) { editingEpoch = model.accountEpoch; editing = recipe }
    private func setValue(_ value: String, field: String, recipe: UUID) { if let index = model.state.recipes.firstIndex(where: { $0.id == recipe }) { model.state.recipes[index].values[field] = value } }
}

struct RecipeEditor: View {
    @State var recipe: PromptRecipe
    let onSave: (PromptRecipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newLabel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    SectionEyebrow(text: "Vorlage gestalten", tint: .sinnAnnotation)
                    Text(recipe.title.isBlank ? "Neue Vorlage" : recipe.title).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                }
                Spacer()
                Button("Abbrechen") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    editorSection("Name") {
                        TextField("Name der Vorlage", text: $recipe.title).font(.system(size: 17, weight: .medium)).textFieldStyle(SinnFieldStyle())
                    }
                    editorSection("Text der Vorlage") {
                        Text("Ersetze wechselnde Angaben durch ein Feld, zum Beispiel {{ziel}}. Feste Fakten bleiben stehen. Es werden keine persönlichen Vorlieben automatisch übernommen.")
                            .font(.system(size: 12)).foregroundStyle(Color.sinnMuted).lineSpacing(2)
                        TextEditor(text: $recipe.template).font(.system(size: 15)).scrollContentBackground(.hidden).frame(minHeight: 200)
                            .accessibilityLabel("Promptvorlage").sinnEditorSurface()
                    }
                    editorSection("Felder") {
                        ForEach($recipe.fields) { $field in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 5) {
                                    TextField("Feldname", text: $field.label).textFieldStyle(SinnFieldStyle())
                                    Text("{{\(field.id)}}").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.sinnMuted).textSelection(.enabled)
                                }
                                Toggle("Benötigt", isOn: $field.required).toggleStyle(.checkbox)
                                Button { removeField(field.id) } label: { Image(systemName: "minus.circle") }
                                    .buttonStyle(.plain).help("Feld entfernen").accessibilityLabel("Feld \(field.label) entfernen")
                            }
                        }
                        HStack {
                            TextField("Neues Feld, etwa Empfänger", text: $newLabel).textFieldStyle(SinnFieldStyle())
                            Button { addField() } label: { Label("Feld ergänzen", systemImage: "plus") }.buttonStyle(SecondaryButtonStyle())
                                .disabled(newLabel.isBlank || recipe.fields.count >= 30)
                        }
                        Text("Neue Felder werden am Ende eingefügt. Verschiebe ihren Platzhalter an die passende Stelle im Text.").font(.system(size: 11)).foregroundStyle(Color.sinnMuted)
                    }
                    editorSection("Merksatz") {
                        TextField("Ein hilfreiches Prinzip", text: $recipe.principle, axis: .vertical).textFieldStyle(SinnFieldStyle()).lineLimit(2...4)
                    }
                    ForEach(recipe.render().validationErrors, id: \.self) { Label($0, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(Color.orange) }
                }
                .padding(.horizontal, 28).padding(.bottom, 20)
            }
            HStack {
                Spacer()
                Button { onSave(recipe); dismiss() } label: { Label("Vorlage speichern", systemImage: "checkmark") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(!recipe.render().validationErrors.isEmpty)
            }
            .padding(.horizontal, 28).padding(.vertical, 18)
            .background(Color.sinnStructure.opacity(0.4))
        }
        .frame(width: 650, height: 730).background(Color.sinnWindow).foregroundStyle(Color.sinnInk).tint(Color.sinnAnnotation)
    }

    private func editorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: title)
            content()
        }
        .paperCard(radius: 18, padding: 18)
    }

    private func addField() { let id = "feld_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased(); let label = newLabel.trimmingCharacters(in: .whitespacesAndNewlines); recipe.fields.append(RecipeField(id: id, label: label)); recipe.template += "\n\(label): {{\(id)}}"; newLabel = "" }
    private func removeField(_ id: String) { if let field = recipe.fields.first(where: { $0.id == id }) { recipe.template = recipe.template.replacingOccurrences(of: "{{\(id)}}", with: "[\(field.label) noch offen]") }; recipe.fields.removeAll { $0.id == id }; recipe.values.removeValue(forKey: id) }
}
