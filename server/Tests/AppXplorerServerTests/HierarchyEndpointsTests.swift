import Foundation
import Testing
@testable import AppXplorerServer

// MARK: - Hierarchy Endpoints Tests

@Test func testHierarchyRouterStructure() async throws {
	let hierarchyRouter = HierarchyEndpoints.createRouter()

	#expect(hierarchyRouter.description == "Inspect UIKit view hierarchy, responder chain, and first responder")
	#expect(hierarchyRouter.registeredPaths.contains("/"))
	#expect(hierarchyRouter.registeredPaths.contains("/views"))
	#expect(hierarchyRouter.registeredPaths.contains("/windows"))
	#expect(hierarchyRouter.registeredPaths.contains("/window-scenes"))
	#expect(hierarchyRouter.registeredPaths.contains("/view-controllers"))
	#expect(hierarchyRouter.registeredPaths.contains("/responder-chain"))
	#expect(hierarchyRouter.registeredPaths.contains("/first-responder"))
	#expect(hierarchyRouter.registeredPaths.count == 7)
}

@Test func testHierarchyRouterIndex() async throws {
	let hierarchyRouter = HierarchyEndpoints.createRouter()

	let response = hierarchyRouter.handle(Request(path: "/"))
	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["description"] as? String == "Inspect UIKit view hierarchy, responder chain, and first responder")
	#expect(decoded?["endpointCount"] as? Int == 7)

	let endpoints = decoded?["endpoints"] as? [[String: Any]]
	#expect(endpoints?.count == 7)
}

// MARK: - Views Endpoint Tests

@Test func testViewsEndpointExists() async throws {
	let hierarchyRouter = HierarchyEndpoints.createRouter()

	let info = hierarchyRouter.routerInfo(deep: true)
	let viewsEndpoint = info.endpoints?.first { $0.path == "/views" }

	#expect(viewsEndpoint != nil)
	#expect(viewsEndpoint?.description.contains("view hierarchy") == true)

	// Check parameters are documented
	let params = viewsEndpoint?.parameters
	#expect(params?.count == 6) // window, maxDepth, includeHidden, includePrivate, properties, format

	let windowParam = params?.first { $0.name == "window" }
	#expect(windowParam != nil)

	let maxDepthParam = params?.first { $0.name == "maxDepth" }
	#expect(maxDepthParam != nil)
	#expect(maxDepthParam?.defaultValue == "0")

	let includeHiddenParam = params?.first { $0.name == "includeHidden" }
	#expect(includeHiddenParam != nil)
	#expect(includeHiddenParam?.defaultValue == "false")

	let includePrivateParam = params?.first { $0.name == "includePrivate" }
	#expect(includePrivateParam != nil)
	#expect(includePrivateParam?.defaultValue == "true")

	let propertiesParam = params?.first { $0.name == "properties" }
	#expect(propertiesParam != nil)
	#expect(propertiesParam?.defaultValue == "standard")
}

// MARK: - Windows Endpoint Tests

@Test func testWindowsEndpointExists() async throws {
	let hierarchyRouter = HierarchyEndpoints.createRouter()

	let info = hierarchyRouter.routerInfo(deep: true)
	let windowsEndpoint = info.endpoints?.first { $0.path == "/windows" }

	#expect(windowsEndpoint != nil)
	#expect(windowsEndpoint?.description.contains("windows") == true)

	let params = windowsEndpoint?.parameters
	#expect(params?.count == 1)
	#expect(params?.first?.name == "includeHidden")
}

// MARK: - Window Scenes Endpoint Tests

@Test func testWindowScenesEndpointExists() async throws {
	let hierarchyRouter = HierarchyEndpoints.createRouter()

	let info = hierarchyRouter.routerInfo(deep: true)
	let scenesEndpoint = info.endpoints?.first { $0.path == "/window-scenes" }

	#expect(scenesEndpoint != nil)
	#expect(scenesEndpoint?.description.contains("UIWindowScenes") == true)

	let params = scenesEndpoint?.parameters
	#expect(params?.count == 1)
	#expect(params?.first?.name == "includeWindows")
	#expect(params?.first?.defaultValue == "true")
}

// MARK: - View Controllers Endpoint Tests

