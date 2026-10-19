import SwiftUI
import KlarCore

/// Building blocks shared by the learning pages (Verfeinern, Vergleichen, Vorlagen, Verlauf):
/// page head, small uppercase labels, white "paper" cards, numbered steps and empty states
/// that always name the next step.

struct LearningPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        SinnPageHeader(eyebrow: eyebrow, title: title, subtitle: subtitle)
    }
}
struct LearningNotice: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 13)).lineSpacing(4).foregroundStyle(Color.sinnMuted).frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Color.sinnStructure,in:RoundedRectangle(cornerRadius:15)).textSelection(.enabled) }
}
struct HandoffButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var service: ChatGPTHandoff
    let prompt: String
    var beforeOpen: () -> Void = {}
    /// Fills the available width (the main action of a sheet).
    var expanded = false
    var body: some View {
        Button { beforeOpen(); service.open(prompt: prompt) } label: {
            HStack(spacing: 10) { ChatGPTMark(size: 20).environment(\.colorScheme, colorScheme == .dark ? .light : .dark); Text(service.actionTitle(for: prompt)).font(.system(size: 14, weight: .semibold)).lineLimit(1); Image(systemName:"arrow.up.right").font(.system(size:11,weight:.bold)) }
                .fixedSize(horizontal: !expanded, vertical: false)
                .frame(maxWidth: expanded ? .infinity : nil)
        }.buttonStyle(PrimaryButtonStyle()).disabled(prompt.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || service.isOpening)
    }
}

struct HandoffStatus: View {
    @ObservedObject var service: ChatGPTHandoff
    let prompt: String
    var body: some View { let message = service.statusMessage(for: prompt); if !message.isEmpty { LearningNotice(text: message) } }
}

/// Small uppercase heading, the same voice as the settings cards.
struct SectionEyebrow: View {
    let text: String
    var tint: Color = .sinnMuted
    var body: some View { Text(text.uppercased()).font(SinnType.eyebrow).tracking(1.3).foregroundStyle(tint) }
}

/// A numbered step heading: the number turns into a check once the step is done.
struct StepHeading: View {
    let number: Int
    let title: String
    var done = false
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(done ? Color.sinnAnnotation : Color.sinnInk)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                } else {
                    Text("\(number)").font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            SectionEyebrow(text: title, tint: .sinnInk)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Schritt \(number): \(title)\(done ? ", erledigt" : "")")
    }
}

/// A small status capsule (Bereit, Läuft, Fertig …).
struct StatusPill: View {
    let text: String
    let symbol: String
    var tint: Color = .sinnMuted
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(tint.opacity(0.1), in: Capsule())
            .fixedSize()
    }
}

extension View {
    /// Plain white card with a hairline, for supporting content next to the dominant glass card.
    func paperCard(radius: CGFloat = 20, padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.black.opacity(0.05)))
            .shadow(color: Color.black.opacity(0.03), radius: 6, y: 2)
    }
}

/// Empty states teach the next step instead of showing a blank area.
struct EmptyStateCard: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(Color.sinnAnnotation)
                .frame(width: 48, height: 48).background(Color.sinnAnnotationWash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(SinnType.title(22))
                Text(text).font(.system(size: 14)).foregroundStyle(Color.sinnMuted).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(26).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }
}

/// A larger empty state: what this page is for, how you get here in three steps, and one button.
struct GuidedEmptyState: View {
    let symbol: String
    let title: String
    let text: String
    let steps: [String]
    let actionTitle: String
    let actionSymbol: String
    let action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 20) {
                Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(Color.sinnAnnotation)
                    .frame(width: 60, height: 60)
                    .background(Color.sinnAnnotationWash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 8) {
                    SectionEyebrow(text: "Noch leer", tint: .sinnAnnotation)
                    Text(title).font(SinnType.title(28)).tracking(-0.4)
                    Text(text).font(.system(size: 15)).foregroundStyle(Color.sinnMuted).lineSpacing(4)
                        .frame(maxWidth: 560, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 24, weight: .regular, design: .serif)).foregroundStyle(Color.sinnAnnotation)
                        Text(step).font(.system(size: 13, weight: .medium)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.05)))
                }
            }
            Button(action: action) { Label(actionTitle, systemImage: actionSymbol) }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 28, elevated: true)
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
