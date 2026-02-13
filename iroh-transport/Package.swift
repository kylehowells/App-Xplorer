// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "AppXplorerIroh",
	platforms: [
		.iOS(.v15),
		.macOS(.v12),
	],
	products: [
		// Iroh P2P transport adapter for AppXplorerServer
		.library(
			name: "AppXplorerIroh",
			targets: ["AppXplorerIroh"]),
	],
	dependencies: [
		// Core AppXplorerServer library
		.package(path: "../server"),
		// Iroh P2P networking
		// TODO: Switch to remote URL once iroh-ffi has a proper release with updated xcframework
		.package(name: "IrohLib", path: "../../iroh-ffi/IrohLib"),
	],
	targets: [
		// Iroh transport adapter
		.target(
			name: "AppXplorerIroh",
			dependencies: [
				.product(name: "AppXplorerServer", package: "server"),
				.product(name: "IrohLib", package: "IrohLib"),
			]),
		// Test executable for Iroh transport
		.executableTarget(
			name: "IrohTestServer",
			dependencies: [
				.product(name: "AppXplorerServer", package: "server"),
				"AppXplorerIroh",
			],
			linkerSettings: [
				.linkedFramework("SystemConfiguration"),
				.linkedFramework("Security"),
			]),
	]
)
