import Foundation
#if canImport(UIKit)
	import UIKit
#endif

// MARK: - BuiltInEndpoints

/// Built-in endpoints for AppXplorerServer
public enum BuiltInEndpoints {
	/// Register all built-in endpoints with the request handler
	public static func registerAll(with handler: RequestHandler) {
		self.registerIndex(with: handler)
		self.registerInfo(with: handler)
		self.registerScreenshot(with: handler)
		self.registerHierarchy(with: handler)
		self.registerFiles(with: handler)
		self.registerUserDefaults(with: handler)
	}

	// MARK: - Index

	private static func registerIndex(with handler: RequestHandler) {
		handler["/"] = { _ in
			return .html("""
			<!DOCTYPE html>
			<html>
			<head>
			    <title>AppXplorer Server</title>
			    <meta name="viewport" content="width=device-width, initial-scale=1">
			    <style>
			        body {
			            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
			            padding: 20px;
			            max-width: 800px;
			            margin: 0 auto;
			        }
			        h1 { color: #007AFF; }
			        .endpoint {
			            background: #f5f5f5;
			            padding: 10px;
			            margin: 10px 0;
			            border-radius: 5px;
			        }
			        code {
			            background: #e0e0e0;
			            padding: 2px 5px;
			            border-radius: 3px;
			        }
			    </style>
			</head>
			<body>
			    <h1>AppXplorer Server</h1>
			    <p>Debug server is running! Available endpoints:</p>
			
			    <div class="endpoint">
			        <strong>GET /info</strong> - Get app and device information
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /screenshot</strong> - Capture current screen
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /hierarchy</strong> - Get view hierarchy
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /files</strong> - Browse file system
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /userdefaults</strong> - View UserDefaults
			    </div>
			
			    <p><small>Version 1.0.0</small></p>
			</body>
			</html>
			""")
		}
	}

	// MARK: - Info

	private static func registerInfo(with handler: RequestHandler) {
		handler["/info"] = { _ in
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
		handler["/screenshot"] = { _ in
			// TODO: Implement screenshot capture
			return .json([
				"status": "pending",
				"message": "Screenshot functionality will be implemented soon",
			])
		}
	}

	// MARK: - View Hierarchy

	private static func registerHierarchy(with handler: RequestHandler) {
		handler["/hierarchy"] = { _ in
			// TODO: Implement view hierarchy inspection
			return .json([
				"status": "pending",
				"message": "View hierarchy functionality will be implemented soon",
			])
		}
	}

	// MARK: - Files

	private static func registerFiles(with handler: RequestHandler) {
		handler["/files"] = { request in
			let path: String = request.queryParams["path"] ?? NSHomeDirectory()

			let fileManager: FileManager = .default
			var isDirectory: ObjCBool = false

			guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
				return .notFound("Path not found: \(path)")
			}

			if isDirectory.boolValue {
				// List directory contents
				do {
					let contents: [String] = try fileManager.contentsOfDirectory(atPath: path)
					var items: [[String: Any]] = []

					for item in contents {
						let itemPath: String = (path as NSString).appendingPathComponent(item)
						var itemIsDirectory: ObjCBool = false
						fileManager.fileExists(atPath: itemPath, isDirectory: &itemIsDirectory)

						var itemInfo: [String: Any] = [
							"name": item,
							"path": itemPath,
							"isDirectory": itemIsDirectory.boolValue,
						]

						if let attributes: [FileAttributeKey: Any] = try? fileManager.attributesOfItem(atPath: itemPath) {
							itemInfo["size"] = attributes[.size]
							itemInfo["modified"] = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970
						}

						items.append(itemInfo)
					}

					return .json([
						"path": path,
						"isDirectory": true,
						"contents": items,
					])
				}
				catch {
					return .error("Failed to read directory: \(error.localizedDescription)")
				}
			}
			else {
				// Return file info
				var fileInfo: [String: Any] = [
					"path": path,
					"isDirectory": false,
				]

				if let attributes: [FileAttributeKey: Any] = try? fileManager.attributesOfItem(atPath: path) {
					fileInfo["size"] = attributes[.size]
					fileInfo["modified"] = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970
				}

				return .json(fileInfo)
			}
		}
	}

	// MARK: - UserDefaults

	private static func registerUserDefaults(with handler: RequestHandler) {
		handler["/userdefaults"] = { request in
			let suiteName: String? = request.queryParams["suite"]
			let defaults: UserDefaults

			if let suite: String = suiteName {
				defaults = UserDefaults(suiteName: suite) ?? UserDefaults.standard
			}
			else {
				defaults = UserDefaults.standard
			}

			let dict: [String: Any] = defaults.dictionaryRepresentation()

			// Filter out system keys if requested
			let filterSystem: Bool = request.queryParams["filterSystem"] == "true"

			if filterSystem {
				let filtered: [String: Any] = dict.filter { key, _ in
					!key.hasPrefix("NS") &&
						!key.hasPrefix("Apple") &&
						!key.hasPrefix("com.apple") &&
						!key.hasPrefix("AK")
				}
				return .json(filtered)
			}

			return .json(dict)
		}
	}
}
