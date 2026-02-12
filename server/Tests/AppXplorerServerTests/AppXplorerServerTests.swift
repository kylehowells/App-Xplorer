import Foundation
import Testing

@testable import AppXplorerServer

// MARK: - AppXplorerServer Public API Tests

@Suite("AppXplorerServer Public API Tests")
struct AppXplorerServerPublicAPITests {
	// MARK: - Register with Full Parameters

	@Test("Register endpoint with full parameters")
	func testRegisterWithFullParameters() {
		let server = AppXplorerServer()

		server.register(
			"/custom/test",
			description: "Test endpoint for custom routes",
			parameters: [
				ParameterInfo(
					name: "format",
					description: "Output format",
					required: false,
					defaultValue: "json"
				)
			],
			runsOnMainThread: false
		) { _ in
			return .json(["status": "ok"])
		}

		// Verify the endpoint is registered and works
		let request = Request(path: "/custom/test", queryParams: [:])
		let response = server.requestHandler.handle(request)

		#expect(response.status == .ok)
	}

	@Test("Register endpoint appears in API discovery")
	func testRegisteredEndpointInDiscovery() {
		let server = AppXplorerServer()

		server.register(
			"/custom/user",
			description: "Get user information",
			parameters: [
				ParameterInfo(name: "include_email", description: "Include email address")
			]
		) { _ in
			return .json(["name": "Test User"])
		}

		// Check API discovery
		let routerInfo = server.requestHandler.routerInfo(deep: true)

		// Find our custom endpoint
		let customEndpoint = routerInfo.endpoints?.first { $0.path == "/custom/user" }
		#expect(customEndpoint != nil)
		#expect(customEndpoint?.description == "Get user information")
		#expect(customEndpoint?.parameters?.count == 1)
		#expect(customEndpoint?.parameters?.first?.name == "include_email")
	}

	// MARK: - Mount Custom Router

	@Test("Mount custom sub-router")
	func testMountCustomRouter() {
		let server = AppXplorerServer()

		// Create a custom router
		let customRouter = RequestHandler(description: "Custom user endpoints")

		customRouter.register(
			"/profile",
			description: "Get user profile"
		) { _ in
			return .json(["name": "John Doe"])
		}

		customRouter.register(
			"/settings",
			description: "Get user settings"
		) { _ in
			return .json(["theme": "dark"])
		}

		// Mount it
		server.mount("/user", router: customRouter)

		// Test that routes work
		let profileRequest = Request(path: "/user/profile", queryParams: [:])
		let profileResponse = server.requestHandler.handle(profileRequest)
		#expect(profileResponse.status == .ok)

		let settingsRequest = Request(path: "/user/settings", queryParams: [:])
		let settingsResponse = server.requestHandler.handle(settingsRequest)
		#expect(settingsResponse.status == .ok)
	}

	@Test("Mounted router appears in API discovery")
	func testMountedRouterInDiscovery() {
		let server = AppXplorerServer()

		let customRouter = RequestHandler(description: "Account management endpoints")
		customRouter.register("/info", description: "Get account info") { _ in
			return .json([:])
		}

		server.mount("/account", router: customRouter)

		// Check API discovery at root level
		let routerInfo = server.requestHandler.routerInfo(deep: true)

		// Find the account router
		let accountRouter = routerInfo.routers?.first { $0.path == "/account" }
		#expect(accountRouter != nil)
		#expect(accountRouter?.description == "Account management endpoints")
	}

	// MARK: - Simple Register

	@Test("Register with simple handler")
	func testSimpleRegister() {
		let server = AppXplorerServer()

		server.register("/simple") { _ in
			return .text("Hello")
		}

		let request = Request(path: "/simple", queryParams: [:])
		let response = server.requestHandler.handle(request)

		#expect(response.status == .ok)
	}

	@Test("Register with subscript syntax")
	func testSubscriptRegister() {
		let server = AppXplorerServer()

		server["/subscript"] = { _ in
			return .text("Subscript route")
		}

		let request = Request(path: "/subscript", queryParams: [:])
		let response = server.requestHandler.handle(request)

		#expect(response.status == .ok)
	}

	// MARK: - runsOnMainThread Parameter

	@Test("Register endpoint with runsOnMainThread false")
	func testRunsOnMainThreadFalse() {
		let server = AppXplorerServer()

		server.register(
			"/background-task",
			description: "Task that runs on background thread",
			runsOnMainThread: false
		) { _ in
			return .json(["thread": "background"])
		}

		let request = Request(path: "/background-task", queryParams: [:])
		let response = server.requestHandler.handle(request)

		#expect(response.status == .ok)
	}

	// MARK: - Integration with Built-in Endpoints

	@Test("Custom endpoints coexist with built-in endpoints")
	func testCoexistenceWithBuiltInEndpoints() {
		let server = AppXplorerServer()

		// Register custom endpoint
		server.register("/my-app/status", description: "App status") { _ in
			return .json(["running": true])
		}

		// Verify built-in endpoints still work
		let infoRequest = Request(path: "/info", queryParams: [:])
		let infoResponse = server.requestHandler.handle(infoRequest)
		#expect(infoResponse.status == .ok)

		// Verify custom endpoint works
		let customRequest = Request(path: "/my-app/status", queryParams: [:])
		let customResponse = server.requestHandler.handle(customRequest)
		#expect(customResponse.status == .ok)
	}
}
