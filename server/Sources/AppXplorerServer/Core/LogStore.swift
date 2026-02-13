import Foundation
import SQLite3

// MARK: - LogLevel

/// Log severity level
public enum LogLevel: Int, Sendable, Codable {
	case debug = 0
	case info = 1
	case warning = 2
	case error = 3
	case critical = 4

	public var name: String {
		switch self {
			case .debug: return "debug"
			case .info: return "info"
			case .warning: return "warning"
			case .error: return "error"
			case .critical: return "critical"
		}
	}

	public init?(name: String) {
		switch name.lowercased() {
			case "debug": self = .debug
			case "info": self = .info
			case "warning", "warn": self = .warning
			case "error": self = .error
			case "critical", "fatal": self = .critical
			default: return nil
		}
	}
}

// MARK: - LogEntry

/// A single log entry
public struct LogEntry: Sendable {
	public let id: Int64
	public let timestamp: Date
	public let level: LogLevel
	public let text: String

	public init(id: Int64, timestamp: Date, level: LogLevel, text: String) {
		self.id = id
		self.timestamp = timestamp
		self.level = level
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

	/// Formatter for session ID (filesystem-safe)
	private static let sessionIdFormatter: ISO8601DateFormatter = {
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
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
				level INTEGER NOT NULL DEFAULT 1,
				text TEXT NOT NULL
			);
			CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON logs(timestamp);
			CREATE INDEX IF NOT EXISTS idx_logs_level ON logs(level);
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

	/// Add a log entry
	public func log(_ text: String, level: LogLevel = .info) {
		self.lock.lock()
		defer { self.lock.unlock() }

		guard let db = self.db else { return }

		let timestamp = Self.isoFormatter.string(from: Date())
		let sql = "INSERT INTO logs (timestamp, level, text) VALUES (?, ?, ?)"

		var stmt: OpaquePointer?
		guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
		defer { sqlite3_finalize(stmt) }

		sqlite3_bind_text(stmt, 1, timestamp, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
		sqlite3_bind_int(stmt, 2, Int32(level.rawValue))
		sqlite3_bind_text(stmt, 3, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

		sqlite3_step(stmt)
	}

	/// Convenience methods for different log levels
	public func debug(_ text: String) { self.log(text, level: .debug) }
	public func info(_ text: String) { self.log(text, level: .info) }
	public func warning(_ text: String) { self.log(text, level: .warning) }
	public func error(_ text: String) { self.log(text, level: .error) }
	public func critical(_ text: String) { self.log(text, level: .critical) }

	// MARK: - Reading Logs

	/// Query parameters for fetching logs
	public struct QueryOptions {
		public var startTime: Date?
		public var endTime: Date?
		public var minLevel: LogLevel?
		public var textPattern: String?  // SQL LIKE pattern (e.g., "%error%")
		public var limit: Int?
		public var offset: Int?
		public var newestFirst: Bool

		public init(
			startTime: Date? = nil,
			endTime: Date? = nil,
			minLevel: LogLevel? = nil,
			textPattern: String? = nil,
			limit: Int? = nil,
			offset: Int? = nil,
			newestFirst: Bool = true
		) {
			self.startTime = startTime
			self.endTime = endTime
			self.minLevel = minLevel
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
		var bindings: [(Int32, Any)] = []
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

		if let minLevel = options.minLevel {
			conditions.append("level >= ?")
			bindings.append((bindIndex, minLevel.rawValue))
			bindIndex += 1
		}

		if let pattern = options.textPattern, !pattern.isEmpty {
			conditions.append("text LIKE ?")
			bindings.append((bindIndex, pattern))
			bindIndex += 1
		}

		// Build query
		var sql = "SELECT id, timestamp, level, text FROM logs"
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
			if let stringValue = value as? String {
				sqlite3_bind_text(stmt, index, stringValue, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
			}
			else if let intValue = value as? Int {
				sqlite3_bind_int(stmt, index, Int32(intValue))
			}
		}

		// Fetch results
		var entries: [LogEntry] = []
		while sqlite3_step(stmt) == SQLITE_ROW {
			let id = sqlite3_column_int64(stmt, 0)
			let timestampStr = String(cString: sqlite3_column_text(stmt, 1))
			let levelRaw = Int(sqlite3_column_int(stmt, 2))
			let text = String(cString: sqlite3_column_text(stmt, 3))

			let timestamp = Self.isoFormatter.date(from: timestampStr) ?? Date()
			let level = LogLevel(rawValue: levelRaw) ?? .info

			entries.append(LogEntry(id: id, timestamp: timestamp, level: level, text: text))
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
