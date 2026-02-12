import Foundation

// MARK: - FilesEndpoints

/// File system browsing endpoints
public enum FilesEndpoints {
	/// Create a router for file endpoints
	public static func createRouter() -> RequestHandler {
		let router: RequestHandler = .init(description: "Browse and read files from the app's sandbox")

		// Register index for this sub-router (file operations don't need main thread)
		router.register("/", description: "List all file endpoints", runsOnMainThread: false) { _ in
			return .json(router.routerInfo(deep: true))
		}

		self.registerKeyDirectories(with: router)
		self.registerList(with: router)
		self.registerMetadata(with: router)
		self.registerRead(with: router)
		self.registerHead(with: router)
		self.registerTail(with: router)

		return router
	}

	// MARK: - Directory Aliases

	/// Map of directory aliases to their paths
	private static func getDirectoryAliases() -> [String: String] {
		let fileManager: FileManager = .default
		var aliases: [String: String] = [:]

		// Home directory
		aliases["home"] = NSHomeDirectory()

		// Documents
		if let documentsURL: URL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
			aliases["documents"] = documentsURL.path
		}

		// Library
		if let libraryURL: URL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
			aliases["library"] = libraryURL.path
		}

		// Caches
		if let cachesURL: URL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
			aliases["caches"] = cachesURL.path
		}

		// Temp
		aliases["tmp"] = NSTemporaryDirectory()
		aliases["temp"] = NSTemporaryDirectory()

		// Application Support
		if let appSupportURL: URL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
			aliases["application-support"] = appSupportURL.path
			aliases["appsupport"] = appSupportURL.path
		}

		// Preferences (Library/Preferences)
		if let libraryURL: URL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
			aliases["preferences"] = libraryURL.appendingPathComponent("Preferences").path
		}

		// App Bundle
		aliases["bundle"] = Bundle.main.bundlePath
		aliases["app"] = Bundle.main.bundlePath

		// Bundle Resources
		if let resourcePath: String = Bundle.main.resourcePath {
			aliases["resources"] = resourcePath
		}

		return aliases
	}

	/// Resolve a path that may be an alias or an absolute path
	private static func resolvePath(_ pathOrAlias: String) -> String {
		let aliases: [String: String] = self.getDirectoryAliases()

		// Check if it's an alias
		if let resolved: String = aliases[pathOrAlias.lowercased()] {
			return resolved
		}

		// Check if it's an alias with a subpath (e.g., "documents/subfolder")
		let components: [String] = pathOrAlias.components(separatedBy: "/")
		if let firstComponent: String = components.first,
		   let basePath: String = aliases[firstComponent.lowercased()]
		{
			let remainingPath: String = components.dropFirst().joined(separator: "/")
			if remainingPath.isEmpty {
				return basePath
			}
			return (basePath as NSString).appendingPathComponent(remainingPath)
		}

		// Return as-is (absolute path)
		return pathOrAlias
	}

	// MARK: - Key Directories

	private static func registerKeyDirectories(with handler: RequestHandler) {
		handler.register(
			"/key-directories",
			description: "List all key app directories with their paths. Use these paths or aliases with other file endpoints.",
			runsOnMainThread: false
		) { _ in
			let fileManager: FileManager = .default
			var directories: [[String: Any]] = []

			// Home
			let homePath: String = NSHomeDirectory()
			directories.append(self.directoryInfo(
				name: "Home",
				alias: "home",
				path: homePath,
				description: "App's home/container directory"
			))

			// Documents
			if let documentsURL: URL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
				directories.append(self.directoryInfo(
					name: "Documents",
					alias: "documents",
					path: documentsURL.path,
					description: "User documents, backed up by iTunes/iCloud"
				))
			}

			// Library
			if let libraryURL: URL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
				directories.append(self.directoryInfo(
					name: "Library",
					alias: "library",
					path: libraryURL.path,
					description: "App support files, backed up (except Caches)"
				))
			}

			// Caches
			if let cachesURL: URL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
				directories.append(self.directoryInfo(
					name: "Caches",
					alias: "caches",
					path: cachesURL.path,
					description: "Cached data, not backed up, may be purged"
				))
			}

			// Application Support
			if let appSupportURL: URL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
				directories.append(self.directoryInfo(
					name: "Application Support",
					alias: "application-support",
					path: appSupportURL.path,
					description: "App-specific support files, backed up"
				))
			}

			// Preferences
			if let libraryURL: URL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
				let prefsPath: String = libraryURL.appendingPathComponent("Preferences").path
				directories.append(self.directoryInfo(
					name: "Preferences",
					alias: "preferences",
					path: prefsPath,
					description: "Preference plist files (UserDefaults)"
				))
			}

			// Temp
			let tempPath: String = NSTemporaryDirectory()
			directories.append(self.directoryInfo(
				name: "Temporary",
				alias: "tmp",
				path: tempPath,
				description: "Temporary files, not backed up, may be purged"
			))

			// App Bundle
			directories.append(self.directoryInfo(
				name: "App Bundle",
				alias: "bundle",
				path: Bundle.main.bundlePath,
				description: "The app's read-only bundle (executable, resources)"
			))

			// Bundle Resources
			if let resourcePath: String = Bundle.main.resourcePath {
				directories.append(self.directoryInfo(
					name: "Resources",
					alias: "resources",
					path: resourcePath,
					description: "Bundle resources (images, nibs, localized content)"
				))
			}

			return .json([
				"directories": directories,
				"note": "Use the 'alias' values with the path parameter in other endpoints (e.g., /files/list?path=documents)",
			])
		}
	}

	/// Helper to build directory info with existence check
	private static func directoryInfo(name: String, alias: String, path: String, description: String) -> [String: Any] {
		let fileManager: FileManager = .default
		var isDirectory: ObjCBool = false
		let exists: Bool = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)

		var info: [String: Any] = [
			"name": name,
			"alias": alias,
			"path": path,
			"description": description,
			"exists": exists,
			"isDirectory": isDirectory.boolValue,
		]

		// Add item count if directory exists
		if exists, isDirectory.boolValue {
			if let contents: [String] = try? fileManager.contentsOfDirectory(atPath: path) {
				info["itemCount"] = contents.count
			}
		}

		return info
	}

	// MARK: - List

	private static func registerList(with handler: RequestHandler) {
		handler.register(
			"/list",
			description: "List directory contents. Returns file names, sizes, types, and timestamps. Accepts directory aliases (documents, caches, tmp, bundle, etc.) or absolute paths.",
			parameters: [
				ParameterInfo(
					name: "path",
					description: "Directory path or alias (home, documents, library, caches, tmp, bundle, resources, application-support, preferences)",
					required: false,
					defaultValue: "home",
					examples: ["documents", "caches", "tmp", "bundle", "/absolute/path"]
				),
				ParameterInfo(
					name: "sort",
					description: "Sort order for results",
					required: false,
					defaultValue: "name",
					examples: ["name", "size", "modified"]
				),
				ParameterInfo(
					name: "order",
					description: "Sort direction",
					required: false,
					defaultValue: "asc",
					examples: ["asc", "desc"]
				),
				ParameterInfo(
					name: "limit",
					description: "Maximum number of items to return",
					required: false
				),
				ParameterInfo(
					name: "offset",
					description: "Number of items to skip (for pagination)",
					required: false,
					defaultValue: "0"
				),
			],
			runsOnMainThread: false
		) { request in
			let pathParam: String = request.queryParams["path"] ?? "home"
			let path: String = self.resolvePath(pathParam)
			let sortBy: String = request.queryParams["sort"] ?? "name"
			let order: String = request.queryParams["order"] ?? "asc"
			let limit: Int? = request.queryParams["limit"].flatMap { Int($0) }
			let offset: Int = request.queryParams["offset"].flatMap { Int($0) } ?? 0

			let fileManager: FileManager = .default
			var isDirectory: ObjCBool = false

			guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
				return .notFound("Path not found: \(path) (resolved from '\(pathParam)')")
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

	// MARK: - Metadata

	private static func registerMetadata(with handler: RequestHandler) {
		handler.register(
			"/metadata",
			description: "Get detailed metadata for a file or directory including size, timestamps, permissions, and owner.",
			parameters: [
				ParameterInfo(
					name: "path",
					description: "Path to file or directory (supports aliases like documents, bundle, etc.)",
					required: true,
					examples: ["documents/file.txt", "bundle/Info.plist", "/absolute/path"]
				),
			],
			runsOnMainThread: false
		) { request in
			guard let pathParam: String = request.queryParams["path"] else {
				return .error("Missing required parameter: path", status: .badRequest)
			}

			let path: String = self.resolvePath(pathParam)
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

	// MARK: - Read

	private static func registerRead(with handler: RequestHandler) {
		handler.register(
			"/read",
			description: "Read file contents. Returns raw binary data by default, or decoded text if encoding is specified. Content-Type is set based on file extension.",
			parameters: [
				ParameterInfo(
					name: "path",
					description: "Path to file (supports aliases like documents, bundle, etc.)",
					required: true,
					examples: ["documents/data.json", "bundle/Info.plist", "/absolute/path"]
				),
				ParameterInfo(
					name: "encoding",
					description: "Text encoding to decode file as (returns text/plain instead of binary)",
					required: false,
					examples: ["utf8", "ascii", "utf16", "latin1"]
				),
			],
			runsOnMainThread: false
		) { request in
			guard let pathParam: String = request.queryParams["path"] else {
				return .error("Missing required parameter: path", status: .badRequest)
			}

			let path: String = self.resolvePath(pathParam)
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

	// MARK: - Head

	private static func registerHead(with handler: RequestHandler) {
		handler.register(
			"/head",
			description: "Read the first N lines of a text file. Returns JSON with line array and joined content.",
			parameters: [
				ParameterInfo(
					name: "path",
					description: "Path to text file (supports aliases like documents, bundle, etc.)",
					required: true,
					examples: ["documents/log.txt", "tmp/output.log"]
				),
				ParameterInfo(
					name: "lines",
					description: "Number of lines to read from the beginning",
					required: false,
					defaultValue: "10"
				),
				ParameterInfo(
					name: "encoding",
					description: "Text encoding",
					required: false,
					defaultValue: "utf8",
					examples: ["utf8", "ascii"]
				),
			],
			runsOnMainThread: false
		) { request in
			guard let pathParam: String = request.queryParams["path"] else {
				return .error("Missing required parameter: path", status: .badRequest)
			}

			let path: String = self.resolvePath(pathParam)
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

	// MARK: - Tail

	private static func registerTail(with handler: RequestHandler) {
		handler.register(
			"/tail",
			description: "Read the last N lines of a text file. Useful for viewing log files. Returns JSON with line array and joined content.",
			parameters: [
				ParameterInfo(
					name: "path",
					description: "Path to text file (supports aliases like documents, bundle, etc.)",
					required: true,
					examples: ["documents/log.txt", "tmp/output.log"]
				),
				ParameterInfo(
					name: "lines",
					description: "Number of lines to read from the end",
					required: false,
					defaultValue: "10"
				),
				ParameterInfo(
					name: "encoding",
					description: "Text encoding",
					required: false,
					defaultValue: "utf8",
					examples: ["utf8", "ascii"]
				),
			],
			runsOnMainThread: false
		) { request in
			guard let pathParam: String = request.queryParams["path"] else {
				return .error("Missing required parameter: path", status: .badRequest)
			}

			let path: String = self.resolvePath(pathParam)
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
}
