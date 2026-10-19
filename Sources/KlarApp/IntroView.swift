import SwiftUI

/// First launch: the thread draws itself into the S, the name assembles around it,
/// then a short, friendly profile step. Skippable at any moment.
struct IntroView: View {
    @ObservedObject var profile: ProfileStore
    /// Returning visitors see the title sequence only; it hands over on its own.
    var returning = false
    var onFinish: () -> Void
    @State private var stage = 0
    @State private var markProgress: CGFloat = 0
    @State private var lettersWidth: CGFloat = 380
    @State private var name = ""
    @State private var avatar = 0
    @State private var glow = false
    @FocusState private var nameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let letters = Array("innfaden")
    private let titleSize: CGFloat = 92

    var body: some View {
        ZStack {
            FluidBackground(energy: stage >= 5 ? 0.5 : 0.2)
                .opacity(stage >= 1 ? 1 : 0)
                .animation(.easeOut(duration: 1.2), value: stage >= 1)
                .ignoresSafeArea()
            if stage < 5 {
                titleSequence
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.86)).combined(with: .offset(y: -60))))
            } else {
                profileStep
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 40)).combined(with: .scale(scale: 0.96)), removal: .opacity))
            }
            VStack {
                HStack {
                    Spacer()
                    Button("Überspringen") { if returning { handOver() } else { finish(skipped: true) } }
                        .keyboardShortcut(.cancelAction)
                        .focusEffectDisabled()
                        .help("Überspringen · Escape")
                        .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sinnMuted)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .opacity(stage >= 1 && stage < 5 ? 1 : 0)
                }
                Spacer()
            }.padding(24)
        }
        .contentShape(Rectangle())
        .onTapGesture { if returning { handOver() } }
        .task { await play() }
    }

    @State private var handedOver = false
    private func handOver() {
        guard !handedOver else { return }
        handedOver = true
        onFinish()
    }

    // MARK: - Title sequence

    private var titleSequence: some View {
        VStack(spacing: 26) {
            ZStack {
                // A soft halo blooms the moment the thread closes.
                Circle().fill(RadialGradient(colors: [Color.sinnAnnotation.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 220))
                    .frame(width: 440, height: 440)
                    .scaleEffect(glow ? 1.1 : 0.4)
                    .opacity(glow ? (stage >= 3 ? 0.5 : 1) : 0)
                    .animation(reduceMotion ? nil : .spring(response: 1.2, dampingFraction: 0.7), value: glow)
                    .animation(.easeOut(duration: 1.2), value: stage)
                HStack(alignment: .firstTextBaseline, spacing: SinnfadenWordmark.spacing(titleSize)) {
                    SinnfadenWordmark.mark(size: titleSize, progress: markProgress)
                        .scaleEffect(stage >= 2 ? 1 : 1.35, anchor: .bottom)
                        .offset(x: stage >= 2 ? 0 : lettersWidth / 2)
                        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.9, dampingFraction: 0.82), value: stage)
                    HStack(spacing: 0) {
                        ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                            Text(String(letter))
                                .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                                .tracking(-titleSize * 0.035)
                                .foregroundStyle(Color.sinnInk)
                                .opacity(stage >= 2 ? 1 : 0)
                                .offset(y: stage >= 2 || reduceMotion ? 0 : 34)
                                .blur(radius: stage >= 2 || reduceMotion ? 0 : 14)
                                .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.75, dampingFraction: 0.78).delay(0.18 + Double(index) * 0.055), value: stage)
                        }
                    }
                    .background(GeometryReader { geo in Color.clear.onAppear { lettersWidth = geo.size.width } })
                }
            }
            Text("Deine Gedanken. Klar formuliert.")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.sinnMuted)
                .opacity(stage >= 3 ? 1 : 0)
                .offset(y: stage >= 3 || reduceMotion ? 0 : 14)
                .animation(.easeOut(duration: 0.7), value: stage)
            Button { advanceToProfile() } label: {
                HStack(spacing: 10) { Text("Los geht's"); Image(systemName: "arrow.right") }
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
            }
            .buttonStyle(PrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .opacity(stage >= 4 ? 1 : 0)
            .scaleEffect(stage >= 4 || reduceMotion ? 1 : 0.8)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: stage)
            .padding(.top, 18)
            .disabled(stage < 4)
        }
    }

    // MARK: - Profile step

    private var profileStep: some View {
        VStack(spacing: 24) {
            ProfileAvatar(index: avatar, size: 96)
                .shadow(color: Color.black.opacity(0.15), radius: 18, y: 10)
                .id(avatar)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
                .animation(.spring(response: 0.45, dampingFraction: 0.65), value: avatar)
            VStack(spacing: 8) {
                Text(name.trimmingCharacters(in: .whitespaces).isEmpty ? "Schön, dass du da bist." : "Hallo, \(name.trimmingCharacters(in: .whitespaces)).")
                    .font(SinnType.display(40)).tracking(-1.2)
                    .contentTransition(.opacity)
                Text("Wie dürfen wir dich nennen? Dein Profil bleibt nur auf diesem Mac.")
                    .font(.system(size: 16)).foregroundStyle(Color.sinnMuted)
            }
            TextField("Dein Vorname (freiwillig)", text: $name)
                .textFieldStyle(SinnFieldStyle())
                .font(.system(size: 18))
                .frame(width: 420)
                .focused($nameFocused)
                .onSubmit { finish(skipped: false) }
            VStack(spacing: 12) {
                Text("Wähle ein Profilbild").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sinnMuted)
                AvatarPicker(selection: $avatar, size: 50)
            }
            Button { finish(skipped: false) } label: {
                HStack(spacing: 10) { Text("Fertig, los geht's"); Image(systemName: "arrow.right") }
                    .font(.system(size: 16, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4)
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(44)
        .cardSurface(radius: 34, elevated: true)
        .frame(maxWidth: 620)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { nameFocused = true } }
    }

    // MARK: - Timeline

    private func play() async {
        if reduceMotion {
            stage = 1; markProgress = 1; stage = returning ? 3 : 4
            if returning { try? await Task.sleep(for: .milliseconds(900)); handOver() }
            return
        }
        try? await Task.sleep(for: .milliseconds(150))
        stage = 1
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.easeInOut(duration: 1.35)) { markProgress = 1 }
        try? await Task.sleep(for: .milliseconds(1250))
        glow = true
        stage = 2
        try? await Task.sleep(for: .milliseconds(1000))
        stage = 3
        if returning {
            try? await Task.sleep(for: .milliseconds(1100))
            handOver()
            return
        }
        try? await Task.sleep(for: .milliseconds(650))
        stage = 4
        guard AppTour.isRequested else { return }
        // Tour only: play the profile step so it can be recorded without input.
        try? await Task.sleep(for: .milliseconds(1400))
        advanceToProfile()
        for letter in "Alex" {
            try? await Task.sleep(for: .milliseconds(260))
            name.append(letter)
        }
        for pick in [4, 7, 2] {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(SinnMotion.selection) { avatar = pick }
        }
        try? await Task.sleep(for: .milliseconds(1400))
        finish(skipped: false)
    }

    private func advanceToProfile() {
        name = profile.name
        avatar = profile.avatar
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.7, dampingFraction: 0.86)) { stage = 5 }
    }

    private func finish(skipped: Bool) {
        if !skipped {
            profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            profile.avatar = avatar
        }
        profile.onboarded = true
        onFinish()
    }
}
