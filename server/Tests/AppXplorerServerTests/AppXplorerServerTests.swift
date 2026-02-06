import Foundation
import Testing
@testable import AppXplorerServer

// MARK: - Request Tests

@Test func testRequestCreation() async throws {
	let request = Request(
		path: "/test",
		queryParams: ["key": "value"],
		body: "test body".data(using: .utf8),
		metadata: ["header": "value"]
	)

	#expect(request.path == "/test")
	#expect(request.queryParams["key"] == "value")
	#expect(request.body != nil)
	#expect(request.metadata["header"] == "value")
}

@Test func testRequestDefaultValues() async throws {
	let request = Request(path: "/simple")

	#expect(request.path == "/simple")
	#expect(request.queryParams.isEmpty)
	#expect(request.body == nil)
	#expect(request.metadata.isEmpty)
}

// MARK: - Response Tests

@Test func testJsonResponse() async throws {
	let response = Response.json(["key": "value"])

	#expect(response.status == .ok)
	#expect(response.contentType == .json)
	#expect(!response.body.isEmpty)

	// Verify JSON is valid
	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: String]
	#expect(decoded?["key"] == "value")
}

@Test func testHtmlResponse() async throws {
	let html = "<html><body>Hello</body></html>"
	let response = Response.html(html)

	#expect(response.status == .ok)
	#expect(response.contentType == .html)
	#expect(String(data: response.body, encoding: .utf8) == html)
}

@Test func testTextResponse() async throws {
	let text = "Plain text response"
	let response = Response.text(text)

	#expect(response.status == .ok)
	#expect(response.contentType == .text)
	#expect(String(data: response.body, encoding: .utf8) == text)
}

@Test func testNotFoundResponse() async throws {
	let response = Response.notFound("Resource missing")

	#expect(response.status == .notFound)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: String]
	#expect(decoded?["error"] == "Resource missing")
}

@Test func testErrorResponse() async throws {
	let response = Response.error("Something went wrong", status: .internalError)

	#expect(response.status == .internalError)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: String]
	#expect(decoded?["error"] == "Something went wrong")
}

@Test func testBinaryResponse() async throws {
	let data = Data([0x00, 0x01, 0x02, 0x03])
	let response = Response.binary(data)

	#expect(response.status == .ok)
	#expect(response.contentType == .binary)
	#expect(response.body == data)
}

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

// MARK: - Response Status Tests

@Test func testResponseStatusCodes() async throws {
	#expect(ResponseStatus.ok.rawValue == 200)
	#expect(ResponseStatus.badRequest.rawValue == 400)
	#expect(ResponseStatus.notFound.rawValue == 404)
	#expect(ResponseStatus.internalError.rawValue == 500)
}

// MARK: - ContentType Tests

@Test func testContentTypeRawValues() async throws {
	#expect(ContentType.json.rawValue == "application/json")
	#expect(ContentType.html.rawValue == "text/html")
	#expect(ContentType.text.rawValue == "text/plain")
	#expect(ContentType.png.rawValue == "image/png")
	#expect(ContentType.jpeg.rawValue == "image/jpeg")
	#expect(ContentType.binary.rawValue == "application/octet-stream")
}
