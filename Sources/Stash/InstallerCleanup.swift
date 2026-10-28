import AppKit

@MainActor
enum InstallerCleanup {
    static func run() {
        let appPath = Bundle.main.bundlePath
        guard !appPath.hasPrefix("/Volumes/"), !appPath.contains("/AppTranslocation/") else { return }

        for image in mountedImages() {
            guard let mountPoint = image.mountPoint,
                  Bundle(path: mountPoint + "/Stash.app")?.bundleIdentifier == Bundle.main.bundleIdentifier
            else { continue }
            let mountURL = URL(fileURLWithPath: mountPoint)
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: mountURL)
            } catch {
                continue
            }
            if let imagePath = image.imagePath, FileManager.default.fileExists(atPath: imagePath) {
                NSWorkspace.shared.recycle([URL(fileURLWithPath: imagePath)])
            }
        }
    }

    private struct MountedImage {
        let imagePath: String?
        let mountPoint: String?
    }

    private static func mountedImages() -> [MountedImage] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["info", "-plist"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]]
        else { return [] }

        return images.map { image in
            let entities = image["system-entities"] as? [[String: Any]] ?? []
            let mountPoint = entities.compactMap { $0["mount-point"] as? String }.first
            return MountedImage(imagePath: image["image-path"] as? String, mountPoint: mountPoint)
        }
    }
}
