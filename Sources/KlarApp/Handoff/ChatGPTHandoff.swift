import AppKit
import Combine
import Security
import KlarCore

@MainActor
final class ChatGPTHandoff: ObservableObject {
    @Published private(set) var statusMessage = ""
    @Published private(set) var isOpening = false
    @Published private(set) var desktopDiagnosis = ""
    private var verifiedTarget: URL?
    private var operation = UUID()
    private var lastPrompt: String?
    func statusMessage(for prompt: String) -> String { lastPrompt == prompt ? statusMessage : "" }

    /// Empty until composer prefill and the everyday Chat surface are observed on
    /// the exact installed version. Metadata or a scheme handler alone is insufficient.
    private static let verifiedDesktopVersions: Set<String> = []

    init() { refreshCompatibility() }
    var actionTitle: String { verifiedTarget == nil ? "Kopieren & ChatGPT öffnen" : "In ChatGPT öffnen" }
    func actionTitle(for prompt: String) -> String {
        if case .preparedDesktop = ChatGPTHandoffPlan.make(prompt: prompt, verifiedDesktopAvailable: verifiedTarget != nil) { return "In ChatGPT öffnen" }
        return "Kopieren & ChatGPT öffnen"
    }

    func refreshCompatibility() {
        verifiedTarget = nil
        guard let target = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex"), let bundle = Bundle(url: target) else {
            desktopDiagnosis = "Die Desktop-Übergabe ist nicht bestätigt. ChatGPT wird im Browser geöffnet."; return
        }
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let schemes = (bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []).flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        guard name == "ChatGPT", schemes.contains("codex"), Self.isOfficialApplication(target) else {
            desktopDiagnosis = "Für den registrierten Link-Empfänger ist die passende ChatGPT-Oberfläche nicht bestätigt. ChatGPT wird im Browser geöffnet."; return
        }
        guard Self.verifiedDesktopVersions.contains(version) else {
            desktopDiagnosis = "ChatGPT \(version) ist installiert. Die Vorbefüllung der passenden Chat-Oberfläche ist für diese Version nicht überprüft. Der Prompt wird deshalb kopiert und ChatGPT im Browser geöffnet."; return
        }
        verifiedTarget = target
        desktopDiagnosis = "Desktop-Übergabe für ChatGPT \(version) überprüft. Der Prompt wird vorbereitet und nicht gesendet."
    }

    func open(prompt: String) {
        guard !isOpening else { return }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { statusMessage = "Es gibt noch keinen Prompt zum Öffnen."; return }
        lastPrompt = prompt
        let id = UUID(); operation = id; isOpening = true; statusMessage = "ChatGPT wird geöffnet …"
        let plan = ChatGPTHandoffPlan.make(prompt: prompt, verifiedDesktopAvailable: verifiedTarget != nil)
        switch plan {
        case .preparedDesktop(let link):
            guard let target = verifiedTarget else { copyAndOpenBrowser(prompt: prompt, operation: id); return }
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([link], withApplicationAt: target, configuration: config) { [weak self] application, error in
                Task { @MainActor in
                    guard let self, self.operation == id else { return }
                    if error == nil, application?.bundleIdentifier == "com.openai.codex" {
                        self.isOpening = false
                        self.statusMessage = "In ChatGPT geöffnet. Bitte prüfe den vorbereiteten Prompt und sende ihn dort selbst."
                    } else { self.copyAndOpenBrowser(prompt: prompt, operation: id) }
                }
            }
        case .clipboardBrowser:
            copyAndOpenBrowser(prompt: prompt, operation: id)
        }
    }

    private func copyAndOpenBrowser(prompt: String, operation id: UUID) {
        // Only called from the explicit button action above. Always copy the original
        // complete string: no truncation, normalization, annotation or status text.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(prompt, forType: .string) else {
            isOpening = false; statusMessage = "Der Prompt konnte nicht kopiert werden. Bitte markiere ihn und kopiere ihn mit ⌘C."; return
        }
        let destination = ChatGPTHandoffPlan.browserDestination
        guard let browser = Self.browserApplication(excluding: "com.openai.codex") else {
            isOpening = false; statusMessage = "Prompt kopiert. Öffne chatgpt.com in deinem Browser und füge ihn mit ⌘V ein."; return
        }
        NSWorkspace.shared.open([destination], withApplicationAt: browser, configuration: NSWorkspace.OpenConfiguration()) { [weak self] application, error in
            Task { @MainActor in
                guard let self, self.operation == id else { return }
                self.isOpening = false
                self.statusMessage = error == nil && application != nil
                    ? "Prompt kopiert. In ChatGPT mit ⌘V einfügen."
                    : "Prompt kopiert. ChatGPT konnte nicht geöffnet werden. Öffne chatgpt.com in deinem Browser und füge den Prompt mit ⌘V ein."
            }
        }
    }

    private static func browserApplication(excluding excludedID: String) -> URL? {
        // Open the web destination in an actual browser even if ChatGPT registers
        // itself as a handler for this specific HTTPS domain.
        let genericWebURL = URL(string: "https://example.com/")!
        if let candidate = NSWorkspace.shared.urlForApplication(toOpen: genericWebURL), Bundle(url: candidate)?.bundleIdentifier != excludedID { return candidate }
        for bundleID in ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "org.mozilla.firefox"] {
            if let candidate = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return candidate }
        }
        return nil
    }

    private static func isOfficialApplication(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        let expression = "anchor apple generic and identifier \"com.openai.codex\" and certificate leaf[subject.OU] = \"2DC432GLL2\""
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess, let requirement else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
