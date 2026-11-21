// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "MarkdownEditor",
            targets: ["MarkdownEditor"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MarkdownEditor",
            dependencies: [],
            path: "Sources",
            sources: ["App", "Shared"]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: ["MarkdownEditor"],
            path: "Tests/AppTests"
        )
    ]
)
