import Foundation
import Testing
@testable import AppXplorerServer

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
