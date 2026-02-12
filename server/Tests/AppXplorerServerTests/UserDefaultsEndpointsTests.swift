import Foundation
import Testing
@testable import AppXplorerServer

// MARK: - UserDefaults Endpoints Tests

@Test func testUserDefaultsRouterStructure() async throws {
	let router = UserDefaultsEndpoints.createRouter()

	#expect(router.description == "Access and inspect NSUserDefaults data")

	// Check all expected paths are registered
	#expect(router.registeredPaths.contains("/"))
	#expect(router.registeredPaths.contains("/all"))
	#expect(router.registeredPaths.contains("/get"))
	#expect(router.registeredPaths.contains("/keys"))
	#expect(router.registeredPaths.contains("/search"))
	#expect(router.registeredPaths.contains("/suites"))
	#expect(router.registeredPaths.contains("/domains"))
	#expect(router.registeredPaths.contains("/domain"))
	#expect(router.registeredPaths.contains("/volatile"))
	#expect(router.registeredPaths.contains("/types"))
}

@Test func testUserDefaultsRouterIndex() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["description"] as? String == "Access and inspect NSUserDefaults data")
	#expect(decoded?["endpointCount"] as? Int == 10)
}

@Test func testUserDefaultsMountedAsSubRouter() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	let info = handler.routerInfo(deep: false)
	let routerPaths = info.routers?.map { $0.path } ?? []

	#expect(routerPaths.contains("/userdefaults"))
}

@Test func testUserDefaultsInRootIndex() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	let response = handler.handle(Request(path: "/", queryParams: ["depth": "shallow"]))
	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	let routers = decoded?["routers"] as? [[String: Any]]

	let userDefaultsRouter = routers?.first { ($0["path"] as? String) == "/userdefaults" }
	#expect(userDefaultsRouter != nil)
	#expect(userDefaultsRouter?["description"] as? String == "Access and inspect NSUserDefaults data")
	#expect(userDefaultsRouter?["endpointCount"] as? Int == 10)
}

// MARK: - /all Endpoint Tests

@Test func testUserDefaultsAllEndpoint() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/all"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["suite"] as? String == "standard")
	#expect(decoded?["items"] != nil)
	#expect(decoded?["count"] as? Int != nil)
}

@Test func testUserDefaultsAllWithFilterSystem() async throws {
	let router = UserDefaultsEndpoints.createRouter()

	// Without filter
	let responseNoFilter = router.handle(Request(path: "/all"))
	let decodedNoFilter = try JSONSerialization.jsonObject(with: responseNoFilter.body) as? [String: Any]
	let countNoFilter = decodedNoFilter?["count"] as? Int ?? 0

	// With filter
	let responseFiltered = router.handle(Request(path: "/all", queryParams: ["filterSystem": "true"]))
	let decodedFiltered = try JSONSerialization.jsonObject(with: responseFiltered.body) as? [String: Any]
	let countFiltered = decodedFiltered?["count"] as? Int ?? 0

	// Filtered should have fewer or equal items
	#expect(countFiltered <= countNoFilter)
}

// MARK: - /get Endpoint Tests

@Test func testUserDefaultsGetMissingKey() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/get"))

	#expect(response.status == .badRequest)
}

@Test func testUserDefaultsGetNonExistentKey() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/get", queryParams: ["key": "nonexistent_key_12345"]))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["key"] as? String == "nonexistent_key_12345")
	#expect(decoded?["exists"] as? Bool == false)
}

// MARK: - /keys Endpoint Tests

@Test func testUserDefaultsKeysEndpoint() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/keys"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["suite"] as? String == "standard")
	#expect(decoded?["keys"] as? [String] != nil)
	#expect(decoded?["count"] as? Int != nil)
}

@Test func testUserDefaultsKeysWithPrefix() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/keys", queryParams: ["prefix": "Apple"]))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	let keys = decoded?["keys"] as? [String] ?? []

	// All keys should start with Apple
	for key in keys {
		#expect(key.hasPrefix("Apple"))
	}
}

@Test func testUserDefaultsKeysWithContains() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/keys", queryParams: ["contains": "Language"]))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	let keys = decoded?["keys"] as? [String] ?? []

	// All keys should contain Language (case insensitive)
	for key in keys {
		#expect(key.localizedCaseInsensitiveContains("Language"))
	}
}

// MARK: - /search Endpoint Tests

@Test func testUserDefaultsSearchMissingQuery() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/search"))

	#expect(response.status == .badRequest)
}

@Test func testUserDefaultsSearchEndpoint() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/search", queryParams: ["query": "Apple"]))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["query"] as? String == "Apple")
	#expect(decoded?["results"] != nil)
	#expect(decoded?["count"] as? Int != nil)
}

// MARK: - /suites Endpoint Tests

@Test func testUserDefaultsSuitesEndpoint() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/suites"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	let suites = decoded?["suites"] as? [[String: Any]]
	#expect(suites != nil)

	// Should have at least the standard suite
	let standardSuite = suites?.first { ($0["name"] as? String) == "standard" }
	#expect(standardSuite != nil)
}

// MARK: - /domains Endpoint Tests

@Test func testUserDefaultsDomainsEndpoint() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/domains"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	let domains = decoded?["domains"] as? [[String: Any]]
	#expect(domains != nil)
	#expect(decoded?["count"] as? Int != nil)
}

// MARK: - /domain Endpoint Tests

@Test func testUserDefaultsDomainMissingName() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/domain"))

	#expect(response.status == .badRequest)
}

@Test func testUserDefaultsDomainNonExistent() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/domain", queryParams: ["name": "nonexistent.domain.12345"]))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["name"] as? String == "nonexistent.domain.12345")
	#expect(decoded?["exists"] as? Bool == false)
}

// MARK: - /volatile Endpoint Tests

@Test func testUserDefaultsVolatileEndpoint() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/volatile"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["volatileDomains"] as? [[String: Any]] != nil)
	#expect(decoded?["count"] as? Int != nil)
}

// MARK: - /types Endpoint Tests

@Test func testUserDefaultsTypesEndpoint() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let response = router.handle(Request(path: "/types"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["suite"] as? String == "standard")
	#expect(decoded?["summary"] as? [[String: Any]] != nil)
	#expect(decoded?["byType"] as? [String: Any] != nil)
	#expect(decoded?["totalCount"] as? Int != nil)
}

// MARK: - Total Endpoint Count Test

@Test func testUserDefaultsTotalEndpointCount() async throws {
	let router = UserDefaultsEndpoints.createRouter()
	let info = router.routerInfo(deep: true)

	// Should have 10 endpoints: /, /all, /get, /keys, /search, /suites, /domains, /domain, /volatile, /types
	#expect(info.endpointCount == 10)
}
