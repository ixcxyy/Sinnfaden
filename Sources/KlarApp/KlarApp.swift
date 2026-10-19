import SwiftUI
import AppKit
import KlarCore

@main
struct KlarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    @StateObject private var profile = ProfileStore()

    var body: some Scene {
        WindowGroup("Sinnfaden") {
            if AnnotationBubbleLab.isRequested {
                AnnotationBubbleLab()
                    .preferredColorScheme(.light)
            } else {
                ContentView(model: model, profile: profile)
                    .frame(minWidth: 900, minHeight: 680)
                    .onAppear {
                        delegate.beforeTermination = { model.cancel(); model.learning.cancelAll(); model.learning.flushPendingSave() }
                        AppTour.start(model)
                    }
                    .tint(Color.klarBlue)
                    .preferredColorScheme(.light)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 860)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen …") { model.updates.checkForUpdates() }
            }
            CommandGroup(replacing: .newItem) {
                Button("Neuer Prompt") { model.newPrompt() }.keyboardShortcut("n")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Einstellungen …") { model.showSettings = true }.keyboardShortcut(",")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var beforeTermination: (() -> Void)?
    func applicationWillTerminate(_ notification: Notification) { beforeTermination?() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
