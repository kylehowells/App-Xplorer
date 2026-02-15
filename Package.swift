// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "AppXplorer",
	platforms: [
		.iOS(.v15),
		.macOS(.v12),
	],
	products: [
		// Core library - HTTP transport only (lightweight, no external dependencies except Swifter)
		.library(
			name: "AppXplorerServer",
			targets: ["AppXplorerServer"]),
		// Optional: Iroh P2P transport (adds ~34MB to binary size)
		.library(
			name: "AppXplorerIroh",
			targets: ["AppXplorerIroh"]),
	],
	dependencies: [
		// Swifter - lightweight HTTP server that works on iOS
		.package(url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.5.0")),
		// Iroh P2P networking (only resolved if AppXplorerIroh is used)
		.package(url: "https://github.com/kylehowells/iroh-ffi", from: "0.96.0"),
	],
	targets: [
		// Core server with HTTP transport
		.target(
			name: "AppXplorerServer",
			dependencies: [
				.product(name: "Swifter", package: "swifter"),
			],
			path: "server/Sources/AppXplorerServer"),
		// Iroh P2P transport adapter
		.target(
			name: "AppXplorerIroh",
			dependencies: [
				"AppXplorerServer",
				.product(name: "IrohLib", package: "iroh-ffi"),
			],
			path: "iroh-transport/Sources/AppXplorerIroh"),
		// Tests
		.testTarget(
			name: "AppXplorerServerTests",
			dependencies: ["AppXplorerServer"],
			path: "server/Tests/AppXplorerServerTests"),
	]
)
