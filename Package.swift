// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "KLAR",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KlarCore", targets: ["KlarCore"]),
        .executable(name: "KLAR", targets: ["KlarApp"]),
        .executable(name: "KlarProbe", targets: ["KlarProbe"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "KlarCore", resources: [.process("Resources")], linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "KlarApp", dependencies: ["KlarCore", .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "KlarProbe", dependencies: ["KlarCore"]),
        .testTarget(name: "KlarCoreTests", dependencies: ["KlarCore"]),
        .testTarget(name: "KlarAppTests", dependencies: ["KlarApp", "KlarCore"])
    ],
    swiftLanguageVersions: [.v5]
)
