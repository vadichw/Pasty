// swift-tools-version:6.0
import PackageDescription

/// Module READMEs live next to the code they describe (see docs/DOC_FORMAT.md).
let modules = ["App", "Capture", "Input", "Output", "Popup", "Settings", "Storage", "Support"]

let package = Package(
    name: "Pasty",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PastyCore",
            path: "Sources/PastyCore",
            exclude: modules.map { "\($0)/README.md" }
        ),
        .executableTarget(
            name: "Pasty",
            dependencies: ["PastyCore"],
            path: "Sources/Pasty"
        ),
        .testTarget(
            name: "PastyCoreTests",
            dependencies: ["PastyCore"],
            path: "Tests/PastyCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
