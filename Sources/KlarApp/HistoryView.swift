import SwiftUI
import KlarCore

/// "Verlauf": your latest attempt as a "Weitermachen" hero, everything else grouped by day
/// in quiet rows, and the data controls at the end. Everything stays on this Mac.
struct HistoryView: View {
    @ObservedObject var model: AppModel
    let onDelete: () -> Void
    @State private var query = ""

    fileprivate static let german = Locale(identifier: "de_DE")

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SinnPageHeader(eyebrow: "Nur auf diesem Mac", title: "Dein Verlauf",
                           subtitle: "Deine Entwürfe, Vorschläge und eigenen Versuche, nach Konto getrennt. Öffne einen Eintrag, um dort weiterzumachen.")
            if model.history.isEmpty {
                GuidedEmptyState(symbol: "clock.arrow.circlepath", title: "Hier entsteht dein Verlauf",
                                 text: "Sobald du einen Prompt verbesserst, findest du ihn hier wieder, mit Vorschlag und deinen Übungen.",
                                 steps: ["Schreib auf, was du von ChatGPT möchtest.", "Lass Sinnfaden deinen Prompt verbessern.", "Hier kannst du jederzeit weitermachen."],
                                 actionTitle: "Ersten Prompt schreiben", actionSymbol: "square.and.pencil", action: { model.page = .coach })
                    .sinnReveal(1)
            } else {
                if query.isBlank, let latest = model.history.first { resumeHero(latest).sinnReveal(1) }
                listSection.sinnReveal(2)
                dataFooter.sinnReveal(3)
            }
        }
    }

    // MARK: Hero

    private func resumeHero(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionEyebrow(text: "Weitermachen", tint: .sinnAnnotation)
                Spacer()
                kindPill(entry)
            }
            Text("„\(entry.original.trimmingCharacters(in: .whitespacesAndNewlines))“")
                .font(.system(size: 24, weight: .semibold)).tracking(-0.3).lineSpacing(3).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if !entry.visiblePrompt.isBlank {
                VStack(alignment: .leading, spacing: 6) {
                    SectionEyebrow(text: "Verbesserter Prompt", tint: .sinnAnnotation)
                    Text(oneLine(entry.visiblePrompt)).font(.system(size: 14)).lineSpacing(3).lineLimit(3)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sinnAnnotationWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack(spacing: 14) {
                Button { model.select(entry) } label: { Label("Weitermachen", systemImage: "arrow.right") }.buttonStyle(PrimaryButtonStyle())
                Text(relativeDate(entry.createdAt)).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sinnMuted)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 28, elevated: true)
    }

    // MARK: List

    private var filtered: [HistoryEntry] {
        guard !query.isBlank else { return Array(model.history.dropFirst()) }
        return model.history.filter { $0.original.localizedCaseInsensitiveContains(query) || $0.visiblePrompt.localizedCaseInsensitiveContains(query) }
    }

    private var listSection: some View {
        let entries = filtered
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                SectionEyebrow(text: query.isBlank ? "Früher · \(entries.count)" : "Treffer · \(entries.count)")
                Spacer()
                if model.history.count > 3 { searchField }
            }
            if entries.isEmpty {
                Text(query.isBlank ? "Weitere Einträge erscheinen hier, sobald du mehr Prompts verbesserst." : "Nichts gefunden für „\(query)“.")
                    .font(.system(size: 13)).foregroundStyle(Color.sinnMuted).paperCard()
            } else {
                ForEach(groups(entries), id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title).font(.system(size: 15, weight: .semibold))
                        VStack(spacing: 0) {
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 { Divider().padding(.leading, 62) }
                                HistoryRow(entry: entry, kind: kind(entry), time: rowTime(entry.createdAt)) { model.select(entry) }
                            }
                        }
                        .padding(6)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.black.opacity(0.05)))
                        .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.sinnMuted)
            TextField("Im Verlauf suchen", text: $query).textFieldStyle(.plain).font(.system(size: 13))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.sinnMuted) }
                    .buttonStyle(.plain).accessibilityLabel("Suche leeren")
            }
        }
        .padding(.horizontal, 12).frame(width: 260, height: 34)
        .background(Color.white.opacity(0.75), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.06)))
    }

    private var dataFooter: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sinnMuted)
                .frame(width: 34, height: 34).background(Color.sinnStructure, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.history.count) \(model.history.count == 1 ? "Eintrag" : "Einträge") auf diesem Mac").font(.system(size: 13, weight: .semibold))
                Text("Keine Telemetrie. Du kannst alles exportieren oder löschen.").font(.system(size: 12)).foregroundStyle(Color.sinnMuted)
            }
            Spacer()
            Button { model.exportHistory() } label: { Label("Exportieren", systemImage: "square.and.arrow.up") }.buttonStyle(SecondaryButtonStyle())
            Button(role: .destructive, action: onDelete) { Label("Löschen", systemImage: "trash") }
                .buttonStyle(.plain).foregroundStyle(Color.red.opacity(0.85)).font(.system(size: 13, weight: .medium))
        }
        .paperCard(radius: 20, padding: 16)
    }

    // MARK: Grouping and labels

    private struct DayGroup { let title: String; let entries: [HistoryEntry] }

    /// Entries arrive newest first, so consecutive entries share a day title.
    private func groups(_ entries: [HistoryEntry]) -> [DayGroup] {
        var result: [DayGroup] = []
        for entry in entries {
            let title = dayTitle(entry.createdAt)
            if let last = result.last, last.title == title {
                result[result.count - 1] = DayGroup(title: title, entries: last.entries + [entry])
            } else {
                result.append(DayGroup(title: title, entries: [entry]))
            }
        }
        return result
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInYesterday(date) { return "Gestern" }
        if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day, days < 7 {
            return date.formatted(.dateTime.weekday(.wide).locale(Self.german))
        }
        return date.formatted(.dateTime.month(.wide).year().locale(Self.german))
    }

    /// Recent rows show the time; older ones also the day, since their group is a whole month.
    private func rowTime(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: Date())).day ?? 0
        return days < 7 ? date.formatted(.dateTime.hour().minute().locale(Self.german))
                        : date.formatted(.dateTime.day().month(.abbreviated).locale(Self.german))
    }

    private func relativeDate(_ date: Date) -> String {
        "\(dayTitle(date)), \(date.formatted(.dateTime.hour().minute().locale(Self.german)))"
    }

    fileprivate struct Kind { let label: String; let symbol: String; let tint: Color }

    fileprivate func kind(_ entry: HistoryEntry) -> Kind {
        let count = entry.practiceAttempts.count
        let practice = count == 0 ? "" : " · \(count) \(count == 1 ? "Übung" : "Übungen")"
        switch entry.response?.status {
        case .improved: return Kind(label: "Vorschlag" + practice, symbol: "sparkles", tint: .sinnAnnotation)
        case .already_good: return Kind(label: "Schon gut" + practice, symbol: "checkmark.seal", tint: .sinnAnnotation)
        case .needs_clarification: return Kind(label: "Rückfrage offen", symbol: "questionmark.bubble", tint: .orange)
        case nil: return Kind(label: entry.outcome == "interrupted" || entry.outcome == "error" ? "Unterbrochen" : "Entwurf", symbol: "doc.text", tint: .sinnMuted)
        }
    }

    private func kindPill(_ entry: HistoryEntry) -> StatusPill {
        let value = kind(entry)
        return StatusPill(text: value.label, symbol: value.symbol, tint: value.tint)
    }
}

