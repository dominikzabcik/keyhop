// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Switchr",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Switchr",
            path: "Sources/Switchr"
        ),
    ]
)
