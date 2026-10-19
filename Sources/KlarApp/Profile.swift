import SwiftUI

/// Local profile: a display name and one of the bundled vector avatars. Stored only on this Mac.
@MainActor
final class ProfileStore: ObservableObject {
    private static let key = "sinnfadenProfile"
    @Published var name: String { didSet { save() } }
    @Published var avatar: Int { didSet { save() } }
    @Published var onboarded: Bool { didSet { save() } }
    /// The opening sequence plays on every launch; this session has seen it once it is true.
    @Published var introPlayed: Bool

    init() {
        let stored = UserDefaults.standard.dictionary(forKey: Self.key) ?? [:]
        name = stored["name"] as? String ?? ""
        avatar = stored["avatar"] as? Int ?? 0
        let arguments = CommandLine.arguments
        let scripted = arguments.contains("--ui-tour") || arguments.contains("--click-probe") || arguments.contains("--compose-probe") || arguments.contains("--show-page")
        onboarded = (stored["onboarded"] as? Bool ?? false || scripted) && !arguments.contains("--intro")
        introPlayed = scripted && !arguments.contains("--intro") && !arguments.contains("--welcome")
    }

    var greetingName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        UserDefaults.standard.set(["name": name, "avatar": avatar, "onboarded": onboarded], forKey: Self.key)
    }
}
