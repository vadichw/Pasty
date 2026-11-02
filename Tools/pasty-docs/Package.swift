// swift-tools-version:6.0
import PackageDescription

// Dev tool only: extracts facts from Sources/PastyCore and checks them against the module
// READMEs. Kept in its own package so the app itself has no external dependencies.
let package = Package(
    name: "pasty-docs",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "pasty-docs",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
    ]
)
