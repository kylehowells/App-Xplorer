import Foundation
import Testing
@testable import AppXplorerServer

// MARK: - RequestHandler Tests

@Test func testRequestHandlerRouteRegistration() async throws {
	let handler = RequestHandler()

	handler.register("/test") { _ in
		return .text("test response")
	}

	#expect(handler.registeredPaths.contains("/test"))
}

@Test func testRequestHandlerSubscriptRegistration() async throws {
	let handler = RequestHandler()

	handler["/subscript"] = { _ in
		return .text("subscript response")
	}

	#expect(handler.registeredPaths.contains("/subscript"))
}

@Test func testRequestHandlerRouteExecution() async throws {
	let handler = RequestHandler()

	handler["/hello"] = { _ in
		return .json(["message": "Hello, World!"])
	}

	let request = Request(path: "/hello")
	let response = handler.handle(request)

	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: String]
	#expect(decoded?["message"] == "Hello, World!")
}

@Test func testRequestHandlerQueryParams() async throws {
	let handler = RequestHandler()

	handler["/greet"] = { request in
		let name = request.queryParams["name"] ?? "Guest"
		return .json(["greeting": "Hello, \(name)!"])
	}

	let request = Request(path: "/greet", queryParams: ["name": "Kyle"])
	let response = handler.handle(request)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: String]
	#expect(decoded?["greeting"] == "Hello, Kyle!")
}

@Test func testRequestHandlerNotFound() async throws {
	let handler = RequestHandler()

	let request = Request(path: "/nonexistent")
	let response = handler.handle(request)

	#expect(response.status == .notFound)
}

@Test func testRequestHandlerCustomNotFoundHandler() async throws {
	let handler = RequestHandler()

	handler.setNotFoundHandler { request in
		return .json(["error": "Custom 404", "path": request.path], status: .notFound)
	}

	let request = Request(path: "/missing")
	let response = handler.handle(request)

	#expect(response.status == .notFound)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: String]
	#expect(decoded?["error"] == "Custom 404")
	#expect(decoded?["path"] == "/missing")
}

@Test func testRequestHandlerTrailingSlashNormalization() async throws {
	let handler = RequestHandler()

	handler["/api/users"] = { _ in
		return .json(["users": []])
	}

	// Request with trailing slash should still match
	let request = Request(path: "/api/users/")
	let response = handler.handle(request)

	#expect(response.status == .ok)
}

@Test func testRequestHandlerMultipleRoutes() async throws {
	let handler = RequestHandler()

	handler["/one"] = { _ in .text("one") }
	handler["/two"] = { _ in .text("two") }
	handler["/three"] = { _ in .text("three") }

	#expect(handler.registeredPaths.count == 3)

	let response1 = handler.handle(Request(path: "/one"))
	let response2 = handler.handle(Request(path: "/two"))
	let response3 = handler.handle(Request(path: "/three"))

	#expect(String(data: response1.body, encoding: .utf8) == "one")
	#expect(String(data: response2.body, encoding: .utf8) == "two")
	#expect(String(data: response3.body, encoding: .utf8) == "three")
}

@Test func testRequestHandlerRouteRemoval() async throws {
	let handler = RequestHandler()

	handler["/temporary"] = { _ in .text("temp") }
	#expect(handler.registeredPaths.contains("/temporary"))

	handler["/temporary"] = nil
	#expect(!handler.registeredPaths.contains("/temporary"))

	let response = handler.handle(Request(path: "/temporary"))
	#expect(response.status == .notFound)
}

// MARK: - Sub-Router Tests

@Test func testSubRouterMounting() async throws {
	let mainHandler = RequestHandler()
	mainHandler.description = "Main Router"

	let subRouter = RequestHandler()
	subRouter.description = "Sub Router"
	subRouter["/list"] = { _ in .json(["items": []]) }
	subRouter["/detail"] = { _ in .json(["id": 1]) }

	mainHandler.mount("/api", router: subRouter)

	// Test routing to sub-router
	let listResponse = mainHandler.handle(Request(path: "/api/list"))
	#expect(listResponse.status == .ok)

	let detailResponse = mainHandler.handle(Request(path: "/api/detail"))
	#expect(detailResponse.status == .ok)

	// Test that non-existent sub-route returns not found
	let notFoundResponse = mainHandler.handle(Request(path: "/api/nonexistent"))
	#expect(notFoundResponse.status == .notFound)
}

