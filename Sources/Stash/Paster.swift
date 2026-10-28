import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

@MainActor
enum Paster {
    static let log = Logger(subsystem: "com.rpopovych.stash", category: "paste")
    static var isTrusted: Bool { AXIsProcessTrusted() }
    private static var didPrompt = false

    static func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        requestAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func copy(_ item: ClipItem, plainText: Bool = false) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            if !plainText, let rtf = item.rtfData { pb.setData(rtf, forType: .rtf) }
            pb.setString(item.text ?? "", forType: .string)
        case .link, .color:
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            if let data = item.imageData {
                pb.setData(data, forType: .png)
                if let tiff = NSImage(data: data)?.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
            }
        case .file:
            if plainText {
                pb.setString(item.filePaths.joined(separator: "\n"), forType: .string)
            } else {
                pb.writeObjects(item.filePaths.map { URL(fileURLWithPath: $0) as NSURL })
            }
        }
        ClipboardMonitor.shared.ignoreCurrentChange()
    }

    static func paste(_ item: ClipItem, plainText: Bool = false) {
        copy(item, plainText: plainText)
        log.debug("paste kind=\(item.kind.rawValue, privacy: .public) pasteDirectly=\(AppSettings.shared.pasteDirectly, privacy: .public) trusted=\(isTrusted, privacy: .public) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil", privacy: .public)")
        let shouldSend = AppSettings.shared.pasteDirectly && isTrusted
        if AppSettings.shared.pasteDirectly, !isTrusted, !didPrompt {
            didPrompt = true
            requestAccess()
        }
        PanelController.shared.hide {
            if shouldSend {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { sendCommandV() }
            }
            ClipStore.shared.touch(item)
        }
    }

    private static func sendCommandV() {
        log.debug("sending cmd-V to \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil", privacy: .public)")
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
