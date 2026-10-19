import SwiftUI
import KlarCore

/// "Antworten vergleichen": one change, two real answers, one criterion to judge them by.
/// Overview: the comparison that is waiting for you as a hero, then all others.
/// Detail: the criterion dominates, the two prompts and later the two answers sit side by side.
struct ComparisonView: View {
    @ObservedObject var model: LearningWorkspace
    let fontSize: Double
    /// Leads to the prompt page, where every comparison starts.
    var onStart: () -> Void = {}

    var body: some View {
        if let storageError = model.storageError { LearningNotice(text: storageError) }
        if let run = model.activeComparison {
            detail(run)
        } else {
            LearningPageHeader(eyebrow: "Eine Änderung entdecken", title: "Antworten vergleichen",
                               subtitle: "Wie viel bewirkt eine einzelne Angabe? Lass dir zwei echte Antworten geben, vorher und nachher, und prüfe sie an einem klaren Kriterium.")
            if model.state.comparisons.isEmpty {
                GuidedEmptyState(symbol: "rectangle.split.2x1", title: "Noch kein Vergleich",
                                 text: "Vergleiche entstehen aus einem Vorschlag. So siehst du an einer echten Antwort, was eine Änderung bringt.",
                                 steps: ["Schreib einen Prompt und lass ihn verbessern.", "Öffne eine markierte Änderung und wähle „Im Ergebnis ansehen“.", "Hier erzeugst du beide Antworten und vergleichst sie."],
                                 actionTitle: "Prompt verbessern", actionSymbol: "square.and.pencil", action: onStart)
                    .sinnReveal(1)
            } else {
                overview
            }
        }
        if let error = model.errorMessage { LearningNotice(text: error) }
    }

    // MARK: Overview