@Test func testSubRouterBasePath() async throws {
	let mainHandler = RequestHandler()
	let subRouter = RequestHandler()
	subRouter.description = "Files Router"

	mainHandler.mount("/files", router: subRouter)

	#expect(subRouter.basePath == "/files")
}

@Test func testTotalEndpointCount() async throws {
	let mainHandler = RequestHandler()
	mainHandler["/root1"] = { _ in .text("root1") }
	mainHandler["/root2"] = { _ in .text("root2") }

	let subRouter = RequestHandler()
	subRouter["/sub1"] = { _ in .text("sub1") }
	subRouter["/sub2"] = { _ in .text("sub2") }
	subRouter["/sub3"] = { _ in .text("sub3") }

	mainHandler.mount("/api", router: subRouter)

	#expect(mainHandler.totalEndpointCount == 5)
}

// MARK: - Router Info Tests

@Test func testRouterInfoShallow() async throws {
	let mainHandler = RequestHandler()
	mainHandler.description = "Test Server"
	mainHandler.register("/info", description: "Get info") { _ in .json(["info": true]) }

	let subRouter = RequestHandler()
	subRouter.description = "API Router"
	subRouter.register("/users", description: "List users") { _ in .json([]) }
	subRouter.register("/posts", description: "List posts") { _ in .json([]) }

	mainHandler.mount("/api", router: subRouter)

	let info = mainHandler.routerInfo(deep: false)

	#expect(info.path == "/")
	#expect(info.description == "Test Server")
	#expect(info.endpointCount == 3)

	// Endpoints should always be included
	#expect(info.endpoints != nil)
	#expect(info.endpoints?.count == 1)
	#expect(info.endpoints?.first?.path == "/info")

	// Sub-routers should be summaries only (no endpoints)
	#expect(info.routers != nil)
	#expect(info.routers?.count == 1)
	#expect(info.routers?.first?.path == "/api")
	#expect(info.routers?.first?.description == "API Router")
	#expect(info.routers?.first?.endpointCount == 2)
	#expect(info.routers?.first?.endpoints == nil) // Shallow = no sub-router endpoints
}

@Test func testRouterInfoDeep() async throws {
	let mainHandler = RequestHandler()
	mainHandler.description = "Test Server"
	mainHandler.register("/info", description: "Get info") { _ in .json(["info": true]) }

	let subRouter = RequestHandler()
	subRouter.description = "API Router"
	subRouter.register("/users", description: "List users") { _ in .json([]) }
	subRouter.register("/posts", description: "List posts") { _ in .json([]) }

	mainHandler.mount("/api", router: subRouter)

	let info = mainHandler.routerInfo(deep: true)

	#expect(info.path == "/")
	#expect(info.endpoints != nil)
	#expect(info.endpoints?.count == 1)

	// Sub-routers should include full endpoint details
	#expect(info.routers != nil)
	#expect(info.routers?.count == 1)
	#expect(info.routers?.first?.endpoints != nil) // Deep = includes sub-router endpoints
	#expect(info.routers?.first?.endpoints?.count == 2)
}

@Test func testEndpointInfoWithParameters() async throws {
	let handler = RequestHandler()

	handler.register(
		"/search",
		description: "Search items",
		parameters: [
			ParameterInfo(
				name: "query",
				description: "Search query",
				required: true
			),
			ParameterInfo(
				name: "limit",
				description: "Max results",
				required: false,
				defaultValue: "10",
				examples: ["5", "10", "20"]
			),
		]
	) { _ in .json([]) }

	let info = handler.routerInfo(deep: true)

	#expect(info.endpoints?.count == 1)

	let endpoint = info.endpoints?.first
	#expect(endpoint?.path == "/search")
	#expect(endpoint?.description == "Search items")
	#expect(endpoint?.parameters?.count == 2)

	let queryParam = endpoint?.parameters?.first { $0.name == "query" }
	#expect(queryParam?.required == true)
	#expect(queryParam?.description == "Search query")

	let limitParam = endpoint?.parameters?.first { $0.name == "limit" }
	#expect(limitParam?.required == false)
	#expect(limitParam?.defaultValue == "10")
	#expect(limitParam?.examples?.contains("10") == true)
}
