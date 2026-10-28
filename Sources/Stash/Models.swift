import Foundation
import SwiftData

enum ClipKind: String, Codable, CaseIterable {
    case text, image, file, link, color

    var label: String {
        switch self {
        case .text: "Text"
        case .image: "Image"
        case .file: "File"
        case .link: "Link"
        case .color: "Color"
        }
    }

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .image: "photo"
        case .file: "doc"
        case .link: "link"
        case .color: "paintpalette"
        }
    }
}

@Model
final class ClipItem {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var kindRaw: String = ClipKind.text.rawValue
    var text: String?
    @Attribute(.externalStorage) var rtfData: Data?
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?
    var imageWidth: Int = 0
    var imageHeight: Int = 0
    var filePaths: [String] = []
    var sourceBundleID: String?
    var sourceAppName: String?
    var isPinned: Bool = false
    var inHistory: Bool = true
    var title: String?
    var searchText: String = ""
    var contentHash: String = ""
    var groups: [ClipGroup] = []

    init(kind: ClipKind, contentHash: String) {
        self.kindRaw = kind.rawValue
        self.contentHash = contentHash
    }

    var kind: ClipKind { ClipKind(rawValue: kindRaw) ?? .text }

    var group: ClipGroup? { groups.first }
}

@Model
final class ClipGroup {
    var id: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#0A84FF"
    var createdAt: Date = Date()
    @Relationship(deleteRule: .nullify, inverse: \ClipItem.groups) var items: [ClipItem] = []

    init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
    }
}
