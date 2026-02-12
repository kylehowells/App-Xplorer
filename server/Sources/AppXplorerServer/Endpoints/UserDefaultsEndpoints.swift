import Foundation

// MARK: - UserDefaultsEndpoints

/// UserDefaults inspection endpoints
public enum UserDefaultsEndpoints {
	/// Create a router for UserDefaults endpoints
	public static func createRouter() -> RequestHandler {
		let router: RequestHandler = .init(description: "Access and inspect NSUserDefaults data")

		// Register index for this sub-router
		router.register("/", description: "List all UserDefaults endpoints", runsOnMainThread: false) { _ in
			return .json(router.routerInfo(deep: true))
		}

		self.registerAll(with: router)
		self.registerGet(with: router)
		self.registerKeys(with: router)
		self.registerSearch(with: router)
		self.registerSuites(with: router)
		self.registerDomains(with: router)
		self.registerDomain(with: router)
		self.registerVolatile(with: router)
		self.registerTypes(with: router)

		return router
	}

	// MARK: - Helper Functions

	/// Get UserDefaults for the specified suite
	private static func getDefaults(suite: String?) -> UserDefaults {
		if let suite = suite, !suite.isEmpty, suite != "standard" {
			return UserDefaults(suiteName: suite) ?? UserDefaults.standard
		}
		return UserDefaults.standard
	}

	/// Check if a key is an Apple system key
	private static func isSystemKey(_ key: String) -> Bool {
		return key.hasPrefix("NS") ||
			key.hasPrefix("Apple") ||
			key.hasPrefix("com.apple") ||
			key.hasPrefix("AK") ||
			key.hasPrefix("PKLog") ||
			key.hasPrefix("WebKit") ||
			key.hasPrefix("AddingEmojiKeybordHandled")
	}

	/// Filter keys based on filterSystem flag
	private static func filterKeys(_ dict: [String: Any], filterSystem: Bool) -> [String: Any] {
		if filterSystem {
			return dict.filter { key, _ in !self.isSystemKey(key) }
		}
		return dict
	}

	/// Get a human-readable type name for a value
	private static func typeName(for value: Any) -> String {
		switch value {
			case is String:
				return "String"

			case is Bool:
				// Note: Bool check must come before numeric checks in Swift
				// because Bool conforms to numeric protocols
				return "Bool"

			case is Int, is Int8, is Int16, is Int32, is Int64,
			     is UInt, is UInt8, is UInt16, is UInt32, is UInt64:
				return "Integer"

			case is Float, is Double:
				return "Float"

			case is Date:
				return "Date"

			case is Data:
				return "Data"

			case is [Any]:
				return "Array"

			case is [String: Any]:
				return "Dictionary"

			default:
				return String(describing: type(of: value))
		}
	}

	/// Serialize a value for JSON output
	private static func serializeValue(_ value: Any) -> Any {
		switch value {
			case let date as Date:
				return ISO8601DateFormatter().string(from: date)

			case let data as Data:
				return [
					"_type": "Data",
					"base64": data.base64EncodedString(),
					"size": data.count,
				]

			case let array as [Any]:
				return array.map { self.serializeValue($0) }

			case let dict as [String: Any]:
				return dict.mapValues { self.serializeValue($0) }

			default:
				return value
		}
	}

	/// Serialize an entire dictionary for JSON output
	private static func serializeDict(_ dict: [String: Any]) -> [String: Any] {
		return dict.mapValues { self.serializeValue($0) }
	}

	// MARK: - All

	private static func registerAll(with handler: RequestHandler) {
		handler.register(
			"/all",
			description: "List all key-value pairs from UserDefaults. Returns the complete contents of the specified suite.",
			parameters: [
				ParameterInfo(
					name: "suite",
					description: "UserDefaults suite name (e.g., app group identifier)",
					required: false,
					defaultValue: "standard",
					examples: ["group.com.example.app"]
				),
				ParameterInfo(
					name: "filterSystem",
					description: "Filter out Apple system keys (NS*, Apple*, com.apple.*, AK*, etc.)",
					required: false,
					defaultValue: "false",
					examples: ["true", "false"]
				),
				ParameterInfo(
					name: "sort",
					description: "Sort keys alphabetically",
					required: false,
					defaultValue: "asc",
					examples: ["asc", "desc", "none"]
				),
			],
			runsOnMainThread: false
		) { request in
			let defaults: UserDefaults = self.getDefaults(suite: request.queryParams["suite"])
			let filterSystem: Bool = request.queryParams["filterSystem"] == "true"
			let sort: String = request.queryParams["sort"] ?? "asc"

			var dict: [String: Any] = defaults.dictionaryRepresentation()
			dict = self.filterKeys(dict, filterSystem: filterSystem)

			// Sort keys if requested
			let sortedKeys: [String]
			switch sort.lowercased() {
				case "desc":
					sortedKeys = dict.keys.sorted(by: >)

				case "none":
					sortedKeys = Array(dict.keys)

				default: // asc
					sortedKeys = dict.keys.sorted()
			}

			// Build ordered result with type info
			var items: [[String: Any]] = []
			for key in sortedKeys {
				if let value = dict[key] {
					items.append([
						"key": key,
						"value": self.serializeValue(value),
						"type": self.typeName(for: value),
					])
				}
			}

			return .json([
				"suite": request.queryParams["suite"] ?? "standard",
				"count": items.count,
				"filterSystem": filterSystem,
				"items": items,
			])
		}
	}

