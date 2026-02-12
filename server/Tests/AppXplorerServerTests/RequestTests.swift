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
