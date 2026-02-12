import Foundation
import Testing

@testable import AppXplorerServer

// MARK: - Interact Endpoints Tests

@Test func testInteractRouterStructure() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	#expect(router.registeredPaths.contains("/"))
	#expect(router.registeredPaths.contains("/tap"))
	#expect(router.registeredPaths.contains("/type"))
	#expect(router.registeredPaths.contains("/focus"))
	#expect(router.registeredPaths.contains("/resign"))
	#expect(router.registeredPaths.contains("/scroll"))
	#expect(router.registeredPaths.contains("/swipe"))
	#expect(router.registeredPaths.contains("/accessibility"))
	#expect(router.registeredPaths.contains("/select-cell"))
	#expect(router.registeredPaths.count == 9)
}

@Test func testInteractRouterIndex() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	let response = router.handle(Request(path: "/"))

	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["description"] as? String == "Interact with UI elements: tap buttons, type text, scroll views, and trigger gestures")
}

@Test func testInteractTapMissingAddress() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	let response = router.handle(Request(path: "/tap"))

	#expect(response.status == .badRequest)
}

@Test func testInteractTapInvalidAddress() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	let response = router.handle(Request(path: "/tap", queryParams: ["address": "not-valid"]))

	#expect(response.status == .badRequest)
}

@Test func testInteractTypeMissingText() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	let response = router.handle(Request(path: "/type"))

	#expect(response.status == .badRequest)
}

@Test func testInteractTypeNoFirstResponder() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	// Without UIKit (macOS tests), this should fail appropriately
	let response = router.handle(Request(path: "/type", queryParams: ["text": "hello"]))

	// On macOS this returns an error, on iOS it would need a first responder
	#expect(response.status == .badRequest)
}

@Test func testInteractFocusMissingAddress() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	let response = router.handle(Request(path: "/focus"))

	#expect(response.status == .badRequest)
}

@Test func testInteractFocusInvalidAddress() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	let response = router.handle(Request(path: "/focus", queryParams: ["address": "0x1"]))

	// Invalid/nonexistent address should return not found
	#expect(response.status == .notFound || response.status == .badRequest)
}

@Test func testInteractScrollMissingAddress() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	let response = router.handle(Request(path: "/scroll"))

	#expect(response.status == .badRequest)
}

@Test func testInteractSwipeMissingParams() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	// Missing both address and direction
	let response1 = router.handle(Request(path: "/swipe"))
	#expect(response1.status == .badRequest)

	// Missing direction
	let response2 = router.handle(Request(path: "/swipe", queryParams: ["address": "0x12345678"]))
	#expect(response2.status == .badRequest)

	// Missing address
	let response3 = router.handle(Request(path: "/swipe", queryParams: ["direction": "left"]))
	#expect(response3.status == .badRequest)
}

@Test func testInteractSwipeInvalidDirection() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	let response = router.handle(Request(path: "/swipe", queryParams: [
		"address": "0x12345678",
		"direction": "diagonal",
	]))

	#expect(response.status == .badRequest)
}

@Test func testInteractAccessibilityMissingAddress() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	let response = router.handle(Request(path: "/accessibility"))

	#expect(response.status == .badRequest)
}

@Test func testInteractTotalEndpointCount() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()
	let info = router.routerInfo(deep: true)

	// 9 endpoints: /, /tap, /type, /focus, /resign, /scroll, /swipe, /accessibility, /select-cell
	#expect(info.endpoints?.count == 9)
}

@Test func testInteractInRootIndex() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	let response = handler.handle(Request(path: "/", queryParams: ["depth": "shallow"]))

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	let routers = decoded?["routers"] as? [[String: Any]]
	let interactRouter = routers?.first { ($0["path"] as? String) == "/interact" }

	#expect(interactRouter != nil)
	#expect(interactRouter?["description"] as? String == "Interact with UI elements: tap buttons, type text, scroll views, and trigger gestures")
	#expect(interactRouter?["endpointCount"] as? Int == 9)
}

@Test func testInteractMountedAsSubRouter() async throws {
	let handler = RequestHandler()
	RootRouter.registerAll(with: handler)

	// Test routing through the main handler
	let response = handler.handle(Request(path: "/interact/"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["path"] as? String == "/interact")
}

// MARK: - Select Cell Tests

@Test func testInteractSelectCellMissingAddress() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	let response = router.handle(Request(path: "/select-cell"))

	#expect(response.status == .badRequest)
}

@Test func testInteractSelectCellMissingRow() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	let response = router.handle(Request(path: "/select-cell", queryParams: ["address": "0x12345678"]))

	#expect(response.status == .badRequest)
}

@Test func testInteractSelectCellInvalidAddress() async throws {
	let router: RequestHandler = InteractEndpoints.createRouter()

	let response = router.handle(Request(path: "/select-cell", queryParams: [
		"address": "not-valid",
		"row": "0",
	]))

	#expect(response.status == .badRequest)
}

// MARK: - Platform-Specific Tests

#if !canImport(UIKit)
	@Test func testInteractTapNotAvailableOnMacOS() async throws {
		let router: RequestHandler = InteractEndpoints.createRouter()

		let response = router.handle(Request(path: "/tap", queryParams: ["address": "0x12345678"]))

		#expect(response.status == .badRequest)

		let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
		let error = decoded?["error"] as? String
		#expect(error?.contains("only available on iOS") == true)
	}

	@Test func testInteractScrollNotAvailableOnMacOS() async throws {
		let router: RequestHandler = InteractEndpoints.createRouter()

		let response = router.handle(Request(path: "/scroll", queryParams: ["address": "0x12345678"]))

		#expect(response.status == .badRequest)
	}
#endif
