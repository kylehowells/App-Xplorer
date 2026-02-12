import Foundation
import Testing
@testable import AppXplorerServer

// MARK: - Files Endpoints Tests

@Test func testFilesRouterStructure() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	#expect(filesRouter.description == "Browse and read files from the app's sandbox")
	#expect(filesRouter.registeredPaths.contains("/"))
	#expect(filesRouter.registeredPaths.contains("/key-directories"))
	#expect(filesRouter.registeredPaths.contains("/list"))
	#expect(filesRouter.registeredPaths.contains("/metadata"))
	#expect(filesRouter.registeredPaths.contains("/read"))
	#expect(filesRouter.registeredPaths.contains("/head"))
	#expect(filesRouter.registeredPaths.contains("/tail"))
	#expect(filesRouter.registeredPaths.count == 7)
}

@Test func testFilesRouterIndex() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	let response = filesRouter.handle(Request(path: "/"))
	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["description"] as? String == "Browse and read files from the app's sandbox")
	#expect(decoded?["endpointCount"] as? Int == 7)

	let endpoints = decoded?["endpoints"] as? [[String: Any]]
	#expect(endpoints?.count == 7)
}

// MARK: - /key-directories Endpoint Tests

@Test func testFilesKeyDirectoriesEndpoint() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	let response = filesRouter.handle(Request(path: "/key-directories"))

	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	let directories = decoded?["directories"] as? [[String: Any]]

	#expect(directories != nil)
	#expect(directories!.count >= 5) // At least: home, documents, library, caches, tmp

	// Check that each directory has required fields
	let homeDir = directories?.first { ($0["alias"] as? String) == "home" }
	#expect(homeDir != nil)
	#expect(homeDir?["name"] as? String == "Home")
	#expect(homeDir?["path"] as? String == NSHomeDirectory())
	#expect(homeDir?["exists"] as? Bool == true)
	#expect(homeDir?["isDirectory"] as? Bool == true)

	// Check tmp alias
	let tmpDir = directories?.first { ($0["alias"] as? String) == "tmp" }
	#expect(tmpDir != nil)
	#expect(tmpDir?["exists"] as? Bool == true)
}

// MARK: - /list Endpoint Tests

@Test func testFilesListEndpoint() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	// List the temp directory which should exist
	let tempDir = NSTemporaryDirectory()
	let response = filesRouter.handle(Request(path: "/list", queryParams: ["path": tempDir]))

	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["path"] as? String == tempDir)
	#expect(decoded?["totalCount"] != nil)
	#expect(decoded?["contents"] != nil)
}

@Test func testFilesListNotFoundPath() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	let response = filesRouter.handle(Request(path: "/list", queryParams: ["path": "/nonexistent/path/12345"]))

	#expect(response.status == .notFound)
}

@Test func testFilesListNotADirectory() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	// Create a temp file
	let tempFile = NSTemporaryDirectory() + "test_file_\(UUID().uuidString).txt"
	FileManager.default.createFile(atPath: tempFile, contents: "test".data(using: .utf8))
	defer { try? FileManager.default.removeItem(atPath: tempFile) }

	let response = filesRouter.handle(Request(path: "/list", queryParams: ["path": tempFile]))

	#expect(response.status == .badRequest)
}

@Test func testFilesListWithAlias() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	// Use the "tmp" alias instead of absolute path
	let response = filesRouter.handle(Request(path: "/list", queryParams: ["path": "tmp"]))

	#expect(response.status == .ok)
	#expect(response.contentType == .json)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	// The path should be resolved to the actual temp directory
	let returnedPath = decoded?["path"] as? String
	#expect(returnedPath == NSTemporaryDirectory())
}

@Test func testFilesListWithAliasSubpath() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	// Create a test directory in tmp
	let subDir = NSTemporaryDirectory() + "alias_test_\(UUID().uuidString)"
	try FileManager.default.createDirectory(atPath: subDir, withIntermediateDirectories: true)
	defer { try? FileManager.default.removeItem(atPath: subDir) }

	// Use alias with subpath
	let subDirName = (subDir as NSString).lastPathComponent
	let response = filesRouter.handle(Request(path: "/list", queryParams: ["path": "tmp/\(subDirName)"]))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["path"] as? String == subDir)
}

