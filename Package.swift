// swift-tools-version:5.10
import PackageDescription

// `Switchr` builds everywhere: on macOS it's the menu bar app, which also answers the `switchr`
// commands; on Linux and Windows it's the `switchr` command that the tray apps drive.
// `SwitchrTray` is the Windows tray app; on other systems it only prints where to find the tray.
// There are no package dependencies, so distribution builds can run offline. SQLite comes from
// the system on macOS and from the bundled amalgamation elsewhere, so Linux builds link statically.
let package = Package(
    name: "Switchr",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Switchr", targets: ["Switchr"]),
        .executable(name: "SwitchrTray", targets: ["SwitchrTray"]),
    ],
    targets: [
        .target(
            name: "CSQLite",
            path: "Sources/CSQLite",
            cSettings: [
                .define("SQLITE_THREADSAFE", to: "1"),
                .define("SQLITE_DQS", to: "0"),
                .define("SQLITE_DEFAULT_MEMSTATUS", to: "0"),
                .define("SQLITE_OMIT_LOAD_EXTENSION"),
                .define("SQLITE_OMIT_DEPRECATED"),
                .define("SQLITE_OMIT_SHARED_CACHE"),
                .define("SQLITE_USE_ALLOCA"),
            ]
        ),
        .executableTarget(
            name: "Switchr",
            dependencies: [.target(name: "CSQLite", condition: .when(platforms: [.linux, .windows]))],
            path: "Sources/Switchr"
        ),
        .executableTarget(
            name: "SwitchrTray",
            path: "Sources/SwitchrTray",
            linkerSettings: [
                // A window app, so starting it at sign-in doesn't open a console.
                .unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"], .when(platforms: [.windows])),
            ]
        ),
        .testTarget(
            name: "SwitchrTests",
            dependencies: ["Switchr"],
            path: "Tests/SwitchrTests"
        ),
    ]
)
