import Foundation
import Testing
@testable import AppXplorerServer

// MARK: - Info Endpoints Tests

@Test func testInfoEndpointRegistration() async throws {
	let handler = RequestHandler()
	InfoEndpoints.register(with: handler)

	#expect(handler.registeredPaths.contains("/info"))
	#expect(handler.registeredPaths.contains("/screenshot"))
	#expect(handler.registeredPaths.count == 2)
}

@Test func testInfoEndpointResponse() async throws {
	let handler = RequestHandler()
	InfoEndpoints.register(with: handler)

	let response = handler.handle(Request(path: "/info"))

	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["app"] != nil)
	#expect(decoded?["timestamp"] != nil)
}

// MARK: - Screenshot Endpoint Tests

@Test func testScreenshotEndpointExists() async throws {
	let handler = RequestHandler()
	InfoEndpoints.register(with: handler)

	// Verify endpoint is registered with correct parameters
	let info = handler.routerInfo(deep: true)
	let screenshotEndpoint = info.endpoints?.first { $0.path == "/screenshot" }

	#expect(screenshotEndpoint != nil)
	#expect(screenshotEndpoint?.description.contains("PNG") == true)

	// Check parameters are documented (view, format, quality, scale, afterScreenUpdates)
	let params = screenshotEndpoint?.parameters
	#expect(params?.count == 5)

	let viewParam = params?.first { $0.name == "view" }
	#expect(viewParam != nil)
	#expect(viewParam?.required == false)
	#expect(viewParam?.examples?.first?.contains("0x") == true)

	let formatParam = params?.first { $0.name == "format" }
	#expect(formatParam != nil)
	#expect(formatParam?.defaultValue == "png")
	#expect(formatParam?.examples?.contains("jpeg") == true)

	let qualityParam = params?.first { $0.name == "quality" }
	#expect(qualityParam != nil)
	#expect(qualityParam?.defaultValue == "0.9")

	let scaleParam = params?.first { $0.name == "scale" }
	#expect(scaleParam != nil)
	#expect(scaleParam?.defaultValue == "1.0")

	let afterScreenUpdatesParam = params?.first { $0.name == "afterScreenUpdates" }
	#expect(afterScreenUpdatesParam != nil)
	#expect(afterScreenUpdatesParam?.defaultValue == "false")
}

#if !canImport(UIKit)
	@Test func testScreenshotNotAvailableOnMacOS() async throws {
		let handler = RequestHandler()
		InfoEndpoints.register(with: handler)

		let response = handler.handle(Request(path: "/screenshot"))

		#expect(response.status == .badRequest)

		let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: String]
		#expect(decoded?["error"]?.contains("only available on iOS") == true)
	}
#endif
