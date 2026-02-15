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
	],
	dependencies: [
		// Using Swifter - a lightweight HTTP server that works on iOS
		.package(url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.5.0")),
	],
	targets: [
		// Core target - HTTP transport
		.target(
			name: "AppXplorerServer",
			dependencies: [
				.product(name: "Swifter", package: "swifter"),
			]),
		// Test server executable (macOS only)
		.executableTarget(
			name: "TestServer",
			dependencies: ["AppXplorerServer"]),
		.testTarget(
			name: "AppXplorerServerTests",
			dependencies: ["AppXplorerServer"]
		),
	]
)
