import AppKit
import Observation
import Security

struct UpdateError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

@Observable
@MainActor
final class Updater {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let downloadURL: URL
        let pageURL: URL
    }

    enum State: Equatable {
        case idle, checking, upToDate, available(Release), downloading, installing, failed(String)
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }

        let tag_name: String
        let html_url: URL
        let assets: [Asset]
    }

    private(set) var state: State = .idle
    private var timer: Timer?
    private let latestReleaseURL = URL(string: "https://api.github.com/repos/rpopovych-maker/stash/releases/latest")!

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var availableRelease: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            Task { await Updater.shared.checkAutomatically() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { _ in
            Task { await Updater.shared.checkAutomatically() }
        }
    }

    private func checkAutomatically() async {
        guard AppSettings.shared.autoCheckUpdates, availableRelease == nil else { return }
        await check()
    }

    func check() async {
        guard !isBusy else { return }
        state = .checking
        do {
            var request = URLRequest(url: latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw UpdateError("Couldn't reach GitHub. Try again later.")
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let version = String(release.tag_name.trimmingPrefix("v"))
            guard Self.isVersion(version, newerThan: currentVersion) else {
                state = .upToDate
                return
            }
            guard let asset = release.assets.first(where: { $0.name == "Stash.zip" }) else {
                throw UpdateError("The latest release has no download yet. Try again in a few minutes.")
            }
            state = .available(Release(version: version, downloadURL: asset.browser_download_url, pageURL: release.html_url))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func install() async {
        guard let release = availableRelease else { return }
        let appURL = Bundle.main.bundleURL
        let parent = appURL.deletingLastPathComponent()
        guard !appURL.path.contains("/AppTranslocation/"), FileManager.default.isWritableFile(atPath: parent.path) else {
            state = .failed("Move Stash to your Applications folder to install updates.")
            return
        }

        state = .downloading
        do {
            let (downloaded, _) = try await URLSession.shared.download(from: release.downloadURL)
            let workDir = FileManager.default.temporaryDirectory.appending(path: "StashUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            let zip = workDir.appending(path: "Stash.zip")
            try FileManager.default.moveItem(at: downloaded, to: zip)

            state = .installing
            try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, workDir.path])
            let newApp = workDir.appending(path: "Stash.app")
            try verify(newApp, expectedVersion: release.version)
            try? await Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
            try relaunch(replacing: appURL, with: newApp, backup: workDir.appending(path: "Stash-previous.app"))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func verify(_ app: URL, expectedVersion: String) throws {
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion
        else {
            throw UpdateError("The downloaded update isn't a valid copy of Stash.")
        }

        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw UpdateError("The downloaded update isn't signed.")
        }
        let requirement = Self.isSignedWithCertificate ? Self.currentDesignatedRequirement : nil
        guard SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess else {
            throw UpdateError("The downloaded update isn't signed by the Stash developer, so it wasn't installed.")
        }
    }

    private func relaunch(replacing appURL: URL, with newApp: URL, backup: URL) throws {
        let script = """
        while kill -0 "$4" 2>/dev/null; do sleep 0.2; done
        if mv "$1" "$3"; then
            if mv "$2" "$1"; then rm -rf "$3"; else mv "$3" "$1"; fi
        fi
        open "$1"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", appURL.path, newApp.path, backup.path, String(ProcessInfo.processInfo.processIdentifier)]
        try process.run()
        NSApp.terminate(nil)
    }

    private static var selfStaticCode: SecStaticCode? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess else { return nil }
        return staticCode
    }

    private static var currentDesignatedRequirement: SecRequirement? {
        guard let staticCode = selfStaticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }

    private static var isSignedWithCertificate: Bool {
        guard let staticCode = selfStaticCode else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let certificates = dict[kSecCodeInfoCertificates as String] as? [SecCertificate]
        else { return false }
        return !certificates.isEmpty
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError("Couldn't unpack the update."))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
