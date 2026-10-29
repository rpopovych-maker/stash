import AppKit
import CryptoKit
import Observation
import SwiftData
import Vision

@Observable
@MainActor
final class ClipStore {
    static let shared = ClipStore()

    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    private(set) var items: [ClipItem] = []
    private(set) var groups: [ClipGroup] = []

    private init() {
        let dir = URL.applicationSupportDirectory.appending(path: "Stash", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = ModelConfiguration(url: dir.appending(path: "Stash.store"))
        do {
            container = try ModelContainer(for: ClipItem.self, ClipGroup.self, configurations: config)
        } catch {
            fatalError("Failed to open store: \(error)")
        }
        migratePins()
        reload()
    }

    private func migratePins() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didMigrateToPinboards") else { return }
        defaults.set(true, forKey: "didMigrateToPinboards")
        let allItems = (try? context.fetch(FetchDescriptor<ClipItem>())) ?? []
        let allGroups = (try? context.fetch(FetchDescriptor<ClipGroup>())) ?? []
        let pinned = allItems.filter(\.isPinned)
        if allGroups.isEmpty || !pinned.isEmpty {
            let board = ClipGroup(name: "Pinned", colorHex: "#FF9F0A")
            board.createdAt = (allGroups.map(\.createdAt).min() ?? Date()).addingTimeInterval(-1)
            context.insert(board)
            for item in pinned {
                item.groups = [board]
                item.isPinned = false
            }
        }
        for item in allItems where item.groups.count > 1 {
            item.groups = [item.groups[0]]
        }
        try? context.save()
    }

    func reload() {
        let itemFetch = FetchDescriptor<ClipItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let groupFetch = FetchDescriptor<ClipGroup>(sortBy: [SortDescriptor(\.createdAt)])
        items = (try? context.fetch(itemFetch)) ?? []
        groups = (try? context.fetch(groupFetch)) ?? []
    }

    private func save() {
        try? context.save()
        reload()
    }

    static func hash(_ parts: [Data]) -> String {
        var hasher = SHA256()
        for part in parts { hasher.update(data: part) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func insert(_ capture: Capture) {
        if let existing = items.first(where: { $0.contentHash == capture.hash }) {
            existing.createdAt = Date()
            existing.inHistory = true
            existing.sourceBundleID = capture.sourceBundleID ?? existing.sourceBundleID
            existing.sourceAppName = capture.sourceAppName ?? existing.sourceAppName
            save()
            return
        }

        let item = ClipItem(kind: capture.kind, contentHash: capture.hash)
        item.text = capture.text
        item.rtfData = capture.rtfData
        item.imageData = capture.imageData
        item.filePaths = capture.filePaths
        item.sourceBundleID = capture.sourceBundleID
        item.sourceAppName = capture.sourceAppName

        if let data = capture.imageData, let image = NSImage(data: data) {
            let rep = image.representations.first
            item.imageWidth = rep?.pixelsWide ?? Int(image.size.width)
            item.imageHeight = rep?.pixelsHigh ?? Int(image.size.height)
            item.thumbnailData = Self.thumbnail(of: image, maxSide: 480)
        }

        item.searchText = [
            capture.text,
            capture.filePaths.map { ($0 as NSString).lastPathComponent }.joined(separator: " "),
            capture.sourceAppName,
        ].compactMap { $0 }.joined(separator: " ")

        context.insert(item)
        enforceLimits()
        save()

        if item.kind == .image, let data = item.imageData {
            recognizeText(in: data, for: item.id)
        }
    }

    func rename(_ item: ClipItem, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.title = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func touch(_ item: ClipItem) {
        item.createdAt = Date()
        save()
    }

    var historyItems: [ClipItem] { items.filter(\.inHistory) }

    func pin(_ item: ClipItem, to group: ClipGroup) {
        item.groups = [group]
        UserDefaults.standard.set(group.id.uuidString, forKey: "lastPinboardID")
        save()
    }

    func togglePin(_ item: ClipItem) {
        if item.group != nil {
            unpin(item)
            return
        }
        let lastID = UserDefaults.standard.string(forKey: "lastPinboardID").flatMap(UUID.init)
        let board = groups.first { $0.id == lastID } ?? groups.first ?? createGroup(name: "Pinned", colorHex: "#FF9F0A")
        pin(item, to: board)
    }

    func unpin(_ item: ClipItem) {
        item.groups = []
        if !item.inHistory { context.delete(item) }
        save()
    }

    func deleteFromHistory(_ item: ClipItem) {
        if item.group == nil {
            context.delete(item)
        } else {
            item.inHistory = false
        }
        save()
    }

    func clearHistory() {
        for item in items where item.inHistory {
            if item.group == nil { context.delete(item) } else { item.inHistory = false }
        }
        save()
    }

    func createGroup(name: String, colorHex: String) -> ClipGroup {
        let group = ClipGroup(name: name, colorHex: colorHex)
        context.insert(group)
        save()
        return group
    }

    func rename(_ group: ClipGroup, to name: String) {
        group.name = name
        save()
    }

    func setColor(_ group: ClipGroup, to hex: String) {
        group.colorHex = hex
        save()
    }

    func delete(_ group: ClipGroup) {
        for item in group.items { context.delete(item) }
        context.delete(group)
        save()
    }

    func prune() {
        enforceLimits()
        save()
    }

    private func enforceLimits() {
        let settings = AppSettings.shared
        let all = FetchDescriptor<ClipItem>(
            predicate: #Predicate { $0.inHistory },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let history = (try? context.fetch(all)) ?? []
        let cutoff = settings.retention.cutoff
        for (index, item) in history.enumerated() {
            let expired = cutoff.map { item.createdAt < $0 } ?? false
            let overLimit = settings.maxItems > 0 && index >= settings.maxItems
            guard expired || overLimit else { continue }
            if item.group == nil { context.delete(item) } else { item.inHistory = false }
        }
    }

    private static func thumbnail(of image: NSImage, maxSide: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    private func recognizeText(in data: Data, for id: UUID) {
        Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(data: data)
            try? handler.perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            guard !text.isEmpty else { return }
            await MainActor.run {
                guard let item = ClipStore.shared.items.first(where: { $0.id == id }) else { return }
                item.searchText += " " + text
                try? ClipStore.shared.context.save()
            }
        }
    }
}
