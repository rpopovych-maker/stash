import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

enum GroupEditTarget: Hashable {
    case new, rename(UUID)
}

enum PanelTab: Hashable {
    case history, group(UUID)
}

@Observable
@MainActor
final class PanelModel {
    var query = ""
    var tab: PanelTab = .history { didSet { selectedIndex = 0 } }
    var selectedIndex = 0
    var editTarget: GroupEditTarget?
    var pendingItemID: UUID?
    var isEditing: Bool { editTarget != nil }
    var openCount = 0
    var resetCount = 0

    var currentGroup: ClipGroup? {
        guard case .group(let id) = tab else { return nil }
        return ClipStore.shared.groups.first { $0.id == id }
    }

    var visibleItems: [ClipItem] {
        let store = ClipStore.shared
        var base: [ClipItem]
        switch tab {
        case .history:
            base = store.historyItems
        case .group:
            base = (currentGroup?.items ?? []).sorted { $0.createdAt > $1.createdAt }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            base = base.filter { $0.searchText.localizedStandardContains(q) || $0.kind.label.localizedStandardContains(q) }
        }
        return base
    }

    var selectedItem: ClipItem? {
        let items = visibleItems
        return items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    var tabs: [PanelTab] {
        [.history] + ClipStore.shared.groups.map { .group($0.id) }
    }

    func moveSelection(_ delta: Int) {
        let count = visibleItems.count
        guard count > 0 else { return }
        selectedIndex = max(0, min(count - 1, selectedIndex + delta))
    }

    func cycleTab(_ delta: Int) {
        let all = tabs
        guard let i = all.firstIndex(of: tab) else { tab = .history; return }
        tab = all[(i + delta + all.count) % all.count]
    }
}

final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let shared = PanelController()

    let model = PanelModel()
    private var panel: GlassPanel!
    private var keyMonitor: Any?
    private(set) var isVisible = false

    private let height: CGFloat = 330
    private let margin: CGFloat = 10

    func setUp() {
        panel = GlassPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: height),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.delegate = self

        let glass = NSGlassEffectView()
        glass.cornerRadius = 30
        glass.contentView = NSHostingView(rootView: PanelView(model: model))
        panel.contentView = glass
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard !isVisible else { return }
        isVisible = true
        model.openCount += 1

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let visible = screen.visibleFrame
        let target = NSRect(x: visible.minX + margin, y: visible.minY + margin, width: visible.width - margin * 2, height: height)
        var start = target
        start.origin.y -= 40

        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
        installKeyMonitor()
    }

    func hide(completion: (() -> Void)? = nil) {
        guard isVisible else { return }
        isVisible = false
        removeKeyMonitor()
        var end = panel.frame
        end.origin.y -= 40
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                guard !self.isVisible else { return }
                self.panel.orderOut(nil)
                self.resetModel()
                completion?()
            }
        })
    }

    private func resetModel() {
        model.query = ""
        model.selectedIndex = 0
        model.editTarget = nil
        model.pendingItemID = nil
        model.resetCount += 1
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !model.isEditing else { return }
        hide()
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { PanelController.shared.handle(event) ? nil : event }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === panel, !model.isEditing else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let store = ClipStore.shared

        switch Int(event.keyCode) {
        case kVK_Escape:
            if model.query.isEmpty { hide() } else { model.query = "" }
            return true
        case kVK_LeftArrow:
            model.moveSelection(-1); return true
        case kVK_RightArrow:
            model.moveSelection(1); return true
        case kVK_Tab:
            model.cycleTab(flags.contains(.shift) ? -1 : 1); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = model.selectedItem { Paster.paste(item, plainText: flags.contains(.shift)) }
            return true
        default:
            break
        }

        guard flags.contains(.command) else { return false }

        if let chars = event.charactersIgnoringModifiers, let n = Int(chars), (1...9).contains(n) {
            let items = model.visibleItems
            if items.indices.contains(n - 1) { Paster.paste(items[n - 1], plainText: flags.contains(.shift)) }
            return true
        }

        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            if !model.query.isEmpty {
                model.query = ""
            } else if let item = model.selectedItem {
                model.currentGroup == nil ? store.deleteFromHistory(item) : store.unpin(item)
                model.moveSelection(0)
            }
            return true
        case kVK_ANSI_P:
            if let item = model.selectedItem { store.togglePin(item) }
            return true
        case kVK_ANSI_C:
            if let item = model.selectedItem, model.query.isEmpty || !(panel.firstResponder is NSText) {
                Paster.copy(item)
                hide()
                return true
            }
            return false
        case kVK_ANSI_Comma:
            hide()
            SettingsWindowController.shared.show()
            return true
        default:
            return false
        }
    }
}
