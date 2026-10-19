import SwiftUI
import KlarCore

/// App shell: flowing milky background, profile and wordmark top left, connection
/// top right, one page at a time, and the Sinnfaden dial at the bottom centre.
struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var profile: ProfileStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var deleteConfirmation = false
    @State private var showProfile = false
    @State private var showDockHint = false
    @State private var shellVisible = false

    var body: some View {
        ZStack {
            FluidBackground(energy: model.busy ? 1 : model.dockOpen ? 0.6 : 0.2).ignoresSafeArea()
            if profile.onboarded && profile.introPlayed {
                shell.transition(.opacity)
            } else {
                IntroView(profile: profile, returning: profile.onboarded) {
                    profile.introPlayed = true
                    presentShell()
                }
                .transition(.opacity.combined(with: .scale(scale: 1.06)))
            }
        }
        .animation(.easeInOut(duration: 0.7), value: profile.onboarded && profile.introPlayed)
        .foregroundStyle(Color.sinnInk)
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model, connection: model.connection) }
        .alert("Verlauf dieses Kontos löschen?", isPresented: $deleteConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Verlauf löschen", role: .destructive) { model.deleteHistory() }
        } message: { Text("Entwurf, gespeicherte Vorschläge und Übungsversuche dieses Kontos werden lokal entfernt.") }
        .onAppear { if profile.onboarded && profile.introPlayed { presentShell(immediate: true) } }
        // Whatever takes over the window closes the dial, so it never lingers half-open.
        .onChange(of: model.page) { _, _ in model.dockOpen = false }
        .onChange(of: model.showSettings) { _, shown in if shown { model.dockOpen = false; showProfile = false } }
        .onChange(of: showProfile) { _, shown in if shown { model.dockOpen = false } }
        .onChange(of: model.dockOpen) { _, isOpen in if isOpen { showProfile = false } }
    }

    private func presentShell(immediate: Bool = false) {
        if immediate || reduceMotion { shellVisible = true } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { shellVisible = true }
        }
        if !UserDefaults.standard.bool(forKey: "sinnfadenDockHintShown") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { showDockHint = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { showDockHint = false }
            UserDefaults.standard.set(true, forKey: "sinnfadenDockHintShown")
        }
    }

    // MARK: - Shell

    private var shell: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 1120
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    topBar
                        .opacity(shellVisible ? 1 : 0)
                        .offset(y: shellVisible || reduceMotion ? 0 : -24)
                        .animation(.spring(response: 0.7, dampingFraction: 0.85), value: shellVisible)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            pageContent(wide: wide)
                        }
                        .id(model.page)
                        .transition(pageTransition)
                        .frame(maxWidth: contentWidth(wide: wide))
                        .padding(.horizontal, geometry.size.width < 900 ? 24 : 40)
                        .padding(.top, 12).padding(.bottom, 150)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geometry.size.height - 80, alignment: model.page == .coach && model.response == nil ? .center : .top)
                    }
                    .scrollIndicators(.never)
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : SinnMotion.page, value: model.page)
                    .opacity(shellVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.1), value: shellVisible)
                }
                // The page goes soft behind the milk wave; only the dial stays in focus.
                .blur(radius: model.dockOpen && !reduceMotion ? 9 : 0)
                .scaleEffect(model.dockOpen && !reduceMotion ? 0.985 : 1)
                .animation(.easeOut(duration: model.dockOpen ? 0.6 : 0.35), value: model.dockOpen)
                NavigationDock(open: $model.dockOpen, current: model.page, items: dockItems, showHint: showDockHint)
                    .opacity(shellVisible ? 1 : 0)
                    .offset(y: shellVisible || reduceMotion ? 0 : 80)
                    .animation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.25), value: shellVisible)
                if showProfile {
                    // Click anywhere else (or Escape) to put the card away.
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { withAnimation(profileMotion) { showProfile = false } }
                        .background { Button("") { withAnimation(profileMotion) { showProfile = false } }.keyboardShortcut(.cancelAction).opacity(0) }
                    profilePopover
                        .padding(.leading, 70).padding(.top, 66)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.12, anchor: .topLeading).combined(with: .opacity))
                        .zIndex(2)
                }
            }
        }
    }

    /// Pages without native text get a cinematic zoom-and-focus; pages that host the
    /// AppKit prompt text use opacity and offset only (AppKit text cannot be blurred or scaled).
    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let hostsNativeText = model.page == .coach || model.page == .followUp
        let insertion: AnyTransition = hostsNativeText
            ? .opacity.combined(with: .offset(y: 24))
            : .opacity.combined(with: .scale(scale: 0.94)).combined(with: .modifier(active: FocusBlur(radius: 14), identity: FocusBlur(radius: 0)))
        return .asymmetric(insertion: insertion.animation(SinnMotion.page.delay(0.08)),
                           removal: .opacity.animation(.easeOut(duration: 0.12)))
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { withAnimation(profileMotion) { showProfile.toggle() } } label: {
                ProfileAvatar(index: profile.avatar, size: 38)
                    .shadow(color: Color.black.opacity(0.14), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .help("Dein Profil")
            .accessibilityLabel("Profil von \(profile.greetingName.isEmpty ? "dir" : profile.greetingName)")
            SinnfadenWordmark(size: 22)
            Spacer()
            Label(pageTitle, systemImage: pageSymbol)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sinnMuted)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.25), value: model.page)
            Spacer()
            Button { model.showSettings = true } label: {
                HStack(spacing: 7) {
                    Circle().fill(model.connection.canGenerate ? Color.green : model.isDemo ? Color.sinnAnnotation : Color.orange).frame(width: 7, height: 7)
                    Text(connectionLabel).font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.9)))
            }
            .buttonStyle(.plain).help("Verbindung und Konto verwalten")
        }
        .padding(.leading, 86).padding(.trailing, 24)
        .frame(height: 64)
    }

    private var profileMotion: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.8) }

    private var profilePopover: some View {
        ProfilePopover(profile: profile) { withAnimation(profileMotion) { showProfile = false }; model.showSettings = true }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.9)))
            .shadow(color: Color(red: 0.1, green: 0.2, blue: 0.45).opacity(0.18), radius: 30, y: 16)
            .shadow(color: Color.black.opacity(0.06), radius: 3, y: 1)
    }

    private var dockItems: [DockItem] {
        [
            DockItem(id: "coach", title: "Prompt", symbol: "square.and.pencil", page: .coach) { model.page = .coach },
            DockItem(id: "followUp", title: "Verfeinern", symbol: "arrow.turn.down.right", page: .followUp) { model.page = .followUp },
            DockItem(id: "lessons", title: "Lernen", symbol: "graduationcap", page: .lessons) { model.page = .lessons },
            DockItem(id: "laboratory", title: "Vergleichen", symbol: "rectangle.split.2x1", page: .laboratory) { model.page = .laboratory },
            DockItem(id: "recipes", title: "Vorlagen", symbol: "square.stack", page: .recipes) { model.page = .recipes },
            DockItem(id: "history", title: "Verlauf", symbol: "clock.arrow.circlepath", page: .history) { model.page = .history },
            DockItem(id: "new", title: "Neu", symbol: "plus", page: nil) { model.newPrompt() },
            DockItem(id: "settings", title: "Einstellungen", symbol: "slider.horizontal.3", page: nil) { model.showSettings = true }
        ]
    }

    private func contentWidth(wide: Bool) -> CGFloat {
        switch model.page {
        case .coach: return model.response == nil ? 820 : (wide ? 1180 : 820)
        case .followUp: return 820
        case .lessons, .recipes, .history, .laboratory: return wide ? 1040 : 820
        }
    }

    private var pageTitle: String {
        switch model.page {
        case .coach: return "Prompt verbessern"
        case .followUp: return "Antwort verfeinern"
        case .lessons: return "Kurz lernen"
        case .laboratory: return "Antworten vergleichen"
        case .recipes: return "Meine Vorlagen"
        case .history: return "Verlauf"
        }
    }

    private var pageSymbol: String {
        switch model.page {
        case .coach: return "square.and.pencil"
        case .followUp: return "arrow.turn.down.right"
        case .lessons: return "graduationcap"
        case .laboratory: return "rectangle.split.2x1"
        case .recipes: return "square.stack"
        case .history: return "clock.arrow.circlepath"
        }
    }

    private var connectionLabel: String {
        if model.isDemo { return "Beispiel · ohne KI" }
        guard model.connection.canGenerate else { return "ChatGPT verbinden" }
        return model.connection.providerKind == .apiKey ? "OpenAI API verbunden" : "ChatGPT verbunden"
    }

    @ViewBuilder private func pageContent(wide: Bool) -> some View {
        switch model.page {
        case .coach: CoachView(model: model, greetingName: profile.greetingName, wide: wide)
        case .history: HistoryView(model: model) { deleteConfirmation = true }
        case .laboratory: ComparisonView(model: model.learning, fontSize: model.fontSize) { model.page = .coach }
        case .lessons: LessonsView(model: model.learning, fontSize: model.fontSize)
        case .recipes: RecipesView(model: model.learning, handoff: model.handoff, fontSize: model.fontSize)
        case .followUp: FollowUpView(model: model.learning, handoff: model.handoff, fontSize: model.fontSize, onCompare: { original, response, change in
            model.learning.prepareComparison(original: original, response: response, change: change); model.page = .laboratory
        }, onRecipe: { prompt in model.learning.createRecipe(from: prompt); model.page = .recipes })
        }
    }
}

