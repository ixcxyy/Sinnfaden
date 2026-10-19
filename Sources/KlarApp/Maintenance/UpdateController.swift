import Foundation
import Combine
import AppKit
import Sparkle
import KlarCore

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var canCheck = false
    @Published private(set) var message = "Updates sind für diesen Entwicklungsbuild noch nicht eingerichtet."
    @Published var automaticallyChecks = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }
    var configured: Bool { controller != nil }
    private var controller: SPUStandardUpdaterController?
    private var subscription: AnyCancellable?

    init(isDemo: Bool) {
        guard !isDemo, Bundle.main.bundleURL.pathExtension == "app",
              MaintenanceConfiguration.validFeed(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String) != nil,
              MaintenanceConfiguration.validPublicKey(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) else { return }
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        controller = updater
        automaticallyChecks = updater.updater.automaticallyChecksForUpdates
        subscription = updater.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).sink { [weak self] in self?.canCheck = $0 }
        do {
            try updater.updater.start()
            message = "Neue Versionen werden angezeigt. Herunterladen und Installieren bestätigst du selbst."
        } catch {
            controller = nil
            message = "Die Update-Suche konnte nicht gestartet werden. Bitte installiere einen vollständig eingerichteten Build."
        }
    }

    func checkForUpdates() {
        guard let controller else {
            let alert = NSAlert(); alert.messageText = "Updates noch nicht eingerichtet"; alert.informativeText = message
            alert.addButton(withTitle: "OK"); alert.runModal(); return
        }
        controller.checkForUpdates(nil)
    }
}