	// MARK: - Get

	private static func registerGet(with handler: RequestHandler) {
		handler.register(
			"/get",
			description: "Get a single key's value from UserDefaults. Returns the value along with its type.",
			parameters: [
				ParameterInfo(
					name: "key",
					description: "The key to look up",
					required: true
				),
				ParameterInfo(
					name: "suite",
					description: "UserDefaults suite name",
					required: false,
					defaultValue: "standard"
				),
			],
			runsOnMainThread: false
		) { request in
			guard let key: String = request.queryParams["key"] else {
				return .error("Missing required parameter: key", status: .badRequest)
			}

			let defaults: UserDefaults = self.getDefaults(suite: request.queryParams["suite"])

			guard let value = defaults.object(forKey: key) else {
				return .json([
					"key": key,
					"exists": false,
					"value": nil as Any?,
					"suite": request.queryParams["suite"] ?? "standard",
				])
			}

			return .json([
				"key": key,
				"exists": true,
				"value": self.serializeValue(value),
				"type": self.typeName(for: value),
				"suite": request.queryParams["suite"] ?? "standard",
			])
		}
	}

	// MARK: - Keys

	private static func registerKeys(with handler: RequestHandler) {
		handler.register(
			"/keys",
			description: "List all key names without values. Useful for exploring what keys exist.",
			parameters: [
				ParameterInfo(
					name: "suite",
					description: "UserDefaults suite name",
					required: false,
					defaultValue: "standard"
				),
				ParameterInfo(
					name: "filterSystem",
					description: "Filter out Apple system keys",
					required: false,
					defaultValue: "false"
				),
				ParameterInfo(
					name: "prefix",
					description: "Only include keys starting with this prefix",
					required: false
				),
				ParameterInfo(
					name: "contains",
					description: "Only include keys containing this substring",
					required: false
				),
				ParameterInfo(
					name: "sort",
					description: "Sort order for keys",
					required: false,
					defaultValue: "asc",
					examples: ["asc", "desc"]
				),
			],
			runsOnMainThread: false
		) { request in
			let defaults: UserDefaults = self.getDefaults(suite: request.queryParams["suite"])
			let filterSystem: Bool = request.queryParams["filterSystem"] == "true"
			let prefix: String? = request.queryParams["prefix"]
			let contains: String? = request.queryParams["contains"]
			let sort: String = request.queryParams["sort"] ?? "asc"

			var keys: [String] = Array(defaults.dictionaryRepresentation().keys)

			// Filter system keys
			if filterSystem {
				keys = keys.filter { !self.isSystemKey($0) }
			}

			// Filter by prefix
			if let prefix = prefix, !prefix.isEmpty {
				keys = keys.filter { $0.hasPrefix(prefix) }
			}

			// Filter by contains
			if let contains = contains, !contains.isEmpty {
				keys = keys.filter { $0.localizedCaseInsensitiveContains(contains) }
			}

			// Sort
			if sort.lowercased() == "desc" {
				keys.sort(by: >)
			}
			else {
				keys.sort()
			}

			return .json([
				"suite": request.queryParams["suite"] ?? "standard",
				"count": keys.count,
				"keys": keys,
			])
		}
	}

	// MARK: - Search

