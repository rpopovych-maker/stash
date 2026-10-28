// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Stash",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Stash",
            path: "Sources/Stash", 
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ] 
)

