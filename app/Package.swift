// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Coach",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Coach",
            resources: [.copy("Resources/content.json")]
        )
    ]
)