@Test func testFilesListDefaultsToHome() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	// No path parameter should default to home
	let response = filesRouter.handle(Request(path: "/list"))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["path"] as? String == NSHomeDirectory())
}

// MARK: - /metadata Endpoint Tests

@Test func testFilesMetadataEndpoint() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	// Create a temp file to get metadata for
	let tempFile = NSTemporaryDirectory() + "metadata_test_\(UUID().uuidString).txt"
	FileManager.default.createFile(atPath: tempFile, contents: "test content".data(using: .utf8))
	defer { try? FileManager.default.removeItem(atPath: tempFile) }

	let response = filesRouter.handle(Request(path: "/metadata", queryParams: ["path": tempFile]))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["path"] as? String == tempFile)
	#expect(decoded?["isDirectory"] as? Bool == false)
	#expect(decoded?["size"] as? Int == 12) // "test content" = 12 bytes
	#expect(decoded?["extension"] as? String == "txt")
}

@Test func testFilesMetadataMissingPath() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	let response = filesRouter.handle(Request(path: "/metadata"))

	#expect(response.status == .badRequest)
}

// MARK: - /read Endpoint Tests

@Test func testFilesReadEndpoint() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	// Create a temp file to read
	let content = "Hello, World!"
	let tempFile = NSTemporaryDirectory() + "read_test_\(UUID().uuidString).txt"
	FileManager.default.createFile(atPath: tempFile, contents: content.data(using: .utf8))
	defer { try? FileManager.default.removeItem(atPath: tempFile) }

	// Read as text
	let response = filesRouter.handle(Request(path: "/read", queryParams: ["path": tempFile, "encoding": "utf8"]))

	#expect(response.status == .ok)
	#expect(response.contentType == .text)
	#expect(String(data: response.body, encoding: .utf8) == content)
}

@Test func testFilesReadBinary() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	// Create a temp binary file
	let binaryData = Data([0x00, 0x01, 0x02, 0x03])
	let tempFile = NSTemporaryDirectory() + "binary_test_\(UUID().uuidString).bin"
	FileManager.default.createFile(atPath: tempFile, contents: binaryData)
	defer { try? FileManager.default.removeItem(atPath: tempFile) }

	// Read without encoding (binary)
	let response = filesRouter.handle(Request(path: "/read", queryParams: ["path": tempFile]))

	#expect(response.status == .ok)
	#expect(response.contentType == .binary)
	#expect(response.body == binaryData)
}

// MARK: - /head Endpoint Tests

@Test func testFilesHeadEndpoint() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	// Create a temp file with multiple lines
	let lines = (1 ... 20).map { "Line \($0)" }.joined(separator: "\n")
	let tempFile = NSTemporaryDirectory() + "head_test_\(UUID().uuidString).txt"
	FileManager.default.createFile(atPath: tempFile, contents: lines.data(using: .utf8))
	defer { try? FileManager.default.removeItem(atPath: tempFile) }

	let response = filesRouter.handle(Request(path: "/head", queryParams: ["path": tempFile, "lines": "5"]))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["totalLines"] as? Int == 20)
	#expect(decoded?["returnedLines"] as? Int == 5)

	let returnedLines = decoded?["lines"] as? [String]
	#expect(returnedLines?.first == "Line 1")
	#expect(returnedLines?.last == "Line 5")
}

// MARK: - /tail Endpoint Tests

@Test func testFilesTailEndpoint() async throws {
	let filesRouter = FilesEndpoints.createRouter()

	// Create a temp file with multiple lines
	let lines = (1 ... 20).map { "Line \($0)" }.joined(separator: "\n")
	let tempFile = NSTemporaryDirectory() + "tail_test_\(UUID().uuidString).txt"
	FileManager.default.createFile(atPath: tempFile, contents: lines.data(using: .utf8))
	defer { try? FileManager.default.removeItem(atPath: tempFile) }

	let response = filesRouter.handle(Request(path: "/tail", queryParams: ["path": tempFile, "lines": "5"]))

	#expect(response.status == .ok)

	let decoded = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
	#expect(decoded?["totalLines"] as? Int == 20)
	#expect(decoded?["returnedLines"] as? Int == 5)

	let returnedLines = decoded?["lines"] as? [String]
	#expect(returnedLines?.first == "Line 16")
	#expect(returnedLines?.last == "Line 20")
}
