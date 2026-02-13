import Foundation
import Testing
@testable import AppXplorerServer

// MARK: - LogLevel Tests (No DB access, can run in parallel)

@Test func testLogLevelNames() async throws {
	#expect(LogLevel.debug.name == "debug")
	#expect(LogLevel.info.name == "info")
	#expect(LogLevel.warning.name == "warning")
	#expect(LogLevel.error.name == "error")
	#expect(LogLevel.critical.name == "critical")
}

@Test func testLogLevelFromName() async throws {
	#expect(LogLevel(name: "debug") == .debug)
	#expect(LogLevel(name: "info") == .info)
	#expect(LogLevel(name: "warning") == .warning)
	#expect(LogLevel(name: "warn") == .warning)
	#expect(LogLevel(name: "error") == .error)
	#expect(LogLevel(name: "critical") == .critical)
	#expect(LogLevel(name: "fatal") == .critical)
	#expect(LogLevel(name: "invalid") == nil)
}

@Test func testLogLevelCaseInsensitive() async throws {
	#expect(LogLevel(name: "DEBUG") == .debug)
	#expect(LogLevel(name: "Info") == .info)
	#expect(LogLevel(name: "WARNING") == .warning)
	#expect(LogLevel(name: "Error") == .error)
}

@Test func testLogLevelRawValues() async throws {
	#expect(LogLevel.debug.rawValue == 0)
	#expect(LogLevel.info.rawValue == 1)
	#expect(LogLevel.warning.rawValue == 2)
	#expect(LogLevel.error.rawValue == 3)
	#expect(LogLevel.critical.rawValue == 4)
}

// MARK: - LogStore Tests (Uses shared DB, must run serialized)

/// All tests that access the shared LogStore database must be in this suite
/// to prevent race conditions from the clear() calls
@Suite(.serialized)
struct LogStoreDatabaseTests {
	// Use a unique marker for each test to identify its logs
	private func uniqueMarker() -> String {
		return UUID().uuidString.prefix(8).description
	}

	@Test func testLogStoreSessionIdFormat() async throws {
		let store = LogStore.shared
		// Session ID should be in format like "2024-01-15T10-30-45"
		#expect(store.sessionId.contains("T"))
		#expect(store.sessionId.count >= 17) // "yyyy-MM-ddTHH-mm-ss"
	}

	@Test func testLogStoreDatabasePathExists() async throws {
		let store = LogStore.shared
		#expect(store.databasePath.contains("Xplorer/sessions"))
		#expect(store.databasePath.hasSuffix("logs.db"))
	}

	@Test func testLogStoreBasicLogging() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()

		store.log("\(marker) Test message 1", level: .info)
		store.log("\(marker) Test message 2", level: .error)

