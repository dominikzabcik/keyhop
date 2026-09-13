// swift-tools-version:5.10
import PackageDescription

// `Keyhop` builds everywhere: on macOS it's the menu bar app, which also answers the `keyhop`
// commands; on Linux and Windows it's the `keyhop` command that the tray apps drive.
// `KeyhopTray` is the Windows tray app; on other systems it only prints where to find the tray.
// There are no package dependencies, so distribution builds can run offline. SQLite comes from
// the system on macOS and from the bundled amalgamation elsewhere, so Linux builds link statically.
let package = Package(
    name: "Keyhop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Keyhop", targets: ["Keyhop"]),
        .executable(name: "KeyhopTray", targets: ["KeyhopTray"]),
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
            name: "Keyhop",
            dependencies: [.target(name: "CSQLite", condition: .when(platforms: [.linux, .windows]))],
            path: "Sources/Keyhop"
        ),
        .executableTarget(
            name: "KeyhopTray",
            path: "Sources/KeyhopTray",
            linkerSettings: [
                // A window app, so starting it at sign-in doesn't open a console.
                .unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"], .when(platforms: [.windows])),
            ]
        ),
        .testTarget(
            name: "KeyhopTests",
            dependencies: ["Keyhop"],
            path: "Tests/KeyhopTests"
        ),
    ]
)
