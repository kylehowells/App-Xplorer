import Foundation
import Testing
@testable import AppXplorerServer

// MARK: - Root Router Integration Tests

@Test func testRootRouterRegistration() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	#expect(handler.description == "AppXplorer Debug Server")

	// Check that root endpoints are registered
	#expect(handler.registeredPaths.contains("/"))
	#expect(handler.registeredPaths.contains("/info"))
	#expect(handler.registeredPaths.contains("/screenshot"))

	// Check that sub-routers are mounted (verified through routerInfo)
	let info = handler.routerInfo(deep: false)
	let routerPaths = info.routers?.map { $0.path } ?? []
	#expect(routerPaths.contains("/files"))
	#expect(routerPaths.contains("/hierarchy"))
	#expect(routerPaths.contains("/userdefaults"))
	#expect(routerPaths.contains("/permissions"))
	#expect(routerPaths.contains("/interact"))
}

@Test func testRootIndexDeepByDefault() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	// Default (no depth param) should be deep
	let response = handler.handle(Request(path: "/"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	let routers = decoded?["routers"] as? [[String: Any]]
	let filesRouter = routers?.first { ($0["path"] as? String) == "/files" }

	// Deep mode: sub-router should have endpoints
	#expect(filesRouter?["endpoints"] != nil)
}

@Test func testRootIndexShallow() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	let response = handler.handle(Request(path: "/", queryParams: ["depth": "shallow"]))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	let routers = decoded?["routers"] as? [[String: Any]]
	let filesRouter = routers?.first { ($0["path"] as? String) == "/files" }

	// Shallow mode: sub-router should NOT have endpoints
	#expect(filesRouter?["endpoints"] == nil)
	#expect(filesRouter?["endpointCount"] as? Int == 7)
}

@Test func testRootIndexIncludesOwnEndpoints() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	// Even in shallow mode, root endpoints should be included
	let response = handler.handle(Request(path: "/", queryParams: ["depth": "shallow"]))

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	let endpoints = decoded?["endpoints"] as? [[String: Any]]

	#expect(endpoints != nil)
	#expect(endpoints?.count == 3) // /, /info, /screenshot (userdefaults is now a sub-router)

	// Check that index endpoint has its own parameters documented
	let indexEndpoint = endpoints?.first { ($0["path"] as? String) == "/" }
	let params = indexEndpoint?["parameters"] as? [[String: Any]]
	#expect(params != nil)
	#expect(params?.first?["name"] as? String == "depth")
}

@Test func testFilesSubRouterRouting() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	// Test that /files routes work through the main handler
	let tempDir = NSTemporaryDirectory()
	let response = handler.handle(Request(path: "/files/list", queryParams: ["path": tempDir]))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["path"] as? String == tempDir)
}

@Test func testFilesSubRouterIndex() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	// /files/ should return the files router index
	let response = handler.handle(Request(path: "/files/"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["description"] as? String == "Browse and read files from the app's sandbox")
	#expect(decoded?["endpointCount"] as? Int == 7)
}
