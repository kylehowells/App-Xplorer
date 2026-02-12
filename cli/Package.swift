// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "xplorer",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(name: "xplorer", targets: ["xplorer"]),
        .library(name: "XplorerLib", targets: ["XplorerLib"]),
    ],
    targets: [
        .target(
            name: "XplorerLib",
            path: "Sources/XplorerLib"
        ),
        .executableTarget(
            name: "xplorer",
            dependencies: ["XplorerLib"],
            path: "Sources/xplorer"
        ),
        .testTarget(
            name: "XplorerTests",
            dependencies: ["XplorerLib"],
            path: "Tests/XplorerTests"
        ),
    ]
)
