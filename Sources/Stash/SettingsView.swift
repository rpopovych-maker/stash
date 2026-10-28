import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "Stash Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var trusted = Paster.isTrusted
    @State private var recording = false
    @State private var recorder: Any?
    @State private var confirmClear = false
    private var updater = Updater.shared

    private let maxItemOptions = [500, 1000, 5000, 10000, 0]
    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section {
                Toggle("Paste directly into the active app", isOn: $settings.pasteDirectly)
                if settings.pasteDirectly {
                    LabeledContent("Accessibility") {
                        if trusted {
                            Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Grant Access…") { Paster.openAccessibilitySettings() }
                        }
                    }
                }
            } header: {
                Text("Pasting")
            } footer: {
                Text("When on, choosing an item pastes it where you were typing. When off, it is only copied to the clipboard. ⇧↩ pastes as plain text.")
            }

            Section {
                LabeledContent("Open Stash") {
                    Button(recording ? "Press shortcut…" : settings.hotKey.display) {
                        recording ? stopRecording() : startRecording()
                    }
                    .buttonStyle(.glass)
                    .tint(recording ? .accentColor : nil)
                }
                ForEach(panelShortcuts, id: \.action) { shortcut in
                    LabeledContent(shortcut.action) {
                        HStack(spacing: 4) {
                            ForEach(shortcut.keys, id: \.self) { Keycap(label: $0) }
                        }
                    }
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Click the Open Stash shortcut to change it. The other shortcuts work while the panel is open. Start typing to search.")
            }

            Section {
                Picker("Keep history for", selection: $settings.retention) {
                    ForEach(Retention.allCases) { Text($0.label).tag($0) }
                }
                Picker("Maximum items", selection: $settings.maxItems) {
                    ForEach(maxItemOptions, id: \.self) { Text($0 == 0 ? "Unlimited" : $0.formatted()).tag($0) }
                }
                LabeledContent("History") {
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("Pinned items never expire. They stay in their group after leaving history.")
            }

            Section {
                Toggle("Pause capturing", isOn: $settings.isPaused)
                Toggle("Ignore passwords and sensitive data", isOn: $settings.ignoreConcealed)
                LabeledContent("Ignored apps") {
                    Button("Add App…", action: addIgnoredApp)
                }
                ForEach(settings.ignoredBundleIDs, id: \.self) { bundleID in
                    HStack {
                        if let icon = AppIconCache.icon(for: bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                        }
                        Text(appName(for: bundleID))
                        Spacer()
                        Button {
                            settings.ignoredBundleIDs.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Items marked as concealed by password managers like 1Password and Keychain are never saved.")
            }

            Section {
                Toggle("Automatically check for updates", isOn: $settings.autoCheckUpdates)
                LabeledContent("Stash \(updater.currentVersion)") {
                    updateControl
                }
                if case .failed(let message) = updater.state {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Stash checks GitHub once a day. Nothing else is sent anywhere.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 680)
        .onReceive(refresh) { _ in trusted = Paster.isTrusted }
        .onChange(of: settings.retention) { ClipStore.shared.prune() }
        .onChange(of: settings.maxItems) { ClipStore.shared.prune() }
        .onDisappear(perform: stopRecording)
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { ClipStore.shared.clearHistory() }
        } message: {
            Text("Pinned items stay in their groups.")
        }
    }

    private var panelShortcuts: [(action: String, keys: [String])] {
        [
            ("Select previous / next item", ["←", "→"]),
            ("Paste selected item", ["↩"]),
            ("Paste as plain text", ["⇧", "↩"]),
            ("Paste item 1–9", ["⌘", "1–9"]),
            ("Copy without pasting", ["⌘", "C"]),
            ("Pin / unpin", ["⌘", "P"]),
            ("Rename item", ["⌘", "R"]),
            ("Delete from History or unpin", ["⌘", "⌫"]),
            ("Next / previous tab", ["tab", "⇧ tab"]),
            ("Clear search or close", ["esc"]),
            ("Open Settings", ["⌘", ","]),
        ]
    }

    @ViewBuilder
    private var updateControl: some View {
        switch updater.state {
        case .checking:
            ProgressView().controlSize(.small)
        case .downloading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading…").foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing…").foregroundStyle(.secondary)
            }
        case .available(let release):
            HStack(spacing: 8) {
                Link("What's New", destination: release.pageURL)
                Button("Update to \(release.version)") { Task { await updater.install() } }
                    .buttonStyle(.glassProminent)
            }
        case .upToDate:
            HStack(spacing: 8) {
                Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Button("Check Now") { Task { await updater.check() } }
            }
        case .idle, .failed:
            Button("Check Now") { Task { await updater.check() } }
        }
    }

    private func startRecording() {
        recording = true
        HotKey.shared.unregister()
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53, flags.isEmpty {
                stopRecording()
                return nil
            }
            guard !flags.isEmpty else { return nil }
            settings.hotKey = HotKeyCombo(
                keyCode: UInt32(event.keyCode),
                carbonModifiers: HotKey.carbonModifiers(from: flags),
                display: HotKey.display(for: event)
            )
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let recorder { NSEvent.removeMonitor(recorder) }
        recorder = nil
        recording = false
        HotKey.shared.register(settings.hotKey)
    }

    private func addIgnoredApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !settings.ignoredBundleIDs.contains(id) else { continue }
            settings.ignoredBundleIDs.append(id)
        }
    }

    private func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
    }
}
