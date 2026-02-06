// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "AppXplorerServer",
	platforms: [
		.iOS(.v15),
		.macOS(.v12),
	],
	products: [
		// Products define the executables and libraries a package produces, making them visible to other packages.
		.library(
			name: "AppXplorerServer",
			targets: ["AppXplorerServer"]),
	],
	dependencies: [
		// Using Swifter - a lightweight HTTP server that works on iOS
		.package(url: "https://github.com/httpswift/swifter.git", .upToNextMajor(from: "1.5.0")),
	],
	targets: [
		// Targets are the basic building blocks of a package, defining a module or a test suite.
		// Targets can depend on other targets in this package and products from dependencies.
		.target(
			name: "AppXplorerServer",
			dependencies: [
				.product(name: "Swifter", package: "swifter"),
			]),
		.testTarget(
			name: "AppXplorerServerTests",
			dependencies: ["AppXplorerServer"]
		),
	]
)