	private static func registerSearch(with handler: RequestHandler) {
		handler.register(
			"/search",
			description: "Search for keys or values matching a query string.",
			parameters: [
				ParameterInfo(
					name: "query",
					description: "Search term to match against keys and/or values",
					required: true
				),
				ParameterInfo(
					name: "searchIn",
					description: "Where to search",
					required: false,
					defaultValue: "both",
					examples: ["keys", "values", "both"]
				),
				ParameterInfo(
					name: "suite",
					description: "UserDefaults suite name",
					required: false,
					defaultValue: "standard"
				),
				ParameterInfo(
					name: "caseSensitive",
					description: "Case-sensitive search",
					required: false,
					defaultValue: "false"
				),
				ParameterInfo(
					name: "filterSystem",
					description: "Filter out Apple system keys from results",
					required: false,
					defaultValue: "true"
				),
			],
			runsOnMainThread: false
		) { request in
			guard let query: String = request.queryParams["query"], !query.isEmpty else {
				return .error("Missing required parameter: query", status: .badRequest)
			}

			let defaults: UserDefaults = self.getDefaults(suite: request.queryParams["suite"])
			let searchIn: String = request.queryParams["searchIn"] ?? "both"
			let caseSensitive: Bool = request.queryParams["caseSensitive"] == "true"
			let filterSystem: Bool = request.queryParams["filterSystem"] != "false"

			var dict: [String: Any] = defaults.dictionaryRepresentation()

			if filterSystem {
				dict = self.filterKeys(dict, filterSystem: true)
			}

			var results: [[String: Any]] = []

			for (key, value) in dict {
				var matched: Bool = false
				var matchLocation: String = ""

				// Search in keys
				if searchIn == "keys" || searchIn == "both" {
					if caseSensitive {
						if key.contains(query) {
							matched = true
							matchLocation = "key"
						}
					}
					else {
						if key.localizedCaseInsensitiveContains(query) {
							matched = true
							matchLocation = "key"
						}
					}
				}

				// Search in values
				if !matched, (searchIn == "values" || searchIn == "both") {
					let stringValue: String = .init(describing: value)
					if caseSensitive {
						if stringValue.contains(query) {
							matched = true
							matchLocation = "value"
						}
					}
					else {
						if stringValue.localizedCaseInsensitiveContains(query) {
							matched = true
							matchLocation = "value"
						}
					}
				}

				if matched {
					results.append([
						"key": key,
						"value": self.serializeValue(value),
						"type": self.typeName(for: value),
						"matchedIn": matchLocation,
					])
				}
			}

			// Sort results by key
			results.sort { ($0["key"] as? String ?? "") < ($1["key"] as? String ?? "") }

			return .json([
				"query": query,
				"searchIn": searchIn,
				"caseSensitive": caseSensitive,
				"suite": request.queryParams["suite"] ?? "standard",
				"count": results.count,
				"results": results,
			])
		}
	}

	// MARK: - Suites

