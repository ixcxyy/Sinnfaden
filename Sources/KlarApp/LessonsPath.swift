import SwiftUI
import KlarCore

/// Teaching material around each fixed exercise: why it matters, one worked example and a
/// line to keep. The exercises and their local checks stay in `LessonCatalog`.
struct LessonGuide {
    let chapter: Int
    let minutes: Int
    let why: String
    let before: String
    let after: String
    /// The part of `after` that is new; it is highlighted in the example.
    let added: String
    let takeaway: String

    static let chapters = [
        ("Klar sagen, was du willst", "Ziel und Umstände: das Fundament jeder Anfrage."),
        ("Passend formen", "Für wen, in welchem Ton, in welcher Form."),
        ("Weiterarbeiten", "Nachfragen und prüfen, bevor du etwas übernimmst.")
    ]

    static let all: [String: LessonGuide] = [
        "goal": LessonGuide(chapter: 0, minutes: 2,
            why: "Eine KI kann nur raten, wofür du das Ergebnis brauchst. Fehlt das Ziel, bekommst du meist etwas Allgemeines, das du erst umbauen musst.",
            before: "Schreib einen Text über unseren Verein.",
            after: "Schreib einen kurzen Text über unseren Verein, der neue Mitglieder zum Probetraining einlädt.",
            added: "der neue Mitglieder zum Probetraining einlädt", takeaway: "Sag nicht nur was, sondern wozu."),
        "context": LessonGuide(chapter: 0, minutes: 2,
            why: "Umstände, die nur du kennst, verändern die beste Antwort: Zeit, Ort, Personen, Grenzen. Erfundene Details helfen dagegen nicht. Nenne nur, was stimmt.",
            before: "Gib mir ein Rezept fürs Abendessen.",
            after: "Gib mir ein Rezept fürs Abendessen für zwei Personen, fertig in 20 Minuten, ohne Backofen.",
            added: "für zwei Personen, fertig in 20 Minuten, ohne Backofen", takeaway: "Nenne, was du weißt und was die Antwort verändert."),
        "audience": LessonGuide(chapter: 1, minutes: 2,
            why: "Dieselbe Sache klingt für ein Kind anders als für eine Fachperson. Zielgruppe und Ton bestimmen Wortwahl, Beispiele und Tiefe.",
            before: "Erkläre, was Inflation ist.",
            after: "Erkläre einer 12-Jährigen in freundlichem, einfachem Ton, was Inflation ist.",
            added: "einer 12-Jährigen in freundlichem, einfachem Ton", takeaway: "Sag, für wen es ist und wie es klingen soll."),
        "format": LessonGuide(chapter: 1, minutes: 2,
            why: "Ohne Vorgabe wählt die KI die Form selbst, oft länger als nötig. Form und Länge machen das Ergebnis sofort benutzbar.",
            before: "Gib mir Tipps für ein Vorstellungsgespräch.",
            after: "Gib mir Tipps für ein Vorstellungsgespräch – als fünf kurze Stichpunkte mit je einem Satz.",
            added: "– als fünf kurze Stichpunkte mit je einem Satz", takeaway: "Wähle Form und Länge, bevor die KI es tut."),
        "followup": LessonGuide(chapter: 2, minutes: 3,
            why: "Die erste Antwort ist selten die letzte. Eine gezielte Rückfrage sagt, was fehlt, statt von vorn zu beginnen.",
            before: "Das ist nicht gut, versuch es nochmal.",
            after: "Die Tipps sind mir zu allgemein. Gib mir zu Tipp 2 ein konkretes Beispiel aus dem Büroalltag.",
            added: "Gib mir zu Tipp 2 ein konkretes Beispiel aus dem Büroalltag.", takeaway: "Sag, was fehlt und was als Nächstes kommen soll."),
        "check": LessonGuide(chapter: 2, minutes: 3,
            why: "KI-Antworten klingen sicher, auch wenn ein Detail falsch ist. Wer Namen, Zahlen und Termine kurz mit der eigenen Anfrage vergleicht, fängt Fehler früh ab.",
            before: "Danke, passt!",
            after: "In deiner Antwort steht 15 Uhr, ich hatte 14 Uhr geschrieben. Bitte korrigiere nur die Uhrzeit.",
            added: "ich hatte 14 Uhr geschrieben. Bitte korrigiere nur die Uhrzeit.", takeaway: "Prüfe Namen, Zahlen und Termine, bevor du übernimmst.")
    ]

