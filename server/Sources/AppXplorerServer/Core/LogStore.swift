import Foundation
import SQLite3

// MARK: - LogEntry

/// A single log entry
public struct LogEntry: Sendable {
	public let id: Int64
	public let timestamp: Date
	public let type: String
	public let text: String

	public init(id: Int64, timestamp: Date, type: String, text: String) {
		self.id = id
		self.timestamp = timestamp
		self.type = type
		self.text = text
	}
}

// MARK: - LogStore

/// SQLite-based log storage
/// Stores logs in /Library/Xplorer/sessions/<session-id>/logs.db
public final class LogStore: @unchecked Sendable {
	/// Shared instance for the current session
	public static let shared: LogStore = .init()

	/// The session ID (ISO datetime of session start)
	public let sessionId: String

	/// Path to the SQLite database
	public let databasePath: String

	/// SQLite database handle
	private var db: OpaquePointer?

	/// Lock for thread safety
	private let lock = NSLock()

	/// ISO8601 formatter for timestamps
	private static let isoFormatter: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return formatter
	}()

	// MARK: - Initialization

	public init() {
		// Generate session ID from current time
		let now = Date()
		// Use a filesystem-safe format: 2024-01-15T10-30-45
		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
		self.sessionId = dateFormatter.string(from: now)

		// Create directory path
		let libraryPath = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first!
		let sessionsPath = (libraryPath as NSString).appendingPathComponent("Xplorer/sessions/\(self.sessionId)")

		// Create directory if needed
		try? FileManager.default.createDirectory(atPath: sessionsPath, withIntermediateDirectories: true)

		self.databasePath = (sessionsPath as NSString).appendingPathComponent("logs.db")

		// Open database
		self.openDatabase()
	}

	deinit {
		self.closeDatabase()
	}

	// MARK: - Database Setup

	private func openDatabase() {
		self.lock.lock()
		defer { self.lock.unlock() }

		guard sqlite3_open(self.databasePath, &self.db) == SQLITE_OK else {
			print("LogStore: Failed to open database at \(self.databasePath)")
			return
		}

		// Create table if needed
		let createSQL = """
			CREATE TABLE IF NOT EXISTS logs (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				timestamp TEXT NOT NULL,
				type TEXT NOT NULL DEFAULT '',
				text TEXT NOT NULL
			);
			CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON logs(timestamp);
			CREATE INDEX IF NOT EXISTS idx_logs_type ON logs(type);
			"""

		var errMsg: UnsafeMutablePointer<CChar>?
		if sqlite3_exec(self.db, createSQL, nil, nil, &errMsg) != SQLITE_OK {
			if let errMsg = errMsg {
				print("LogStore: Failed to create table: \(String(cString: errMsg))")
				sqlite3_free(errMsg)
			}
		}
	}

	private func closeDatabase() {
		self.lock.lock()
		defer { self.lock.unlock() }

		if let db = self.db {
			sqlite3_close(db)
			self.db = nil
		}
	}

	// MARK: - Writing Logs

	/// Add a log entry with optional freeform type
	public func log(_ text: String, type: String = "") {
		self.lock.lock()
		defer { self.lock.unlock() }

		guard let db = self.db else { return }

		let timestamp = Self.isoFormatter.string(from: Date())
		let sql = "INSERT INTO logs (timestamp, type, text) VALUES (?, ?, ?)"

		var stmt: OpaquePointer?
		guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
		defer { sqlite3_finalize(stmt) }

		sqlite3_bind_text(stmt, 1, timestamp, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
		sqlite3_bind_text(stmt, 2, type, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
		sqlite3_bind_text(stmt, 3, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

		sqlite3_step(stmt)
	}

	// MARK: - Reading Logs

	/// Query parameters for fetching logs
	public struct QueryOptions {
		public var startTime: Date?
		public var endTime: Date?
		public var type: String?         // Exact type match
		public var textPattern: String?  // SQL LIKE pattern (e.g., "%error%")
		public var limit: Int?
		public var offset: Int?
		public var newestFirst: Bool

		public init(
			startTime: Date? = nil,
			endTime: Date? = nil,
			type: String? = nil,
			textPattern: String? = nil,
			limit: Int? = nil,
			offset: Int? = nil,
			newestFirst: Bool = true
		) {
			self.startTime = startTime
			self.endTime = endTime
			self.type = type
			self.textPattern = textPattern
			self.limit = limit
			self.offset = offset
			self.newestFirst = newestFirst
		}
	}

	/// Fetch logs with optional filtering
	public func fetch(options: QueryOptions = .init()) -> [LogEntry] {
		self.lock.lock()
		defer { self.lock.unlock() }

		guard let db = self.db else { return [] }

		var conditions: [String] = []
		var bindings: [(Int32, String)] = []
		var bindIndex: Int32 = 1

		// Build WHERE conditions
		if let startTime = options.startTime {
			conditions.append("timestamp >= ?")
			bindings.append((bindIndex, Self.isoFormatter.string(from: startTime)))
			bindIndex += 1
		}

		if let endTime = options.endTime {
			conditions.append("timestamp <= ?")
			bindings.append((bindIndex, Self.isoFormatter.string(from: endTime)))
			bindIndex += 1
		}

		if let type = options.type, !type.isEmpty {
			conditions.append("type = ?")
			bindings.append((bindIndex, type))
			bindIndex += 1
		}

		if let pattern = options.textPattern, !pattern.isEmpty {
			conditions.append("text LIKE ?")
			bindings.append((bindIndex, pattern))
			bindIndex += 1
		}

		// Build query
		var sql = "SELECT id, timestamp, type, text FROM logs"
		if !conditions.isEmpty {
			sql += " WHERE " + conditions.joined(separator: " AND ")
		}

		// Order
		sql += options.newestFirst ? " ORDER BY id DESC" : " ORDER BY id ASC"

		// Limit and offset
		if let limit = options.limit {
			sql += " LIMIT \(limit)"
			if let offset = options.offset {
				sql += " OFFSET \(offset)"
			}
		}

		var stmt: OpaquePointer?
		guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
			return []
		}
		defer { sqlite3_finalize(stmt) }

		// Bind parameters
		for (index, value) in bindings {
			sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
		}

		// Fetch results
		var entries: [LogEntry] = []
		while sqlite3_step(stmt) == SQLITE_ROW {
			let id = sqlite3_column_int64(stmt, 0)
			let timestampStr = String(cString: sqlite3_column_text(stmt, 1))
			let type = String(cString: sqlite3_column_text(stmt, 2))
			let text = String(cString: sqlite3_column_text(stmt, 3))

			let timestamp = Self.isoFormatter.date(from: timestampStr) ?? Date()

			entries.append(LogEntry(id: id, timestamp: timestamp, type: type, text: text))
		}

		return entries
	}

	/// Get total log count
	public func count() -> Int {
		self.lock.lock()
		defer { self.lock.unlock() }

		guard let db = self.db else { return 0 }

		let sql = "SELECT COUNT(*) FROM logs"
		var stmt: OpaquePointer?
		guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
		defer { sqlite3_finalize(stmt) }

		if sqlite3_step(stmt) == SQLITE_ROW {
			return Int(sqlite3_column_int64(stmt, 0))
		}
		return 0
	}

	/// Clear all logs
	public func clear() {
		self.lock.lock()
		defer { self.lock.unlock() }

		guard let db = self.db else { return }

		sqlite3_exec(db, "DELETE FROM logs", nil, nil, nil)
	}
}
