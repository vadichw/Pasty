// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Pasty",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pasty",
            path: "Sources/Pasty"
        )
    ],
    swiftLanguageModes: [.v5]
)