    static func of(_ lesson: PromptLesson) -> LessonGuide {
        all[lesson.id] ?? LessonGuide(chapter: 0, minutes: 2, why: lesson.principle, before: lesson.baseline, after: lesson.solution, added: "", takeaway: lesson.principle)
    }
}

enum LessonStatus {
    case new, started, done
    var label: String { switch self { case .new: "Neu"; case .started: "Begonnen"; case .done: "Geschafft" } }
    var symbol: String { switch self { case .new: "circle"; case .started: "circle.lefthalf.filled"; case .done: "checkmark.circle.fill" } }
    var tint: Color { switch self { case .new: .sinnMuted; case .started: .orange; case .done: .sinnAnnotation } }
}

// MARK: - Path overview

struct LessonsView: View {
    @ObservedObject var model: LearningWorkspace
    let fontSize: Double

    private var lessons: [PromptLesson] { LessonCatalog.lessons }

    func status(_ lesson: PromptLesson) -> LessonStatus {
        let attempts = model.state.lessonAttempts.filter { $0.lessonID == lesson.id }
        if attempts.contains(where: { $0.feedback.meetsExercise }) { return .done }
        return attempts.isEmpty ? .new : .started
    }

    var body: some View {
        if let storageError = model.storageError { LearningNotice(text: storageError) }
        if let lesson = lessons.first(where: { $0.id == model.selectedLesson }) {
            LessonDetail(model: model, lesson: lesson, fontSize: fontSize, next: nextLesson(after: lesson))
                .id(lesson.id)
        } else {
            LearningPageHeader(eyebrow: "Lernpfad", title: "Kurz lernen", subtitle: "Sechs kleine Lektionen, je zwei bis drei Minuten. Erst verstehen, dann selbst ausprobieren.")
            progressHero.sinnReveal(1)
            ForEach(Array(LessonGuide.chapters.enumerated()), id: \.offset) { index, chapter in
                chapterSection(index: index, title: chapter.0, subtitle: chapter.1).sinnReveal(index + 2)
            }
        }
    }

    private func nextLesson(after lesson: PromptLesson) -> PromptLesson? {
        guard let index = lessons.firstIndex(of: lesson), lessons.indices.contains(index + 1) else { return nil }
        return lessons[index + 1]
    }

    private var recommended: PromptLesson {
        lessons.first { status($0) == .started } ?? lessons.first { status($0) == .new } ?? lessons[0]
    }