    @ViewBuilder private var overview: some View {
        let runs = model.state.comparisons
        let featured = runs.first { isReady($0) } ?? runs[0]
        hero(featured).sinnReveal(1)
        let others = runs.filter { $0.id != featured.id }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionEyebrow(text: "Alle Vergleiche · \(runs.count)")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                    ForEach(others, id: \.id) { run in row(run) }
                }
            }
            .padding(.top, 6)
            .sinnReveal(2)
        }
    }

    private func hero(_ run: ComparisonRun) -> some View {
        let ready = isReady(run)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionEyebrow(text: ready ? "Bereit zum Ausprobieren" : "Zuletzt verglichen", tint: .sinnAnnotation)
                Spacer()
                statusPill(run)
            }
            Text(run.plan.title).font(SinnType.title(28)).tracking(-0.4).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "scope").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.sinnAnnotation).padding(.top, 2)
                Text(run.plan.criterion).font(.system(size: 15)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sinnAnnotationWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 14) {
                Button { withAnimation(SinnMotion.page) { model.selectedComparison = run.id } } label: {
                    Label(ready ? "Zwei Antworten erzeugen" : "Vergleich öffnen", systemImage: ready ? "play.fill" : "arrow.right")
                }
                .buttonStyle(PrimaryButtonStyle())
                Text(run.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sinnMuted)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 28, elevated: true)
    }

    private func row(_ run: ComparisonRun) -> some View {
        Button { withAnimation(SinnMotion.page) { model.selectedComparison = run.id } } label: {
            VStack(alignment: .leading, spacing: 10) {
                statusPill(run)
                Text(run.plan.title).font(.system(size: 16, weight: .semibold)).multilineTextAlignment(.leading).padding(.trailing, 18)
                Text(run.plan.criterion).font(.system(size: 13)).foregroundStyle(Color.sinnMuted).lineLimit(2).multilineTextAlignment(.leading)
                Text(run.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(Color.sinnMuted)
            }
            .padding(20).frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        }
        .buttonStyle(LiftCardStyle())
    }

    // MARK: Detail

    private func detail(_ run: ComparisonRun) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Button { withAnimation(SinnMotion.page) { model.selectedComparison = nil } } label: { Label("Alle Vergleiche", systemImage: "chevron.left") }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                statusPill(run)
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionEyebrow(text: "Vergleich · \(run.createdAt.formatted(date: .abbreviated, time: .shortened))", tint: .sinnAnnotation)
                Text(run.plan.title).font(SinnType.display(38)).tracking(-1).fixedSize(horizontal: false, vertical: true)
            }
            criterionCard(run.plan)
            HStack(alignment: .top, spacing: 12) {
                promptColumn("Vorher", run.plan.baseline, tint: .sinnMuted, wash: Color.white)
                Image(systemName: "arrow.right").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.sinnAnnotation).padding(.top, 44)
                promptColumn(run.plan.kind == .isolated ? "Mit dieser Änderung" : "Gesamter überarbeiteter Prompt", run.plan.variant, tint: .sinnAnnotation, wash: Color.sinnAnnotationWash)
            }
            .fixedSize(horizontal: false, vertical: true)
            if run.baselineAnswer.status == .pending && run.variantAnswer.status == .pending {
                startCard(run)
            } else {
                answers(run)
            }
            Label("Ein Beispiel, kein Beweis: KI-Antworten können von Versuch zu Versuch variieren. Prüfe beide am genannten Kriterium.", systemImage: "info.circle")
                .font(.system(size: 12)).foregroundStyle(Color.sinnMuted).lineSpacing(3)
        }
    }

    private func criterionCard(_ plan: ComparisonPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: "Darauf achtest du", tint: .sinnAnnotation)
            Text(plan.criterion).font(.system(size: 24, weight: .semibold)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            if !plan.note.isBlank {
                Text(plan.note).font(.system(size: 14)).foregroundStyle(Color.sinnMuted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color.white, Color.sinnAnnotationWash], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white))
        .shadow(color: Color.sinnAnnotation.opacity(0.12), radius: 22, y: 10)
    }

    private func promptColumn(_ title: String, _ text: String, tint: Color, wash: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: title, tint: tint)
            Text(text).font(.system(size: fontSize)).lineSpacing(4).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(wash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.black.opacity(0.05)))
    }

    private func startCard(_ run: ComparisonRun) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            StepHeading(number: 1, title: "Was erwartest du? (freiwillig)")
            TextField("Zum Beispiel: Die zweite Antwort wird kürzer und konkreter.", text: Binding(get: { run.prediction }, set: { model.setPrediction($0, id: run.id) }), axis: .vertical)
                .textFieldStyle(SinnFieldStyle()).lineLimit(2...4)
            StepHeading(number: 2, title: "Beide Antworten erzeugen")
            HStack(spacing: 14) {
                Button { model.runComparison(run.id) } label: { Label("Zwei Antworten erzeugen", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(model.comparisonBusy)
                Text("Nutzt zweimal dein KI-Kontingent · Modell: \(run.model.isEmpty ? "noch keines gewählt" : run.model)")
                    .font(.system(size: 12)).foregroundStyle(Color.sinnMuted)
            }
        }
        .paperCard(radius: 22, padding: 22)
    }

    @ViewBuilder private func answers(_ run: ComparisonRun) -> some View {
        if !run.prediction.isEmpty {
            Label("Deine Vermutung: \(run.prediction)", systemImage: "lightbulb").font(.system(size: 14)).foregroundStyle(Color.sinnMuted)
        }
        HStack(alignment: .top, spacing: 14) {
            answerPanel("Antwort vorher", run.baselineAnswer, tint: .sinnMuted)
            answerPanel("Antwort mit Änderung", run.variantAnswer, tint: .sinnAnnotation)
        }
        .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 14) {
            if model.comparisonBusy {
                Button("Vergleich abbrechen") { model.cancelComparison() }.buttonStyle(SecondaryButtonStyle())
            } else {
                Button { model.freshComparison(run) } label: { Label("Neuen Vergleich vorbereiten", systemImage: "arrow.clockwise") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            Text("Gleiches Modell für beide: \(run.model.isEmpty ? "noch keines gewählt" : run.model)").font(.system(size: 12)).foregroundStyle(Color.sinnMuted)
        }
    }

    private func answerPanel(_ title: String, _ answer: ComparisonAnswer, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionEyebrow(text: title, tint: tint)
                Spacer()
                if answer.status == .running { ThreadLoader(width: 50) }
                else { Text(label(answer.status)).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.sinnMuted) }
            }
            if !answer.text.isEmpty {
                Text(answer.text).font(.system(size: fontSize)).lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else if answer.status == .running {
                Text("Entsteht …").font(.system(size: 14)).foregroundStyle(Color.sinnMuted)
            }
            if let error = answer.error { LearningNotice(text: error) }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .paperCard(radius: 20, padding: 20)
    }

    // MARK: Status

    private func isReady(_ run: ComparisonRun) -> Bool { run.baselineAnswer.status == .pending && run.variantAnswer.status == .pending }

    private func statusPill(_ run: ComparisonRun) -> StatusPill {
        let statuses = [run.baselineAnswer.status, run.variantAnswer.status]
        if statuses.contains(.running) { return StatusPill(text: "Läuft", symbol: "ellipsis", tint: .orange) }
        if run.isComplete { return StatusPill(text: "Beide Antworten da", symbol: "checkmark.circle.fill", tint: .sinnAnnotation) }
        if isReady(run) { return StatusPill(text: "Bereit", symbol: "circle.dashed", tint: .sinnMuted) }
        return StatusPill(text: "Unvollständig", symbol: "exclamationmark.circle", tint: .orange)
    }

    private func label(_ status: ComparisonAnswerStatus) -> String {
        switch status { case .pending: return "Noch nicht angefordert"; case .running: return "Entsteht …"; case .completed: return "Vollständig"; case .failed: return "Fehlgeschlagen"; case .interrupted: return "Unvollständig / abgebrochen" }
    }
}