@Test func testViewControllersEndpointExists() async throws {
	let hierarchyRouter = HierarchyEndpoints.createRouter()

	let info = hierarchyRouter.routerInfo(deep: true)
	let vcEndpoint = info.endpoints?.first { $0.path == "/view-controllers" }

	#expect(vcEndpoint != nil)
	#expect(vcEndpoint?.description.contains("view controller") == true)

	let params = vcEndpoint?.parameters
	#expect(params?.count == 2)

	let windowParam = params?.first { $0.name == "window" }
	#expect(windowParam != nil)

	let maxDepthParam = params?.first { $0.name == "maxDepth" }
	#expect(maxDepthParam != nil)
}

// MARK: - Responder Chain Endpoint Tests

@Test func testResponderChainEndpointExists() async throws {
	let hierarchyRouter = HierarchyEndpoints.createRouter()

	let info = hierarchyRouter.routerInfo(deep: true)
	let responderEndpoint = info.endpoints?.first { $0.path == "/responder-chain" }

	#expect(responderEndpoint != nil)
	#expect(responderEndpoint?.description.contains("responder chain") == true)

	let params = responderEndpoint?.parameters
	#expect(params?.count == 1)
	#expect(params?.first?.name == "from")
	#expect(params?.first?.defaultValue == "first-responder")
}

// MARK: - First Responder Endpoint Tests

@Test func testFirstResponderEndpointExists() async throws {
	let hierarchyRouter = HierarchyEndpoints.createRouter()

	let info = hierarchyRouter.routerInfo(deep: true)
	let firstResponderEndpoint = info.endpoints?.first { $0.path == "/first-responder" }

	#expect(firstResponderEndpoint != nil)
	#expect(firstResponderEndpoint?.description.contains("first responder") == true)

	let params = firstResponderEndpoint?.parameters
	#expect(params?.count == 1)
	#expect(params?.first?.name == "includeProperties")
	#expect(params?.first?.defaultValue == "true")
}

// MARK: - Non-UIKit Tests

#if !canImport(UIKit)
	@Test func testViewsNotAvailableOnMacOS() async throws {
		let hierarchyRouter = HierarchyEndpoints.createRouter()

		let response = hierarchyRouter.handle(Request(path: "/views"))

		#expect(response.status == .badRequest)

		let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: String]
		#expect(decoded?["error"]?.contains("only available on iOS") == true)
	}

	@Test func testWindowsNotAvailableOnMacOS() async throws {
		let hierarchyRouter = HierarchyEndpoints.createRouter()

		let response = hierarchyRouter.handle(Request(path: "/windows"))

		#expect(response.status == .badRequest)
	}

	@Test func testWindowScenesNotAvailableOnMacOS() async throws {
		let hierarchyRouter = HierarchyEndpoints.createRouter()

		let response = hierarchyRouter.handle(Request(path: "/window-scenes"))

		#expect(response.status == .badRequest)
	}

	@Test func testViewControllersNotAvailableOnMacOS() async throws {
		let hierarchyRouter = HierarchyEndpoints.createRouter()

		let response = hierarchyRouter.handle(Request(path: "/view-controllers"))

		#expect(response.status == .badRequest)
	}

	@Test func testResponderChainNotAvailableOnMacOS() async throws {
		let hierarchyRouter = HierarchyEndpoints.createRouter()

		let response = hierarchyRouter.handle(Request(path: "/responder-chain"))

		#expect(response.status == .badRequest)
	}

	@Test func testFirstResponderNotAvailableOnMacOS() async throws {
		let hierarchyRouter = HierarchyEndpoints.createRouter()

		let response = hierarchyRouter.handle(Request(path: "/first-responder"))

		#expect(response.status == .badRequest)
	}
#endif

// MARK: - Root Router Integration Tests

@Test func testHierarchyMountedAsSubRouter() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	// Check that /hierarchy routes work through the main handler
	let response = handler.handle(Request(path: "/hierarchy/"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["description"] as? String == "Inspect UIKit view hierarchy, responder chain, and first responder")
}

@Test func testHierarchyInRootIndex() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	let response = handler.handle(Request(path: "/"))

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	let routers = decoded?["routers"] as? [[String: Any]]

	let hierarchyRouter = routers?.first { ($0["path"] as? String) == "/hierarchy" }
	#expect(hierarchyRouter != nil)
	#expect(hierarchyRouter?["description"] as? String == "Inspect UIKit view hierarchy, responder chain, and first responder")
	#expect(hierarchyRouter?["endpointCount"] as? Int == 7)
}
