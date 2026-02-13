import Foundation

// MARK: - LogEndpoints

/// Endpoints for log ingestion and retrieval
public enum LogEndpoints {
	/// Create a router for log endpoints
	public static func createRouter() -> RequestHandler {
		let handler = RequestHandler(description: "Log ingestion and retrieval. Apps can send logs here for remote viewing.")

		self.registerIngest(with: handler)
		self.registerFetch(with: handler)
		self.registerInfo(with: handler)
		self.registerClear(with: handler)

		return handler
	}

	/// ISO8601 formatter for parsing/formatting timestamps
	private static let isoFormatter: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter
	}()

	// MARK: - Ingest

	private static func registerIngest(with handler: RequestHandler) {
		handler.register(
			"/ingest",
			description: "Ingest a log entry. Send log messages from your app to be stored and retrieved later.",
			parameters: [
				ParameterInfo(
					name: "text",
					description: "The log message text",
					required: true,
					examples: ["User logged in", "Error: Connection failed"]
				),
				ParameterInfo(
					name: "level",
					description: "Log level/severity",
					required: false,
					defaultValue: "info",
					examples: ["debug", "info", "warning", "error", "critical"]
				),
			],
			runsOnMainThread: false
		) { request in
			guard let text = request.queryParams["text"], !text.isEmpty else {
				return .error("Missing required parameter: text", status: .badRequest)
			}

			let levelName = request.queryParams["level"] ?? "info"
			let level = LogLevel(name: levelName) ?? .info

			LogStore.shared.log(text, level: level)

			return .json([
				"success": true,
				"level": level.name,
				"count": LogStore.shared.count(),
			])
		}
	}

	// MARK: - Fetch

	private static func registerFetch(with handler: RequestHandler) {
		handler.register(
			"/",
			description: "Fetch logs. Returns logs in JSONL format (one JSON object per line). Supports time-based filtering, text search with SQL LIKE patterns, and pagination.",
			parameters: [
				ParameterInfo(
					name: "start",
					description: "Start time filter (ISO8601 format)",
					required: false,
					examples: ["2024-01-15T10:00:00Z"]
				),
				ParameterInfo(
					name: "end",
					description: "End time filter (ISO8601 format)",
					required: false,
					examples: ["2024-01-15T12:00:00Z"]
				),
				ParameterInfo(
					name: "level",
					description: "Minimum log level to include",
					required: false,
					examples: ["debug", "info", "warning", "error", "critical"]
				),
				ParameterInfo(
					name: "match",
					description: "Text pattern filter using SQL LIKE syntax. Use % as wildcard.",
					required: false,
					examples: ["%error%", "User%", "%failed"]
				),
				ParameterInfo(
					name: "limit",
					description: "Maximum number of logs to return",
					required: false,
					defaultValue: "12",
					examples: ["12", "50", "100", "500"]
				),
				ParameterInfo(
					name: "offset",
					description: "Number of logs to skip (for pagination)",
					required: false,
					examples: ["0", "100", "200"]
				),
				ParameterInfo(
					name: "sort",
					description: "Sort order: 'newest' (default) or 'oldest' first",
					required: false,
					defaultValue: "newest",
					examples: ["newest", "oldest"]
				),
				ParameterInfo(
					name: "format",
					description: "Output format: 'jsonl' (default, one JSON per line) or 'json' (array)",
					required: false,
					defaultValue: "jsonl",
					examples: ["jsonl", "json"]
				),
			],
			runsOnMainThread: false
		) { request in
			// Parse query options
			var options = LogStore.QueryOptions()

			if let startStr = request.queryParams["start"] {
				options.startTime = self.isoFormatter.date(from: startStr)
			}

			if let endStr = request.queryParams["end"] {
				options.endTime = self.isoFormatter.date(from: endStr)
			}

			if let levelStr = request.queryParams["level"] {
				options.minLevel = LogLevel(name: levelStr)
			}

			options.textPattern = request.queryParams["match"]

			if let limitStr = request.queryParams["limit"], let limit = Int(limitStr) {
				options.limit = limit
			}
			else {
				options.limit = 12  // Default limit
			}

			if let offsetStr = request.queryParams["offset"], let offset = Int(offsetStr) {
				options.offset = offset
			}

			let sortOrder = request.queryParams["sort"] ?? "newest"
			options.newestFirst = sortOrder.lowercased() != "oldest"

			let format = request.queryParams["format"] ?? "jsonl"

			// Fetch logs
			let entries = LogStore.shared.fetch(options: options)

			if format.lowercased() == "json" {
				// Return as JSON array
				let jsonEntries: [[String: Any]] = entries.map { entry in
					[
						"id": entry.id,
						"time": self.isoFormatter.string(from: entry.timestamp),
						"level": entry.level.name,
						"text": entry.text,
					]
				}
				return .json([
					"count": entries.count,
					"total": LogStore.shared.count(),
					"logs": jsonEntries,
				])
			}
			else {
				// Return as JSONL (one JSON object per line)
				// First line is metadata with total count
				var lines: [String] = []

				let totalCount = LogStore.shared.count()
				let metaObj: [String: Any] = [
					"_meta": true,
					"total": totalCount,
					"returned": entries.count,
				]
				if let metaData = try? JSONSerialization.data(withJSONObject: metaObj, options: [.sortedKeys]),
				   let metaLine = String(data: metaData, encoding: .utf8)
				{
					lines.append(metaLine)
				}

				for entry in entries {
					let jsonObj: [String: Any] = [
						"id": entry.id,
						"time": self.isoFormatter.string(from: entry.timestamp),
						"level": entry.level.name,
						"text": entry.text,
					]
					if let data = try? JSONSerialization.data(withJSONObject: jsonObj, options: [.sortedKeys]),
					   let line = String(data: data, encoding: .utf8)
					{
						lines.append(line)
					}
				}
				let body = lines.joined(separator: "\n")
				return .text(body)
			}
		}
	}

	// MARK: - Info

	private static func registerInfo(with handler: RequestHandler) {
		handler.register(
			"/info",
			description: "Get information about the current log session including session ID, database path, and log count.",
			runsOnMainThread: false
		) { _ in
			return .json([
				"sessionId": LogStore.shared.sessionId,
				"databasePath": LogStore.shared.databasePath,
				"count": LogStore.shared.count(),
			])
		}
	}

	// MARK: - Clear

	private static func registerClear(with handler: RequestHandler) {
		handler.register(
			"/clear",
			description: "Clear all logs from the current session.",
			runsOnMainThread: false
		) { _ in
			let countBefore = LogStore.shared.count()
			LogStore.shared.clear()
			return .json([
				"success": true,
				"cleared": countBefore,
			])
		}
	}
}