/// Blur used only as a page-entry focus pull on pure SwiftUI pages.
private struct FocusBlur: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

/// The profile card: your companion large and alive on its own colour, your name, the
/// other companions to choose from, and the way to settings.
private struct ProfilePopover: View {
    @ObservedObject var profile: ProfileStore
    let openSettings: () -> Void
    @State private var settingsHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("WIE DARF ICH DICH NENNEN?").font(SinnType.eyebrow).tracking(1.4).foregroundStyle(Color.sinnMuted)
                    TextField("Vorname", text: $profile.name).textFieldStyle(SinnFieldStyle())
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text("DEIN BEGLEITER").font(SinnType.eyebrow).tracking(1.4).foregroundStyle(Color.sinnMuted)
                    AvatarPicker(selection: $profile.avatar, size: 36)
                }
                Button(action: openSettings) {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(Color.sinnStructure, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text("Einstellungen & Verbindung").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.sinnMuted)
                            .offset(x: settingsHovered && !reduceMotion ? 2 : 0)
                    }
                    .padding(8)
                    .background(Color.sinnStructure.opacity(settingsHovered ? 0.8 : 0), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in withAnimation(SinnMotion.hover) { settingsHovered = inside } }
            }
            .padding(18)
        }
        .frame(width: 344)
    }

    private var header: some View {
        let colors = ProfileAvatar.backdrop(profile.avatar)
        return VStack(spacing: 10) {
                ProfileAvatar(index: profile.avatar, size: 92, live: true)
                    .shadow(color: ProfileAvatar.tone(profile.avatar).opacity(0.4), radius: 16, y: 8)
                    .id(profile.avatar)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                VStack(spacing: 2) {
                    Text(profile.greetingName.isEmpty ? "Dein Profil" : profile.greetingName)
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.sinnInk)
                    Label("Nur auf diesem Mac", systemImage: "lock.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.sinnInk.opacity(0.55))
                }
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color.white.opacity(0.7), .clear], center: .top, startRadius: 0, endRadius: 180)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.72), value: profile.avatar)
    }
}
