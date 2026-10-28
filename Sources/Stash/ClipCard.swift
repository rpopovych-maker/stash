import AppKit
import SwiftUI

@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]
    private static var colors: [String: Color] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }

    static func color(for bundleID: String?) -> Color {
        guard let bundleID else { return .gray }
        if let cached = colors[bundleID] { return cached }
        let color = icon(for: bundleID).flatMap(averageColor) ?? .gray
        colors[bundleID] = color
        return color
    }

    private static func averageColor(of image: NSImage) -> Color? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 8, height: 8))
        NSGraphicsContext.restoreGraphicsState()

        var r = 0.0, g = 0.0, b = 0.0, weight = 0.0
        for x in 0..<8 {
            for y in 0..<8 {
                guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
                let saturation = c.saturationComponent
                let w = 0.2 + saturation
                r += c.redComponent * w
                g += c.greenComponent * w
                b += c.blueComponent * w
                weight += w
            }
        }
        guard weight > 0 else { return nil }
        let base = NSColor(srgbRed: r / weight, green: g / weight, blue: b / weight, alpha: 1)
        let tuned = NSColor(
            hue: base.hueComponent,
            saturation: min(1, base.saturationComponent * 1.15),
            brightness: min(0.78, max(0.42, base.brightnessComponent)),
            alpha: 1
        )
        return Color(nsColor: tuned)
    }
}

struct ClipCard: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let now: Date

    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .layoutPriority(-1)
            footer
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 236, height: 248)
        .background(shape.fill(.background.opacity(0.72)))
        .clipShape(shape)
        .overlay(shape.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 3 : 1))
        .shadow(color: .black.opacity(isSelected ? 0.25 : 0.12), radius: isSelected ? 10 : 5, y: 3)
        .scaleEffect(isSelected ? 1.0 : 0.97)
        .animation(.snappy(duration: 0.18), value: isSelected)
        .contentShape(shape)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.kind.label)
                    .font(.system(size: 13, weight: .semibold))
                Text(relativeTime)
                    .font(.system(size: 11))
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
            if let group = item.group {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Circle().fill(Color(hex: group.colorHex)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                    .help("Pinned to \(group.name)")
            }
            if let icon = AppIconCache.icon(for: item.sourceBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .help(item.sourceAppName ?? "")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(AppIconCache.color(for: item.sourceBundleID).gradient)
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text:
            Text(String((item.text ?? "").prefix(800)))
                .font(.system(size: 12))
                .lineLimit(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        case .link:
            let url = URL(string: item.text ?? "")
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tint)
                Text(url?.host() ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(item.text ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(12)
        case .color:
            ZStack {
                Color(hex: item.text ?? "#000")
                Text(item.text ?? "")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
            }
        case .image:
            if let data = item.thumbnailData, let image = NSImage(data: data) {
                Color.clear
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipped()
            } else {
                Image(systemName: "photo").font(.largeTitle).foregroundStyle(.secondary)
            }
        case .file:
            VStack(spacing: 8) {
                if let path = item.filePaths.first {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                        .resizable()
                        .frame(width: 72, height: 72)
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        HStack {
            Text(info)
                .lineLimit(1)
            Spacer()
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
    }

    private var relativeTime: String {
        let seconds = now.timeIntervalSince(item.createdAt)
        if seconds < 60 { return "Just now" }
        return item.createdAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    private var info: String {
        switch item.kind {
        case .text:
            let count = item.text?.count ?? 0
            return "\(count.formatted()) character\(count == 1 ? "" : "s")"
        case .image:
            return "\(item.imageWidth) × \(item.imageHeight)"
        case .file:
            let n = item.filePaths.count
            return n == 1 ? "1 file" : "\(n) files"
        case .link:
            return item.sourceAppName ?? "Link"
        case .color:
            return item.sourceAppName ?? "Color"
        }
    }
}
