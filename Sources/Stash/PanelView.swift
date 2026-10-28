import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let stashItem = UTType(exportedAs: "com.rpopovych.stash.item")
}

struct ClipItemRef: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .stashItem)
    }
}

let groupPalette = ["#0A84FF", "#30D158", "#FF9F0A", "#FF375F", "#BF5AF2", "#64D2FF", "#FFD60A", "#AC8E68"]

struct PanelView: View {
    @Bindable var model: PanelModel
    @FocusState private var searchFocused: Bool

    private var store: ClipStore { ClipStore.shared }

    var body: some View {
        let items = model.visibleItems
        VStack(spacing: 14) {
            topBar
            if items.isEmpty {
                emptyState
            } else {
                cards(items)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.openCount, initial: true) {
            searchFocused = true
        }
        .onChange(of: model.query) {
            model.selectedIndex = 0
        }
        .onChange(of: model.tab) {
            searchFocused = true
        }
    }

    private var topBar: some View {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $model.query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(width: 240, height: 32)
                .glassEffect(.regular, in: .capsule)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        TabChip(title: "History", symbol: "clock", color: nil, isSelected: model.tab == .history) {
                            model.tab = .history
                        }
                        ForEach(store.groups) { group in
                            TabChip(title: group.name, symbol: nil, color: Color(hex: group.colorHex), isSelected: model.tab == .group(group.id)) {
                                model.tab = .group(group.id)
                            } onDrop: { ids in
                                for item in items(for: ids) { store.pin(item, to: group) }
                            }
                            .contextMenu {
                                Button("Rename…") { model.editTarget = .rename(group.id) }
                                Button("Delete Group and Its Items", role: .destructive) {
                                    if model.tab == .group(group.id) { model.tab = .history }
                                    store.delete(group)
                                }
                            }
                            .popover(isPresented: editBinding(.rename(group.id)), arrowEdge: .bottom) {
                                GroupEditor(initialName: group.name, initialColor: group.colorHex, title: "Rename Group") { name, color in
                                    store.rename(group, to: name)
                                    group.colorHex = color
                                    model.editTarget = nil
                                } onCancel: { model.editTarget = nil }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()

                Button { model.editTarget = .new } label: {
                    Image(systemName: "plus").frame(width: 18, height: 18)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .focusable(false)
                .help("New Group")
                .popover(isPresented: editBinding(.new), arrowEdge: .bottom) {
                    GroupEditor(initialName: "", initialColor: groupPalette[store.groups.count % groupPalette.count], title: "New Group") { name, color in
                        let group = store.createGroup(name: name, colorHex: color)
                        if let id = model.pendingItemID, let item = store.items.first(where: { $0.id == id }) {
                            store.pin(item, to: group)
                        }
                        model.pendingItemID = nil
                        model.editTarget = nil
                        model.tab = .group(group.id)
                    } onCancel: {
                        model.pendingItemID = nil
                        model.editTarget = nil
                    }
                }

                Button {
                    PanelController.shared.hide()
                    SettingsWindowController.shared.show()
                } label: {
                    Image(systemName: "gearshape").frame(width: 18, height: 18)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .focusable(false)
                .help("Settings (⌘,)")
            }
    }

    private func items(for ids: [UUID]) -> [ClipItem] {
        store.items.filter { ids.contains($0.id) }
    }

    private func renameBinding(_ item: ClipItem) -> Binding<Bool> {
        Binding(
            get: { model.renamingItemID == item.id },
            set: { if !$0, model.renamingItemID == item.id { model.renamingItemID = nil } }
        )
    }

    private func editBinding(_ target: GroupEditTarget) -> Binding<Bool> {
        Binding(
            get: { model.editTarget == target },
            set: { if !$0, model.editTarget == target { model.editTarget = nil } }
        )
    }

    private func cards(_ items: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipCard(item: item, index: index, isSelected: index == model.selectedIndex, now: Date())
                            .id(item.id)
                            .onTapGesture { Paster.paste(item) }
                            .draggable(ClipItemRef(id: item.id)) {
                                ClipCard(item: item, index: 99, isSelected: false, now: Date())
                                    .scaleEffect(0.6)
                                    .frame(width: 150, height: 160)
                            }
                            .contextMenu { menu(for: item) }
                            .popover(isPresented: renameBinding(item), arrowEdge: .top) {
                                RenameEditor(initialTitle: item.title ?? "") { title in
                                    store.rename(item, to: title)
                                    model.renamingItemID = nil
                                } onCancel: { model.renamingItemID = nil }
                            }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
            .onChange(of: model.selectedIndex) {
                guard items.indices.contains(model.selectedIndex) else { return }
                withAnimation(.snappy) { proxy.scrollTo(items[model.selectedIndex].id, anchor: .center) }
            }
            .onChange(of: model.resetCount) {
                if let first = items.first { proxy.scrollTo(first.id, anchor: .leading) }
            }
        }
    }

    @ViewBuilder
    private func menu(for item: ClipItem) -> some View {
        Button("Paste") { Paster.paste(item) }
        Button("Paste as Plain Text") { Paster.paste(item, plainText: true) }
        Button("Copy") { Paster.copy(item); PanelController.shared.hide() }
        Button("Rename…") { model.renamingItemID = item.id }
        Divider()
        Menu(item.group == nil ? "Pin to" : "Move to") {
            ForEach(store.groups) { group in
                Button(group.name) { store.pin(item, to: group) }
                    .disabled(item.group?.id == group.id)
            }
            if !store.groups.isEmpty { Divider() }
            Button("New Group…") {
                model.pendingItemID = item.id
                model.editTarget = .new
            }
        }
        if let group = item.group {
            Button("Unpin from \(group.name)") { store.unpin(item) }
        }
        if item.kind == .link, let text = item.text, let url = URL(string: text) {
            Button("Open Link") { NSWorkspace.shared.open(url); PanelController.shared.hide() }
        }
        if item.kind == .file, let path = item.filePaths.first {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                PanelController.shared.hide()
            }
        }
        Divider()
        if model.currentGroup == nil {
            Button("Delete from History", role: .destructive) { store.deleteFromHistory(item) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if !model.query.isEmpty { return "No matches for “\(model.query)”" }
        switch model.tab {
        case .history: return "Copy something to get started"
        case .group: return "Drag items here, or right-click and choose Pin to"
        }
    }
}

struct TabChip: View {
    let title: String
    let symbol: String?
    let color: Color?
    let isSelected: Bool
    let action: () -> Void
    var onDrop: (([UUID]) -> Void)? = nil

    @State private var isTargeted = false

    var body: some View {
        let chip = Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                } else if let color {
                    Circle().fill(isSelected ? .white : color).frame(width: 8, height: 8)
                }
                Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(isTargeted ? (color ?? .accentColor) : .clear, lineWidth: 2))
            .contentShape(Capsule())
            .scaleEffect(isTargeted ? 1.08 : 1)
            .animation(.snappy(duration: 0.15), value: isTargeted)
        }
        .buttonStyle(.plain)
        .focusable(false)

        if let onDrop {
            chip.dropDestination(for: ClipItemRef.self) { refs, _ in
                onDrop(refs.map(\.id))
                return true
            } isTargeted: { isTargeted = $0 }
        } else {
            chip
        }
    }

    private var fill: Color {
        if isSelected { return (color ?? .accentColor).opacity(0.9) }
        if isTargeted { return (color ?? .accentColor).opacity(0.3) }
        return Color.primary.opacity(0.09)
    }
}

struct RenameEditor: View {
    @State var title: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    init(initialTitle: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _title = State(initialValue: initialTitle)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Item").font(.headline)
            TextField("Name", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { onSave(title) }
            HStack {
                Text("Leave empty to remove the name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(title) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { focused = true }
    }
}

struct GroupEditor: View {
    @State var name: String
    @State var color: String
    let title: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    init(initialName: String, initialColor: String, title: String, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        _name = State(initialValue: initialName)
        _color = State(initialValue: initialColor)
        self.title = title
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
            HStack(spacing: 8) {
                ForEach(groupPalette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: color == hex ? 2 : 0))
                        .onTapGesture { color = hex }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear { focused = true }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, color)
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let hasAlpha = s.count == 8
        let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
