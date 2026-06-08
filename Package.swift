// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuickOCR",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "QuickOCR",
            path: "Sources",
            resources: [.copy("complete.wav")]
        )
    ]
)
