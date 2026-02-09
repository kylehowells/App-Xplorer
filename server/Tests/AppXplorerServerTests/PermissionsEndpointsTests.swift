import Foundation
import Testing
@testable import AppXplorerServer

// MARK: - Permissions Endpoints Tests

@Test func testPermissionsRouterStructure() async throws {
	let router: RequestHandler = PermissionsEndpoints.createRouter()

	#expect(router.registeredPaths.contains("/"))
	#expect(router.registeredPaths.contains("/all"))
	#expect(router.registeredPaths.contains("/list"))
	#expect(router.registeredPaths.contains("/get"))
	#expect(router.registeredPaths.contains("/refresh"))
	#expect(router.registeredPaths.count == 5)
}

@Test func testPermissionsRouterIndex() async throws {
	let router: RequestHandler = PermissionsEndpoints.createRouter()

	let response = router.handle(Request(path: "/"))

	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["endpoints"] != nil)
}

@Test func testPermissionsListEndpoint() async throws {
	let router: RequestHandler = PermissionsEndpoints.createRouter()

	let response = router.handle(Request(path: "/list"))

	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]

	#expect(decoded?["count"] != nil)
	#expect(decoded?["types"] != nil)

	// Should list all supported permission types
	if let types = decoded?["types"] as? [[String: Any]] {
		#expect(types.count == 15) // 15 permission types defined

		// Check that each type has required fields
		for type in types {
			#expect(type["type"] != nil)
			#expect(type["displayName"] != nil)
			#expect(type["framework"] != nil)
			#expect(type["detectionClass"] != nil)
		}

		// Check some specific types exist
		let typeNames: [String] = types.compactMap { $0["type"] as? String }
		#expect(typeNames.contains("photos"))
		#expect(typeNames.contains("camera"))
		#expect(typeNames.contains("contacts"))
		#expect(typeNames.contains("location"))
		#expect(typeNames.contains("notifications"))
	}
}

@Test func testPermissionsAllEndpoint() async throws {
	let router: RequestHandler = PermissionsEndpoints.createRouter()

	let response = router.handle(Request(path: "/all"))

	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]

	#expect(decoded?["count"] != nil)
	#expect(decoded?["permissions"] != nil)
	#expect(decoded?["timestamp"] != nil)
	#expect(decoded?["summary"] != nil)

	// Check permissions array
	if let permissions = decoded?["permissions"] as? [[String: Any]] {
		#expect(permissions.count == 15)

		// Each permission should have required fields
		for perm in permissions {
			#expect(perm["type"] != nil)
			#expect(perm["displayName"] != nil)
			#expect(perm["status"] != nil)
			#expect(perm["description"] != nil)
			#expect(perm["framework"] != nil)
		}
	}

	// Check summary counts
	if let summary = decoded?["summary"] as? [String: Int] {
		// On macOS test environment, most frameworks won't be linked
		// so we expect most to show "not_linked"
		#expect(summary.values.reduce(0, +) == 15) // Total should equal permission count
	}
}

@Test func testPermissionsGetEndpoint() async throws {
	let router: RequestHandler = PermissionsEndpoints.createRouter()

	let response = router.handle(Request(path: "/get", queryParams: ["type": "photos"]))

	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]

	#expect(decoded?["type"] as? String == "photos")
	#expect(decoded?["displayName"] as? String == "Photos")
	#expect(decoded?["framework"] as? String == "Photos")
	#expect(decoded?["status"] != nil)
	#expect(decoded?["description"] != nil)
	#expect(decoded?["timestamp"] != nil)
}

@Test func testPermissionsGetMissingType() async throws {
	let router: RequestHandler = PermissionsEndpoints.createRouter()

	let response = router.handle(Request(path: "/get"))

	#expect(response.status == .badRequest)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: String]
	#expect(decoded?["error"]?.contains("Missing required parameter: type") == true)
}

@Test func testPermissionsGetInvalidType() async throws {
	let router: RequestHandler = PermissionsEndpoints.createRouter()

	let response = router.handle(Request(path: "/get", queryParams: ["type": "invalid_type"]))

	#expect(response.status == .badRequest)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: String]
	#expect(decoded?["error"]?.contains("Invalid permission type") == true)
	#expect(decoded?["error"]?.contains("Valid types:") == true)
}

@Test func testPermissionsGetCaseInsensitive() async throws {
	let router: RequestHandler = PermissionsEndpoints.createRouter()

	// Test uppercase
	let response1 = router.handle(Request(path: "/get", queryParams: ["type": "PHOTOS"]))
	#expect(response1.status == .ok)

	// Test mixed case
	let response2 = router.handle(Request(path: "/get", queryParams: ["type": "Photos"]))
	#expect(response2.status == .ok)

	// Test lowercase
	let response3 = router.handle(Request(path: "/get", queryParams: ["type": "photos"]))
	#expect(response3.status == .ok)
}

