import Foundation

// MARK: - FilesEndpoints

/// File system browsing endpoints
public enum FilesEndpoints {
	/// Register file endpoints with the request handler
	public static func register(with handler: RequestHandler) {
		self.registerList(with: handler)
		self.registerMetadata(with: handler)
		self.registerRead(with: handler)
		self.registerHead(with: handler)
		self.registerTail(with: handler)
	}

	// MARK: - List

	/// GET /files/list - List directory contents with sorting and pagination
	/// Query params:
	///   - path: Directory path (default: app home directory)
	///   - sort: name, size, modified (default: name)
	///   - order: asc, desc (default: asc)
	///   - limit: Max items to return (default: unlimited)
	///   - offset: Skip first N items (default: 0)
	private static func registerList(with handler: RequestHandler) {
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

	// MARK: - Metadata

	/// GET /files/metadata - Get file or directory metadata
	/// Query params:
	///   - path: File or directory path (required)
	private static func registerMetadata(with handler: RequestHandler) {
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

	// MARK: - Read

	/// GET /files/read - Read file contents
	/// Query params:
	///   - path: File path (required)
	///   - encoding: text encoding (utf8, ascii, etc.) - if omitted, returns binary
	private static func registerRead(with handler: RequestHandler) {
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

	// MARK: - Head

	/// GET /files/head - Read first N lines of a text file
	/// Query params:
	///   - path: File path (required)
	///   - lines: Number of lines (default: 10)
	///   - encoding: text encoding (default: utf8)
	private static func registerHead(with handler: RequestHandler) {
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

	// MARK: - Tail

	/// GET /files/tail - Read last N lines of a text file
	/// Query params:
	///   - path: File path (required)
	///   - lines: Number of lines (default: 10)
	///   - encoding: text encoding (default: utf8)
	private static func registerTail(with handler: RequestHandler) {
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
}