/// Previews read as one flowing line; paragraph breaks would leave empty rows.
private func oneLine(_ text: String) -> String {
    text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
}

/// One quiet row: what kind of entry, your words, the improved prompt underneath, the time.
private struct HistoryRow: View {
    let entry: HistoryEntry
    let kind: HistoryView.Kind
    let time: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: kind.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(kind.tint)
                    .frame(width: 36, height: 36)
                    .background(kind.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.original.trimmingCharacters(in: .whitespacesAndNewlines)).font(.system(size: 15, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                    if !entry.visiblePrompt.isBlank {
                        Text(oneLine(entry.visiblePrompt)).font(.system(size: 12)).foregroundStyle(Color.sinnMuted).lineLimit(1)
                    }
                    Text(kind.label).font(.system(size: 11, weight: .semibold)).foregroundStyle(kind.tint)
                }
                Spacer(minLength: 12)
                Text(time).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.sinnMuted).monospacedDigit()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(hovered ? Color.sinnInk : Color.sinnMuted.opacity(0.6))
                    .offset(x: hovered && !reduceMotion ? 2 : 0)
                    .padding(.top, 1)
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
            .background(Color.sinnStructure.opacity(hovered ? 0.6 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(SinnMotion.hover) { hovered = inside } }
        .accessibilityLabel("\(kind.label): \(entry.original)")
    }
}