		// Verify our messages are there using pattern match
		let entries = store.fetch(options: .init(textPattern: "%\(marker)%", limit: 10))
		#expect(entries.count == 2)
	}

	@Test func testLogStoreConvenienceMethods() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()

		store.debug("\(marker) Debug message")
		store.info("\(marker) Info message")
		store.warning("\(marker) Warning message")
		store.error("\(marker) Error message")
		store.critical("\(marker) Critical message")

		let entries = store.fetch(options: .init(textPattern: "%\(marker)%", limit: 10))
		#expect(entries.count == 5)

		let levels = entries.map { $0.level }
		#expect(levels.contains(.debug))
		#expect(levels.contains(.info))
		#expect(levels.contains(.warning))
		#expect(levels.contains(.error))
		#expect(levels.contains(.critical))
	}

	@Test func testLogStoreFetchAll() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()

		store.log("\(marker) Message 1", level: .info)
		store.log("\(marker) Message 2", level: .info)
		store.log("\(marker) Message 3", level: .info)

		let entries = store.fetch(options: .init(textPattern: "%\(marker)%", limit: 100))
		#expect(entries.count == 3)
	}

	@Test func testLogStoreFetchWithLimit() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()

		for i in 1 ... 10 {
			store.log("\(marker) Message \(i)", level: .info)
		}

		let entries = store.fetch(options: .init(textPattern: "%\(marker)%", limit: 5))
		#expect(entries.count == 5)
	}

	@Test func testLogStoreFetchWithOffset() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()

		store.log("\(marker) First", level: .info)
		store.log("\(marker) Second", level: .info)
		store.log("\(marker) Third", level: .info)

		// Newest first, skip 1
		let entries = store.fetch(options: .init(textPattern: "%\(marker)%", limit: 10, offset: 1, newestFirst: true))
		#expect(entries.count == 2)
		#expect(!entries.map { $0.text }.contains("\(marker) Third")) // Should have skipped newest
	}

	@Test func testLogStoreFetchNewestFirst() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()

		store.log("\(marker) First", level: .info)
		store.log("\(marker) Second", level: .info)
		store.log("\(marker) Third", level: .info)

		let newestFirst = store.fetch(options: .init(textPattern: "%\(marker)%", limit: 3, newestFirst: true))
		#expect(newestFirst.count == 3)
		#expect(newestFirst.first?.text == "\(marker) Third")

		let oldestFirst = store.fetch(options: .init(textPattern: "%\(marker)%", limit: 3, newestFirst: false))
		#expect(oldestFirst.count == 3)
		#expect(oldestFirst.first?.text == "\(marker) First")
	}

	@Test func testLogStoreFetchByLevel() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()

		store.log("\(marker) Debug log", level: .debug)
		store.log("\(marker) Info log", level: .info)
		store.log("\(marker) Warning log", level: .warning)
		store.log("\(marker) Error log", level: .error)

		// Fetch only warning and above with our marker
		let entries = store.fetch(options: .init(minLevel: .warning, textPattern: "%\(marker)%", limit: 100))
		#expect(entries.count == 2)
		#expect(entries.allSatisfy { $0.level.rawValue >= LogLevel.warning.rawValue })
	}

	@Test func testLogStoreFetchByTextPattern() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()

		store.log("\(marker) User logged in", level: .info)
		store.log("\(marker) User logged out", level: .info)
		store.log("\(marker) Error occurred", level: .error)
		store.log("\(marker) System started", level: .info)

		// Fetch logs containing "User" with our marker
		let userLogs = store.fetch(options: .init(textPattern: "%\(marker)%User%", limit: 100))
		#expect(userLogs.count == 2)
		#expect(userLogs.allSatisfy { $0.text.contains("User") })

		// Fetch logs starting with marker and containing "Error"
		let errorLogs = store.fetch(options: .init(textPattern: "\(marker) Error%", limit: 100))
		#expect(errorLogs.count == 1)
	}

	@Test func testLogStoreFetchByTimeRange() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()

		let beforeLogs = Date().addingTimeInterval(-1) // 1 second ago

		store.log("\(marker) During test", level: .info)

		let afterLogs = Date().addingTimeInterval(1) // 1 second from now

		// Fetch logs in time range with our marker
		let entries = store.fetch(options: .init(
			startTime: beforeLogs,
			endTime: afterLogs,
			textPattern: "%\(marker)%",
			limit: 100
		))
		#expect(entries.count >= 1)
		#expect(entries.contains { $0.text == "\(marker) During test" })
	}

	@Test func testLogStoreClear() async throws {
		let store = LogStore.shared

		// Add a test log first
		store.log("Before clear", level: .info)
		let countBefore = store.count()
		#expect(countBefore >= 1)

		// Clear and verify
		store.clear()
		#expect(store.count() == 0)

		// Add some back so other tests can work
		store.log("After clear", level: .info)
		#expect(store.count() >= 1)
	}

	@Test func testLogEntryHasCorrectFields() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()

		let beforeLog = Date().addingTimeInterval(-1)
		store.log("\(marker) Test entry", level: .warning)
		let afterLog = Date().addingTimeInterval(1)

		let entries = store.fetch(options: .init(textPattern: "%\(marker)%", limit: 1, newestFirst: true))
		guard let entry = entries.first else {
			#expect(Bool(false), "Failed to fetch the test entry")
			return
		}

		#expect(entry.id > 0)
		#expect(entry.text == "\(marker) Test entry")
		#expect(entry.level == .warning)
		#expect(entry.timestamp >= beforeLog)
		#expect(entry.timestamp <= afterLog)
	}

	@Test func testLogStoreCombinedFilters() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()

		store.log("\(marker) User error: failed to login", level: .error)
		store.log("\(marker) User info: logged in", level: .info)
		store.log("\(marker) System error: disk full", level: .error)
		store.log("\(marker) System info: started", level: .info)

		// Combine level filter and text pattern
		let entries = store.fetch(options: .init(
			minLevel: .error,
			textPattern: "%\(marker)%User%",
			limit: 100
		))

		#expect(entries.count == 1)
		#expect(entries.allSatisfy { $0.level == .error && $0.text.contains("User") })
	}

	@Test func testLogStoreEmptyFetch() async throws {
		let store = LogStore.shared

		// Fetch with pattern that won't match anything
		let marker = uniqueMarker()
		let entries = store.fetch(options: .init(textPattern: "NOMATCH12345NOMATCH_\(marker)", limit: 100))
		#expect(entries.isEmpty)
	}

	@Test func testLogStoreSpecialCharacters() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()

		let specialMessage = "\(marker) Test with 'quotes' and \"double quotes\" and emoji 🎉 and newline\nand tab\t"
		store.log(specialMessage, level: .info)

		let entries = store.fetch(options: .init(textPattern: "%\(marker)%", limit: 1, newestFirst: true))
		#expect(entries.first?.text == specialMessage)
	}

	@Test func testLogStoreLongMessage() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()

		let longMessage = "\(marker) " + String(repeating: "A", count: 10000)
		store.log(longMessage, level: .info)

		let entries = store.fetch(options: .init(textPattern: "%\(marker)%", limit: 1, newestFirst: true))
		#expect(entries.first?.text == longMessage)
	}

	// MARK: - LogEndpoints Tests

	@Test func testLogEndpointsRouterCreation() async throws {
		let router = LogEndpoints.createRouter()

		#expect(router.registeredPaths.contains("/ingest"))
		#expect(router.registeredPaths.contains("/"))
		#expect(router.registeredPaths.contains("/info"))
		#expect(router.registeredPaths.contains("/clear"))
		#expect(router.registeredPaths.count == 4)
	}

	@Test func testLogEndpointsIngest() async throws {
		let router = LogEndpoints.createRouter()
		let marker = uniqueMarker()

		let request = Request(
			path: "/ingest",
			queryParams: ["text": "\(marker) Test log message", "level": "warning"]
		)
		let response = router.handle(request)

		#expect(response.status == .ok)

		// Verify the response
		let json = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any]
		#expect(json?["success"] as? Bool == true)
		#expect(json?["level"] as? String == "warning")

		// Verify log was stored
		let entries = LogStore.shared.fetch(options: .init(textPattern: "%\(marker)%", limit: 1, newestFirst: true))
		#expect(entries.count >= 1)
		#expect(entries.first?.text == "\(marker) Test log message")
		#expect(entries.first?.level == .warning)
	}

	@Test func testLogEndpointsIngestMissingText() async throws {
		let router = LogEndpoints.createRouter()

		let request = Request(path: "/ingest", queryParams: [:])
		let response = router.handle(request)

		#expect(response.status == .badRequest)
	}

	@Test func testLogEndpointsInfo() async throws {
		let router = LogEndpoints.createRouter()

		let request = Request(path: "/info")
		let response = router.handle(request)

		#expect(response.status == .ok)

		let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
		#expect(json?["sessionId"] != nil)
		#expect(json?["databasePath"] != nil)
		#expect(json?["count"] != nil)
	}

	@Test func testLogEndpointsFetchJSON() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()
		store.log("\(marker) Test for JSON fetch", level: .info)

		let router = LogEndpoints.createRouter()
		let request = Request(path: "/", queryParams: ["format": "json", "limit": "100", "match": "%\(marker)%"])
		let response = router.handle(request)

		#expect(response.status == .ok)
		#expect(response.contentType == .json)

		let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
		#expect(json?["logs"] != nil)
		#expect(json?["count"] != nil)
		#expect(json?["total"] != nil)

		let logs = json?["logs"] as? [[String: Any]]
		#expect(logs?.count == 1)
	}

	@Test func testLogEndpointsFetchJSONL() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()
		store.log("\(marker) Test for JSONL fetch", level: .info)

		let router = LogEndpoints.createRouter()
		let request = Request(path: "/", queryParams: ["format": "jsonl", "limit": "100", "match": "%\(marker)%"])
		let response = router.handle(request)

		#expect(response.status == .ok)
		#expect(response.contentType == .text)

		let body = String(data: response.body, encoding: .utf8) ?? ""
		let lines = body.split(separator: "\n")
		#expect(lines.count >= 1) // At least metadata line

		// First line should be metadata
		if let firstLine = lines.first,
		   let firstJson = try? JSONSerialization.jsonObject(with: Data(firstLine.utf8)) as? [String: Any]
		{
			#expect(firstJson["_meta"] as? Bool == true)
		}

		// Should have metadata + our 1 log entry
		#expect(lines.count == 2)
	}

	@Test func testLogEndpointsClear() async throws {
		let store = LogStore.shared
		let marker = uniqueMarker()
		store.log("\(marker) To be cleared", level: .info)

		let countBefore = store.count()
		#expect(countBefore >= 1)

		let router = LogEndpoints.createRouter()
		let request = Request(path: "/clear")
		let response = router.handle(request)

		#expect(response.status == .ok)
		#expect(store.count() == 0)

		let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
		#expect(json?["success"] as? Bool == true)
		#expect((json?["cleared"] as? Int) ?? 0 >= 1)
	}
}