    private var progressHero: some View {
        let done = lessons.filter { status($0) == .done }.count
        let next = recommended
        let guide = LessonGuide.of(next)
        return HStack(spacing: 26) {
            ZStack {
                Circle().stroke(Color.sinnStructure, lineWidth: 10)
                Circle().trim(from: 0, to: CGFloat(done) / CGFloat(lessons.count))
                    .stroke(Color.sinnAnnotation, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(done)").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("von \(lessons.count)").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sinnMuted)
                }
            }
            .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 8) {
                Text(done == lessons.count ? "ALLES GESCHAFFT · NOCHMAL ÜBEN" : "ALS NÄCHSTES").font(SinnType.eyebrow).tracking(1.4).foregroundStyle(Color.sinnAnnotation)
                Text(next.title).font(SinnType.title(26))
                Text(next.principle).font(.system(size: 14)).foregroundStyle(Color.sinnMuted)
                HStack(spacing: 12) {
                    Button { withAnimation(SinnMotion.page) { model.selectedLesson = next.id } } label: {
                        Label(status(next) == .started ? "Weitermachen" : "Lektion starten", systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Label("≈ \(guide.minutes) Min.", systemImage: "clock").font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sinnMuted)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 28, elevated: true)
    }

    private func chapterSection(index: Int, title: String, subtitle: String) -> some View {
        let members = lessons.filter { LessonGuide.of($0).chapter == index }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Kapitel \(index + 1)").font(SinnType.eyebrow).tracking(1.2).foregroundStyle(Color.sinnMuted)
                Text(title).font(.system(size: 19, weight: .semibold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Color.sinnMuted)
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(members) { lesson in lessonCard(lesson) }
            }
        }
        .padding(.top, 10)
    }

    private func lessonCard(_ lesson: PromptLesson) -> some View {
        let number = (lessons.firstIndex(of: lesson) ?? 0) + 1
        let state = status(lesson)
        let guide = LessonGuide.of(lesson)
        return Button { withAnimation(SinnMotion.page) { model.selectedLesson = lesson.id } } label: {
            HStack(alignment: .top, spacing: 16) {
                Text(String(format: "%02d", number))
                    .font(.system(size: 30, weight: .regular, design: .serif)).foregroundStyle(Color.sinnAnnotation)
                VStack(alignment: .leading, spacing: 7) {
                    Text(lesson.title).font(.system(size: 17, weight: .semibold)).multilineTextAlignment(.leading)
                    Text(lesson.principle).font(.system(size: 13)).foregroundStyle(Color.sinnMuted).multilineTextAlignment(.leading).lineSpacing(2)
                    HStack(spacing: 10) {
                        Label(state.label, systemImage: state.symbol).foregroundStyle(state.tint)
                        Label("\(guide.minutes) Min.", systemImage: "clock").foregroundStyle(Color.sinnMuted)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.top, 4)
                }
                .padding(.trailing, 16)
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        }
        .buttonStyle(LiftCardStyle())
    }
}

// MARK: - One lesson in three steps

private struct LessonDetail: View {
    @ObservedObject var model: LearningWorkspace
    let lesson: PromptLesson
    let fontSize: Double
    let next: PromptLesson?
    @State private var step = 0
    @Namespace private var stepMarker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var guide: LessonGuide { LessonGuide.of(lesson) }
    private let steps = ["Verstehen", "Ausprobieren", "Festhalten"]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Button { withAnimation(SinnMotion.page) { model.selectedLesson = nil } } label: { Label("Lernpfad", systemImage: "chevron.left") }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                stepTabs
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("KAPITEL \(guide.chapter + 1) · \(LessonGuide.chapters[guide.chapter].0.uppercased())").font(SinnType.eyebrow).tracking(1.3).foregroundStyle(Color.sinnAnnotation)
                Text(lesson.title).font(SinnType.display(40)).tracking(-1.2)
            }
            Group {
                switch step {
                case 0: understand
                case 1: practice
                default: keep
                }
            }
            .id(step)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(x: 30)), removal: .opacity.combined(with: .offset(x: -30))))
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : SinnMotion.page, value: step)
        .onAppear {
            // Returning learners continue where the work is: straight to practice.
            if !model.state.lessonAttempts.filter({ $0.lessonID == lesson.id }).isEmpty { step = 1 }
        }
    }

    private var stepTabs: some View {
        HStack(spacing: 4) {
            ForEach(steps.indices, id: \.self) { index in
                Button { step = index } label: {
                    HStack(spacing: 6) {
                        Text("\(index + 1)").font(.system(size: 11, weight: .bold))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(step >= index ? Color.sinnAnnotation : Color.sinnChrome))
                            .foregroundStyle(.white)
                        Text(steps[index]).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(step == index ? Color.sinnInk : Color.sinnMuted)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background {
                        if step == index { Capsule().fill(Color.white).matchedGeometryEffect(id: "step", in: stepMarker) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.sinnStructure.opacity(0.8), in: Capsule())
    }

    // MARK: Step 1

    private var understand: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(lesson.principle).font(.system(size: 24, weight: .semibold)).lineSpacing(4)
            Text(guide.why).font(.system(size: 16)).foregroundStyle(Color.sinnMuted).lineSpacing(5).frame(maxWidth: 680, alignment: .leading)
            HStack(alignment: .top, spacing: 14) {
                exampleCard(label: "Vorher", text: Text(guide.before), tint: Color.sinnMuted, wash: Color.sinnStructure.opacity(0.6))
                Image(systemName: "arrow.right").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.sinnAnnotation).padding(.top, 52)
                exampleCard(label: "Nachher", text: highlighted(guide.after, added: guide.added), tint: Color.sinnAnnotation, wash: Color.sinnAnnotationWash)
            }
            HStack {
                Spacer()
                Button { step = 1 } label: { Label("Selbst ausprobieren", systemImage: "arrow.right") }.buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(28).cardSurface(radius: 28, elevated: true)
    }

    private func exampleCard(label: String, text: Text, tint: Color, wash: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased()).font(SinnType.eyebrow).tracking(1.4).foregroundStyle(tint)
            text.font(.system(size: 16)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(wash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func highlighted(_ sentence: String, added: String) -> Text {
        guard !added.isEmpty, let range = sentence.range(of: added) else { return Text(sentence) }
        return Text(sentence[..<range.lowerBound])
            + Text(sentence[range]).foregroundColor(Color.sinnAnnotation).fontWeight(.semibold)
            + Text(sentence[range.upperBound...])
    }

    // MARK: Step 2

    private var attempts: [LessonAttempt] { model.state.lessonAttempts.filter { $0.lessonID == lesson.id } }

    private var practice: some View {
        let practiceStage = LessonCatalog.stage(for: model.state.lessonAttempts, lessonID: lesson.id)
        let draft = model.state.lessonDrafts[lesson.id] ?? ""
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("AUSGANGSPUNKT").font(SinnType.eyebrow).tracking(1.4).foregroundStyle(Color.sinnMuted)
                Text(lesson.baseline).font(.system(size: fontSize)).lineSpacing(4).textSelection(.enabled)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.sinnStructure.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Label(lesson.action, systemImage: "pencil.and.outline").font(.system(size: 18, weight: .semibold)).lineSpacing(4)
            if practiceStage == .transfer {
                Text("Du hast dieses Prinzip schon mehrfach selbst angewendet. Formuliere eine andere Lösung, zuerst ohne Hinweis.").font(.system(size: 13)).foregroundStyle(Color.sinnMuted)
            }
            TextField("Dein eigener Versuch", text: Binding(get: { model.state.lessonDrafts[lesson.id] ?? "" }, set: { model.state.lessonDrafts[lesson.id] = $0 }), axis: .vertical)
                .font(.system(size: fontSize)).lineLimit(3...8).textFieldStyle(SinnFieldStyle())
            HStack(spacing: 12) {
                Button { model.submitLesson(lesson) } label: { Label("Versuch prüfen", systemImage: "checkmark") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attempts.last?.answer == draft)
                Button { withAnimation(SinnMotion.reveal) { model.state.lessonHelp[lesson.id] = true } } label: { Label("Hinweis", systemImage: "lightbulb") }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Lösung ansehen") { withAnimation(SinnMotion.reveal) { model.state.lessonSolutionRevealed[lesson.id] = true } }
                    .buttonStyle(.plain).foregroundStyle(Color.sinnMuted).font(.system(size: 13, weight: .medium))
                Spacer()
            }
            if model.state.lessonHelp[lesson.id] == true { LearningNotice(text: lesson.hint) }
            if model.state.lessonSolutionRevealed[lesson.id] == true { LearningNotice(text: "Ein möglicher Vorschlag:\n" + lesson.solution) }
            if let last = attempts.last {
                VStack(alignment: .leading, spacing: 12) {
                    Label(last.feedback.meetsExercise ? "Das passt zur Aufgabe" : "Noch nicht ganz", systemImage: last.feedback.meetsExercise ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(last.feedback.meetsExercise ? Color.sinnAnnotation : Color.orange)
                    Text(last.feedback.observation).font(.system(size: 14)).lineSpacing(4).foregroundStyle(Color.sinnInk)
                    HStack {
                        Button("Noch einmal versuchen") { model.nextLessonAttempt(lesson) }.buttonStyle(SecondaryButtonStyle())
                        Spacer()
                        if last.feedback.meetsExercise {
                            Button { step = 2 } label: { Label("Merksatz", systemImage: "arrow.right") }.buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
                .padding(18)
                .background((last.feedback.meetsExercise ? Color.sinnAnnotationWash : Color.orange.opacity(0.08)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if !attempts.isEmpty {
                DisclosureGroup("Deine bisherigen Versuche (\(attempts.count))") {
                    ForEach(attempts.reversed()) { attempt in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(attempt.answer).font(.system(size: 14))
                            Text(attempt.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(Color.sinnMuted)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .font(.system(size: 13))
            }
        }
        .padding(28).cardSurface(radius: 28, elevated: true)
    }

    // MARK: Step 3

    private var keep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ZUM MITNEHMEN").font(SinnType.eyebrow).tracking(1.4).foregroundStyle(Color.sinnAnnotation)
            Text("„\(guide.takeaway)“").font(SinnType.display(34)).tracking(-0.8).fixedSize(horizontal: false, vertical: true)
            Text("Achte beim nächsten eigenen Prompt einmal bewusst darauf. Sinnfaden markiert dir passende Stellen im Vorschlag.")
                .font(.system(size: 15)).foregroundStyle(Color.sinnMuted).lineSpacing(4)
            HStack {
                Button { withAnimation(SinnMotion.page) { model.selectedLesson = nil } } label: { Label("Zum Lernpfad", systemImage: "list.bullet") }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                if let next {
                    Button { withAnimation(SinnMotion.page) { model.selectedLesson = next.id } } label: { Label("Nächste Lektion: \(next.title)", systemImage: "arrow.right") }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color.white, Color.sinnAnnotationWash], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white))
        .shadow(color: Color.sinnAnnotation.opacity(0.12), radius: 24, y: 12)
    }
}
