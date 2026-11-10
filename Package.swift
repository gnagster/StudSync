// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StudSync",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "StudSync", targets: ["StudSyncApp"])],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.14.3"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.1")
    ],
    targets: [
        .target(name: "StudSyncCore", dependencies: ["SwiftSoup"]),
        .executableTarget(name: "StudSyncApp", dependencies: ["StudSyncCore", .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "StudSyncCoreTests", dependencies: ["StudSyncCore"], path: "tests/StudSyncCoreTests"),
        .testTarget(name: "StudSyncAppTests", dependencies: ["StudSyncApp", "StudSyncCore"], path: "tests/StudSyncAppTests")
    ]
)
