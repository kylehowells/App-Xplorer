import Foundation

// MARK: - LogEndpoints

/// Endpoints for log retrieval
/// Logs are ingested via the Swift API: AppXplorerServer.log.log("message", type: "network")
public enum LogEndpoints {
	/// Create a router for log endpoints
	public static func createRouter() -> RequestHandler {
		let handler = RequestHandler(description: "Log retrieval. Apps send logs via AppXplorerServer.log.log() API, then retrieve them here.")

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
					name: "type",
					description: "Filter by log type (exact match)",
					required: false,
					examples: ["network", "auth", "error"]
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

			options.type = request.queryParams["type"]
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
					var obj: [String: Any] = [
						"id": entry.id,
						"time": self.isoFormatter.string(from: entry.timestamp),
						"text": entry.text,
					]
					if !entry.type.isEmpty {
						obj["type"] = entry.type
					}
					return obj
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
					var jsonObj: [String: Any] = [
						"id": entry.id,
						"time": self.isoFormatter.string(from: entry.timestamp),
						"text": entry.text,
					]
					if !entry.type.isEmpty {
						jsonObj["type"] = entry.type
					}
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