@Test func testPermissionsGetAllTypes() async throws {
	let router: RequestHandler = PermissionsEndpoints.createRouter()

	// Test each permission type (all lowercase to match enum rawValue)
	let types: [String] = [
		"photos", "camera", "microphone", "contacts", "calendar",
		"reminders", "location", "notifications", "health", "motion",
		"speech", "bluetooth", "homekit", "medialibrary", "siri",
	]

	for type in types {
		let response = router.handle(Request(path: "/get", queryParams: ["type": type]))
		#expect(response.status == .ok, "Failed for type: \(type)")

		let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
		#expect(decoded?["type"] as? String == type, "Type mismatch for: \(type)")
		#expect(decoded?["status"] != nil, "Missing status for: \(type)")
	}
}

@Test func testPermissionsInRootIndex() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	let response = handler.handle(Request(path: "/"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	let routers = decoded?["routers"] as? [[String: Any]]

	// Find permissions sub-router
	let permissionsRouter = routers?.first { ($0["path"] as? String) == "/permissions" }
	#expect(permissionsRouter != nil)
	#expect(permissionsRouter?["description"] as? String == "Inspect system permission states")
}

@Test func testPermissionsMountedAsSubRouter() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	// Should be able to access via mounted path
	let response = handler.handle(Request(path: "/permissions/list"))

	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["types"] != nil)
}

@Test func testPermissionsTotalEndpointCount() async throws {
	let router: RequestHandler = PermissionsEndpoints.createRouter()
	let info = router.routerInfo(deep: true)

	// 5 endpoints: /, /all, /list, /get, /refresh
	#expect(info.endpoints?.count == 5)
}

@Test func testPermissionsGetEndpointParameters() async throws {
	let router: RequestHandler = PermissionsEndpoints.createRouter()
	let info = router.routerInfo(deep: true)

	// Find /get endpoint
	let getEndpoint = info.endpoints?.first { $0.path == "/get" }
	#expect(getEndpoint != nil)
	#expect(getEndpoint?.parameters?.count == 1)

	let typeParam = getEndpoint?.parameters?.first { $0.name == "type" }
	#expect(typeParam != nil)
	#expect(typeParam?.required == true)
	#expect(typeParam?.examples?.isEmpty == false)
}

@Test func testPermissionsRefreshEndpoint() async throws {
	let router: RequestHandler = PermissionsEndpoints.createRouter()

	let response = router.handle(Request(path: "/refresh"))

	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]

	#expect(decoded?["message"] != nil)
	#expect(decoded?["refreshing"] != nil)
	#expect(decoded?["timestamp"] != nil)

	// Check refreshing array contains async permissions
	if let refreshing = decoded?["refreshing"] as? [[String: Any]] {
		// Should have at least notifications and siri as async
		#expect(refreshing.count >= 2)

		for perm in refreshing {
			#expect(perm["type"] != nil)
			#expect(perm["status"] as? String == "checking")
		}
	}
}

@Test func testPermissionsAllIncludesAsyncInfo() async throws {
	let router: RequestHandler = PermissionsEndpoints.createRouter()

	let response = router.handle(Request(path: "/all"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]

	// Should include async-related fields
	#expect(decoded?["asyncNeedingRefresh"] != nil)

	// Check permissions include isAsync field
	if let permissions = decoded?["permissions"] as? [[String: Any]] {
		for perm in permissions {
			#expect(perm["isAsync"] != nil, "Missing isAsync field for permission")
		}
	}
}

// MARK: - Framework Detection Tests (macOS specific)

#if !canImport(UIKit)
	@Test func testPermissionsNotLinkedOnMacOS() async throws {
		let router: RequestHandler = PermissionsEndpoints.createRouter()

		// On macOS, most iOS frameworks aren't linked
		let response = router.handle(Request(path: "/get", queryParams: ["type": "photos"]))

		#expect(response.status == .ok)

		let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]

		// PHPhotoLibrary should not be available on macOS test environment
		let status = decoded?["status"] as? String
		#expect(status == "not_linked" || status == "unknown")
	}

	@Test func testPermissionsSummaryOnMacOS() async throws {
		let router: RequestHandler = PermissionsEndpoints.createRouter()

		let response = router.handle(Request(path: "/all"))

		#expect(response.status == .ok)

		let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
		let summary = decoded?["summary"] as? [String: Int]

		// Most should be not_linked on macOS
		let notLinkedCount: Int = summary?["not_linked"] ?? 0
		#expect(notLinkedCount > 0)
	}
#endif
