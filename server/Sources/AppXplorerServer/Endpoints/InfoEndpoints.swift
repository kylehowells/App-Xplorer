import Foundation
#if canImport(UIKit)
	import UIKit
#endif

// MARK: - InfoEndpoints

/// App and device information endpoints
public enum InfoEndpoints {
	/// Register info endpoints with the request handler
	public static func register(with handler: RequestHandler) {
		self.registerInfo(with: handler)
		self.registerScreenshot(with: handler)
		self.registerHierarchy(with: handler)
	}

	// MARK: - Info

	private static func registerInfo(with handler: RequestHandler) {
		handler.register(
			"/info",
			description: "Get app, device, and screen information"
		) { _ in
			#if canImport(UIKit)
				let device: UIDevice = .current
				let bundle: Bundle = .main
				let screen: UIScreen = .main

				let info: [String: Any] = [
					"app": [
						"name": bundle.object(forInfoDictionaryKey: "CFBundleName") ?? "Unknown",
						"version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "Unknown",
						"build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "Unknown",
						"bundleId": bundle.bundleIdentifier ?? "Unknown",
					],
					"device": [
						"name": device.name,
						"model": device.model,
						"systemVersion": device.systemVersion,
						"systemName": device.systemName,
					],
					"screen": [
						"width": screen.bounds.width,
						"height": screen.bounds.height,
						"scale": screen.scale,
					],
					"timestamp": ISO8601DateFormatter().string(from: Date()),
				]
			#else
				let bundle: Bundle = .main
				let info: [String: Any] = [
					"app": [
						"name": bundle.object(forInfoDictionaryKey: "CFBundleName") ?? "Unknown",
						"version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "Unknown",
						"build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "Unknown",
						"bundleId": bundle.bundleIdentifier ?? "Unknown",
					],
					"platform": "macOS",
					"timestamp": ISO8601DateFormatter().string(from: Date()),
				]
			#endif

			return .json(info)
		}
	}

	// MARK: - Screenshot

	private static func registerScreenshot(with handler: RequestHandler) {
		handler.register(
			"/screenshot",
			description: "Capture current screen"
		) { _ in
			// TODO: Implement screenshot capture
			return .json([
				"status": "pending",
				"message": "Screenshot functionality will be implemented soon",
			])
		}
	}

	// MARK: - View Hierarchy

	private static func registerHierarchy(with handler: RequestHandler) {
		handler.register(
			"/hierarchy",
			description: "Get view hierarchy"
		) { _ in
			// TODO: Implement view hierarchy inspection
			return .json([
				"status": "pending",
				"message": "View hierarchy functionality will be implemented soon",
			])
		}
	}
}
