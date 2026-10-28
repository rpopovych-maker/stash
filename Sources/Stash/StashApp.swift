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
            if let release = Updater.shared.availableRelease {
                Button("Update to Stash \(release.version)…") { Task { await Updater.shared.install() } }
            }
            Button("Check for Updates…") {
                SettingsWindowController.shared.show()
                Task { await Updater.shared.check() }
            }
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
            Updater.shared.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { InstallerCleanup.run() }
            pruneTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
                MainActor.assumeIsolated { ClipStore.shared.prune() }
            }
        }
    }
}
