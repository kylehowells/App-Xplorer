// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "AppXplorerServer",
	platforms: [
		.iOS(.v15),
		.macOS(.v12),
	],
	products: [
		// Core library - HTTP transport only
		.library(
			name: "AppXplorerServer",
			targets: ["AppXplorerServer"]),
		// Optional: Iroh transport for P2P connections
		.library(
			name: "AppXplorerIroh",
			targets: ["AppXplorerIroh"]),
		// Test executable for Iroh transport
		.executable(
			name: "IrohTestServer",
			targets: ["IrohTestServer"]),
	],
	dependencies: [
		// Using Swifter - a lightweight HTTP server that works on iOS
		.package(url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.5.0")),
		// Iroh P2P networking (optional) - using local path for development
		// TODO: Switch to remote URL once iroh-ffi has a proper release with updated xcframework
		.package(name: "IrohLib", path: "../../iroh-ffi/IrohLib"),
	],
	targets: [
		// Core target - HTTP transport
		.target(
			name: "AppXplorerServer",
			dependencies: [
				.product(name: "Swifter", package: "swifter"),
			]),
		// Optional Iroh transport target
		.target(
			name: "AppXplorerIroh",
			dependencies: [
				"AppXplorerServer",
				.product(name: "IrohLib", package: "IrohLib"),
			],
			path: "Sources/AppXplorerIroh"),
		// Test executable for Iroh transport
		.executableTarget(
			name: "IrohTestServer",
			dependencies: [
				"AppXplorerServer",
				"AppXplorerIroh",
			],
			path: "Sources/IrohTestServer",
			linkerSettings: [
				.linkedFramework("SystemConfiguration"),
				.linkedFramework("Security"),
			]),
		.testTarget(
			name: "AppXplorerServerTests",
			dependencies: ["AppXplorerServer"]
		),
	]
)
