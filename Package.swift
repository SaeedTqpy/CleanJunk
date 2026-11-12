// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CleanJunk",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "CleanJunk", targets: ["CleanJunkApp"]),
        .library(name: "CleanJunkCore", targets: ["CleanJunkCore"])
    ],
    targets: [
        .target(
            name: "CleanJunkCore",
            path: "Sources/CleanJunkCore"
        ),
        .executableTarget(
            name: "CleanJunkApp",
            dependencies: ["CleanJunkCore"],
            path: "Sources/CleanJunkApp"
        ),
        .testTarget(
            name: "CleanJunkCoreTests",
            dependencies: ["CleanJunkCore"],
            path: "Tests/CleanJunkCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