	private static func registerSuites(with handler: RequestHandler) {
		handler.register(
			"/suites",
			description: "List known UserDefaults suites. Shows standard suite and any accessible app group containers.",
			runsOnMainThread: false
		) { _ in
			var suites: [[String: Any]] = []

			// Standard suite
			suites.append([
				"name": "standard",
				"description": "Standard UserDefaults",
				"keyCount": UserDefaults.standard.dictionaryRepresentation().count,
			])

			// Try to find app group containers
			let fileManager: FileManager = .default
			if let groupContainers: URL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "") {
				// This won't actually work without a real group ID, but shows the pattern
				_ = groupContainers
			}

			// Get persistent domains as potential suites
			if let bundleId: String = Bundle.main.bundleIdentifier {
				suites.append([
					"name": bundleId,
					"description": "App bundle domain",
					"type": "persistentDomain",
				])
			}

			return .json([
				"suites": suites,
				"note": "Use the 'suite' parameter with other endpoints to access different suites",
			])
		}
	}

	// MARK: - Domains

	private static func registerDomains(with handler: RequestHandler) {
		handler.register(
			"/domains",
			description: "List known persistent domains. Shows the app's bundle domain and any detected domains.",
			runsOnMainThread: false
		) { _ in
			var domainInfo: [[String: Any]] = []

			// Add app bundle domain
			if let bundleId: String = Bundle.main.bundleIdentifier {
				let defaults: UserDefaults = .standard
				if let dict: [String: Any] = defaults.persistentDomain(forName: bundleId) {
					domainInfo.append([
						"name": bundleId,
						"keyCount": dict.count,
						"type": "app",
					])
				}
				else {
					domainInfo.append([
						"name": bundleId,
						"keyCount": 0,
						"type": "app",
					])
				}
			}

			// Add global domain
			let globalDomain: String = UserDefaults.globalDomain
			domainInfo.append([
				"name": globalDomain,
				"description": "System-wide defaults",
				"type": "global",
			])

			// Add registration domain (where registerDefaults: are stored)
			let registrationDomain: String = UserDefaults.registrationDomain
			domainInfo.append([
				"name": registrationDomain,
				"description": "Registered default values",
				"type": "registration",
			])

			// Add arguments domain (command-line arguments)
			let argumentsDomain: String = UserDefaults.argumentDomain
			domainInfo.append([
				"name": argumentsDomain,
				"description": "Command-line argument defaults",
				"type": "arguments",
			])

			return .json([
				"count": domainInfo.count,
				"domains": domainInfo,
				"note": "Use /domain?name=<domain> to view contents of a specific domain",
			])
		}
	}

	// MARK: - Domain

	private static func registerDomain(with handler: RequestHandler) {
		handler.register(
			"/domain",
			description: "Get the contents of a specific persistent domain.",
			parameters: [
				ParameterInfo(
					name: "name",
					description: "Domain name (e.g., bundle identifier)",
					required: true
				),
				ParameterInfo(
					name: "filterSystem",
					description: "Filter out Apple system keys",
					required: false,
					defaultValue: "false"
				),
			],
			runsOnMainThread: false
		) { request in
			guard let name: String = request.queryParams["name"] else {
				return .error("Missing required parameter: name", status: .badRequest)
			}

			let defaults: UserDefaults = .standard
			let filterSystem: Bool = request.queryParams["filterSystem"] == "true"

			guard var dict: [String: Any] = defaults.persistentDomain(forName: name) else {
				return .json([
					"name": name,
					"exists": false,
					"count": 0,
					"items": [] as [Any],
				])
			}

			dict = self.filterKeys(dict, filterSystem: filterSystem)

			let sortedKeys: [String] = dict.keys.sorted()
			var items: [[String: Any]] = []
			for key in sortedKeys {
				if let value = dict[key] {
					items.append([
						"key": key,
						"value": self.serializeValue(value),
						"type": self.typeName(for: value),
					])
				}
			}

			return .json([
				"name": name,
				"exists": true,
				"count": items.count,
				"items": items,
			])
		}
	}

	// MARK: - Volatile

	private static func registerVolatile(with handler: RequestHandler) {
		handler.register(
			"/volatile",
			description: "List volatile domain names. Volatile domains contain temporary values that are not persisted to disk.",
			runsOnMainThread: false
		) { _ in
			let defaults: UserDefaults = .standard
			let volatileNames: [String] = defaults.volatileDomainNames

			var domains: [[String: Any]] = []
			for name in volatileNames {
				let dict: [String: Any] = defaults.volatileDomain(forName: name)
				domains.append([
					"name": name,
					"keyCount": dict.count,
				])
			}

			// Sort by name
			domains.sort { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }

			return .json([
				"count": domains.count,
				"volatileDomains": domains,
				"note": "Volatile domains contain temporary values not persisted to disk",
			])
		}
	}

	// MARK: - Types

	private static func registerTypes(with handler: RequestHandler) {
		handler.register(
			"/types",
			description: "Group all keys by their value types. Useful for understanding the data structure.",
			parameters: [
				ParameterInfo(
					name: "suite",
					description: "UserDefaults suite name",
					required: false,
					defaultValue: "standard"
				),
				ParameterInfo(
					name: "filterSystem",
					description: "Filter out Apple system keys",
					required: false,
					defaultValue: "true"
				),
			],
			runsOnMainThread: false
		) { request in
			let defaults: UserDefaults = self.getDefaults(suite: request.queryParams["suite"])
			let filterSystem: Bool = request.queryParams["filterSystem"] != "false"

			var dict: [String: Any] = defaults.dictionaryRepresentation()
			dict = self.filterKeys(dict, filterSystem: filterSystem)

			// Group by type
			var typeGroups: [String: [[String: Any]]] = [:]

			for (key, value) in dict {
				let type: String = self.typeName(for: value)

				if typeGroups[type] == nil {
					typeGroups[type] = []
				}

				typeGroups[type]?.append([
					"key": key,
					"value": self.serializeValue(value),
				])
			}

			// Sort keys within each group
			for type in typeGroups.keys {
				typeGroups[type]?.sort { ($0["key"] as? String ?? "") < ($1["key"] as? String ?? "") }
			}

			// Build summary
			var summary: [[String: Any]] = []
			for (type, items) in typeGroups.sorted(by: { $0.key < $1.key }) {
				summary.append([
					"type": type,
					"count": items.count,
				])
			}

			return .json([
				"suite": request.queryParams["suite"] ?? "standard",
				"totalCount": dict.count,
				"summary": summary,
				"byType": typeGroups,
			])
		}
	}
}
