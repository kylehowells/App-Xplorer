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
			        <strong>GET /files/list</strong> - List directory contents
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /files/metadata</strong> - Get file/directory metadata
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /files/read</strong> - Read file contents
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /files/head</strong> - Read first N lines of text file
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /files/tail</strong> - Read last N lines of text file
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
		self.registerFilesList(with: handler)
		self.registerFilesMetadata(with: handler)
		self.registerFilesRead(with: handler)
		self.registerFilesHead(with: handler)
		self.registerFilesTail(with: handler)
	}

	/// GET /files/list - List directory contents with sorting and pagination
	/// Query params:
	///   - path: Directory path (default: app home directory)
	///   - sort: name, size, modified (default: name)
	///   - order: asc, desc (default: asc)
	///   - limit: Max items to return (default: unlimited)
	///   - offset: Skip first N items (default: 0)
	private static func registerFilesList(with handler: RequestHandler) {
		handler["/files/list"] = { request in
			let path: String = request.queryParams["path"] ?? NSHomeDirectory()
			let sortBy: String = request.queryParams["sort"] ?? "name"
			let order: String = request.queryParams["order"] ?? "asc"
			let limit: Int? = request.queryParams["limit"].flatMap { Int($0) }
			let offset: Int = request.queryParams["offset"].flatMap { Int($0) } ?? 0

			let fileManager: FileManager = .default
			var isDirectory: ObjCBool = false

			guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
				return .notFound("Path not found: \(path)")
			}

			guard isDirectory.boolValue else {
				return .error("Path is not a directory: \(path)", status: .badRequest)
			}

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
						itemInfo["size"] = attributes[.size] ?? 0
						itemInfo["modified"] = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
						itemInfo["created"] = (attributes[.creationDate] as? Date)?.timeIntervalSince1970
						itemInfo["type"] = (attributes[.type] as? FileAttributeType)?.rawValue
					}

					items.append(itemInfo)
				}

				// Sort items
				let ascending: Bool = order.lowercased() != "desc"
				items.sort { a, b in
					switch sortBy.lowercased() {
						case "size":
							let sizeA: Int = (a["size"] as? Int) ?? 0
							let sizeB: Int = (b["size"] as? Int) ?? 0
							return ascending ? sizeA < sizeB : sizeA > sizeB

						case "modified":
							let modA: Double = (a["modified"] as? Double) ?? 0
							let modB: Double = (b["modified"] as? Double) ?? 0
							return ascending ? modA < modB : modA > modB

						default: // name
							let nameA: String = (a["name"] as? String) ?? ""
							let nameB: String = (b["name"] as? String) ?? ""
							return ascending ? nameA.localizedCaseInsensitiveCompare(nameB) == .orderedAscending
								: nameA.localizedCaseInsensitiveCompare(nameB) == .orderedDescending
					}
				}

				// Apply pagination
				let totalCount: Int = items.count
				if offset > 0 {
					items = Array(items.dropFirst(offset))
				}
				if let limit = limit {
					items = Array(items.prefix(limit))
				}

				return .json([
					"path": path,
					"totalCount": totalCount,
					"offset": offset,
					"count": items.count,
					"sort": sortBy,
					"order": order,
					"contents": items,
				])
			}
			catch {
				return .error("Failed to read directory: \(error.localizedDescription)")
			}
		}
	}

	/// GET /files/metadata - Get file or directory metadata
	/// Query params:
	///   - path: File or directory path (required)
	private static func registerFilesMetadata(with handler: RequestHandler) {
		handler["/files/metadata"] = { request in
			guard let path: String = request.queryParams["path"] else {
				return .error("Missing required parameter: path", status: .badRequest)
			}

			let fileManager: FileManager = .default
			var isDirectory: ObjCBool = false

			guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
				return .notFound("Path not found: \(path)")
			}

			do {
				let attributes: [FileAttributeKey: Any] = try fileManager.attributesOfItem(atPath: path)

				var metadata: [String: Any] = [
					"path": path,
					"name": (path as NSString).lastPathComponent,
					"isDirectory": isDirectory.boolValue,
					"size": attributes[.size] ?? 0,
					"modified": (attributes[.modificationDate] as? Date)?.timeIntervalSince1970,
					"created": (attributes[.creationDate] as? Date)?.timeIntervalSince1970,
					"type": (attributes[.type] as? FileAttributeType)?.rawValue,
					"permissions": attributes[.posixPermissions],
					"owner": attributes[.ownerAccountName],
					"group": attributes[.groupOwnerAccountName],
				]

				// Add extension info for files
				if !isDirectory.boolValue {
					let ext: String = (path as NSString).pathExtension
					metadata["extension"] = ext.isEmpty ? nil : ext
				}

				// Add item count for directories
				if isDirectory.boolValue {
					if let contents: [String] = try? fileManager.contentsOfDirectory(atPath: path) {
						metadata["itemCount"] = contents.count
					}
				}

				return .json(metadata)
			}
			catch {
				return .error("Failed to read metadata: \(error.localizedDescription)")
			}
		}
	}

	/// GET /files/read - Read file contents
	/// Query params:
	///   - path: File path (required)
	///   - encoding: text encoding (utf8, ascii, etc.) - if omitted, returns binary
	private static func registerFilesRead(with handler: RequestHandler) {
		handler["/files/read"] = { request in
			guard let path: String = request.queryParams["path"] else {
				return .error("Missing required parameter: path", status: .badRequest)
			}

			let fileManager: FileManager = .default
			var isDirectory: ObjCBool = false

			guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
				return .notFound("Path not found: \(path)")
			}

			guard !isDirectory.boolValue else {
				return .error("Cannot read directory as file: \(path)", status: .badRequest)
			}

			guard let data: Data = fileManager.contents(atPath: path) else {
				return .error("Failed to read file: \(path)")
			}

			// Check if text encoding requested
			if let encoding: String = request.queryParams["encoding"] {
				let stringEncoding: String.Encoding
				switch encoding.lowercased() {
					case "utf8", "utf-8":
						stringEncoding = .utf8

					case "ascii":
						stringEncoding = .ascii

					case "utf16", "utf-16":
						stringEncoding = .utf16

					case "latin1", "iso-8859-1":
						stringEncoding = .isoLatin1

					default:
						stringEncoding = .utf8
				}

				if let text: String = String(data: data, encoding: stringEncoding) {
					return .text(text)
				}
				else {
					return .error("Failed to decode file as \(encoding)")
				}
			}

			// Return binary data with appropriate content type
			let ext: String = (path as NSString).pathExtension.lowercased()
			switch ext {
				case "json":
					return Response(status: .ok, contentType: .json, body: data)

				case "html", "htm":
					return Response(status: .ok, contentType: .html, body: data)

				case "txt", "log", "md":
					return Response(status: .ok, contentType: .text, body: data)

				case "png":
					return .png(data)

				case "jpg", "jpeg":
					return .jpeg(data)

				default:
					return .binary(data)
			}
		}
	}

	/// GET /files/head - Read first N lines of a text file
	/// Query params:
	///   - path: File path (required)
	///   - lines: Number of lines (default: 10)
	///   - encoding: text encoding (default: utf8)
	private static func registerFilesHead(with handler: RequestHandler) {
		handler["/files/head"] = { request in
			guard let path: String = request.queryParams["path"] else {
				return .error("Missing required parameter: path", status: .badRequest)
			}

			let lineCount: Int = request.queryParams["lines"].flatMap { Int($0) } ?? 10
			let encoding: String = request.queryParams["encoding"] ?? "utf8"

			let fileManager: FileManager = .default
			var isDirectory: ObjCBool = false

			guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
				return .notFound("Path not found: \(path)")
			}

			guard !isDirectory.boolValue else {
				return .error("Cannot read directory as file: \(path)", status: .badRequest)
			}

			guard let data: Data = fileManager.contents(atPath: path) else {
				return .error("Failed to read file: \(path)")
			}

			let stringEncoding: String.Encoding = encoding.lowercased() == "ascii" ? .ascii : .utf8

			guard let text: String = String(data: data, encoding: stringEncoding) else {
				return .error("Failed to decode file as text")
			}

			let lines: [String] = text.components(separatedBy: .newlines)
			let headLines: [String] = Array(lines.prefix(lineCount))

			return .json([
				"path": path,
				"totalLines": lines.count,
				"requestedLines": lineCount,
				"returnedLines": headLines.count,
				"content": headLines.joined(separator: "\n"),
				"lines": headLines,
			])
		}
	}

	/// GET /files/tail - Read last N lines of a text file
	/// Query params:
	///   - path: File path (required)
	///   - lines: Number of lines (default: 10)
	///   - encoding: text encoding (default: utf8)
	private static func registerFilesTail(with handler: RequestHandler) {
		handler["/files/tail"] = { request in
			guard let path: String = request.queryParams["path"] else {
				return .error("Missing required parameter: path", status: .badRequest)
			}

			let lineCount: Int = request.queryParams["lines"].flatMap { Int($0) } ?? 10
			let encoding: String = request.queryParams["encoding"] ?? "utf8"

			let fileManager: FileManager = .default
			var isDirectory: ObjCBool = false

			guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
				return .notFound("Path not found: \(path)")
			}

			guard !isDirectory.boolValue else {
				return .error("Cannot read directory as file: \(path)", status: .badRequest)
			}

			guard let data: Data = fileManager.contents(atPath: path) else {
				return .error("Failed to read file: \(path)")
			}

			let stringEncoding: String.Encoding = encoding.lowercased() == "ascii" ? .ascii : .utf8

			guard let text: String = String(data: data, encoding: stringEncoding) else {
				return .error("Failed to decode file as text")
			}

			let lines: [String] = text.components(separatedBy: .newlines)
			let tailLines: [String] = Array(lines.suffix(lineCount))

			return .json([
				"path": path,
				"totalLines": lines.count,
				"requestedLines": lineCount,
				"returnedLines": tailLines.count,
				"content": tailLines.joined(separator: "\n"),
				"lines": tailLines,
			])
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
