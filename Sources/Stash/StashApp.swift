import AppKit
import ServiceManagement
import SwiftUI

@main
struct StashApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Bindable private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra("Stash", systemImage: settings.isPaused ? "clipboard.fill" : "list.clipboard") {
            Button("Open Stash  \(settings.hotKey.display)") { PanelController.shared.show() }
            Divider()
            Toggle("Pause Capturing", isOn: $settings.isPaused)
            Button("Settings…") { SettingsWindowController.shared.show() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit Stash") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pruneTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.accessory)
            Paster.log.debug("launch trusted=\(Paster.isTrusted, privacy: .public) path=\(Bundle.main.bundlePath, privacy: .public)")
            if !UserDefaults.standard.bool(forKey: "didSetUpLoginItem") {
                UserDefaults.standard.set(true, forKey: "didSetUpLoginItem")
                try? SMAppService.mainApp.register()
            }
            _ = ClipStore.shared
            ClipStore.shared.prune()
            PanelController.shared.setUp()
            ClipboardMonitor.shared.start()
            HotKey.shared.action = { PanelController.shared.toggle() }
            HotKey.shared.register(AppSettings.shared.hotKey)
            pruneTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
                MainActor.assumeIsolated { ClipStore.shared.prune() }
            }
        }
    }
}
