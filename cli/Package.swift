// swift-tools-version: 5.9
import PackageDescription

// Set to true to enable Iroh P2P support (requires built xcframework)
let enableIroh = true

let package = Package(
    name: "xplorer",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(name: "xplorer", targets: ["xplorer"]),
        .library(name: "XplorerLib", targets: ["XplorerLib"]),
    ],
    dependencies: enableIroh ? [
        // Iroh P2P networking - using local path for development
        // TODO: Switch to remote URL once iroh-ffi has a proper release with xcframework
        .package(name: "IrohLib", path: "../../iroh-ffi/IrohLib"),
    ] : [],
    targets: [
        .target(
            name: "XplorerLib",
            path: "Sources/XplorerLib"
        ),
        .executableTarget(
            name: "xplorer",
            dependencies: enableIroh ? [
                "XplorerLib",
                .product(name: "IrohLib", package: "IrohLib"),
            ] : ["XplorerLib"],
            path: "Sources/xplorer",
            swiftSettings: enableIroh ? [
                .define("IROH_ENABLED"),
            ] : [],
            linkerSettings: enableIroh ? [
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("Security"),
            ] : []
        ),
        .testTarget(
            name: "XplorerTests",
            dependencies: ["XplorerLib"],
            path: "Tests/XplorerTests"
        ),
    ]
)
