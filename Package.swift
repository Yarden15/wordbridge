// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Wordbridge",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Wordbridge",
            path: "Sources/Wordbridge",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
