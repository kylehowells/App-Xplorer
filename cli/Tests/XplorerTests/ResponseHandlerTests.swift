import Foundation
import XCTest
@testable import XplorerLib

final class ResponseHandlerTests: XCTestCase {
    // MARK: - classifyResponse Tests

    func testClassifyResponseWithJSON() {
        let jsonData = "{\"key\": \"value\"}".data(using: .utf8)!
        let result = classifyResponse(jsonData)

        if case let .json(text) = result {
            XCTAssertTrue(text.contains("key"))
            XCTAssertTrue(text.contains("value"))
        } else {
            XCTFail("Expected .json, got \(result)")
        }
    }

    func testClassifyResponseWithJSONArray() {
        let jsonData = "[1, 2, 3]".data(using: .utf8)!
        let result = classifyResponse(jsonData)

        if case .json = result {
            // Success
        } else {
            XCTFail("Expected .json, got \(result)")
        }
    }

    func testClassifyResponseWithPlainText() {
        let textData = "Hello, this is plain text with no JSON structure.".data(using: .utf8)!
        let result = classifyResponse(textData)

        if case let .text(text) = result {
            XCTAssertEqual(text, "Hello, this is plain text with no JSON structure.")
        } else {
            XCTFail("Expected .text, got \(result)")
        }
    }

    func testClassifyResponseWithBinaryPNG() {
        // PNG magic bytes: 89 50 4E 47 0D 0A 1A 0A
        var pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        pngData.append(contentsOf: [0x00, 0x00, 0x00, 0x0D]) // More binary data

        let result = classifyResponse(pngData)

        if case let .binary(data) = result {
            XCTAssertEqual(data, pngData)
        } else {
            XCTFail("Expected .binary, got \(result)")
        }
    }

    func testClassifyResponseWithBinaryJPEG() {
        // JPEG magic bytes: FF D8 FF
        var jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])
        jpegData.append(contentsOf: [0x49, 0x46, 0x00, 0x01])

        let result = classifyResponse(jpegData)

        if case .binary = result {
            // Success
        } else {
            XCTFail("Expected .binary, got \(result)")
        }
    }

    // MARK: - detectFileExtension Tests

    func testDetectFileExtensionPNG() {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        XCTAssertEqual(detectFileExtension(from: pngData), "png")
    }

    func testDetectFileExtensionJPEG() {
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46])
        XCTAssertEqual(detectFileExtension(from: jpegData), "jpg")
    }

    func testDetectFileExtensionGIF() {
        let gifData = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x00, 0x00])
        XCTAssertEqual(detectFileExtension(from: gifData), "gif")
    }

    func testDetectFileExtensionPDF() {
        let pdfData = Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34])
        XCTAssertEqual(detectFileExtension(from: pdfData), "pdf")
    }

    func testDetectFileExtensionZIP() {
        let zipData = Data([0x50, 0x4B, 0x03, 0x04, 0x0A, 0x00, 0x00, 0x00])
        XCTAssertEqual(detectFileExtension(from: zipData), "zip")
    }

    func testDetectFileExtensionUnknown() {
        let unknownData = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        XCTAssertEqual(detectFileExtension(from: unknownData), "bin")
    }

    func testDetectFileExtensionTooShort() {
        let shortData = Data([0x89, 0x50, 0x4E])
        XCTAssertEqual(detectFileExtension(from: shortData), "bin")
    }

    // MARK: - generateTimestampFilename Tests

    func testGenerateTimestampFilename() {
        let date = Date(timeIntervalSince1970: 1_707_206_400) // 2024-02-06 08:00:00 UTC
        let filename = generateTimestampFilename(extension: "png", date: date)

        XCTAssertTrue(filename.hasPrefix("/tmp/xplorer-"))
        XCTAssertTrue(filename.hasSuffix(".png"))
    }

    func testGenerateTimestampFilenameWithBinExtension() {
        let date = Date(timeIntervalSince1970: 1_707_206_400)
        let filename = generateTimestampFilename(extension: "bin", date: date)

        XCTAssertTrue(filename.hasSuffix(".bin"))
    }

    // MARK: - writeDataToFile Tests

    func testWriteDataToFile() throws {
        let testData = "Test content for file".data(using: .utf8)!
        let tempPath = "/tmp/xplorer-test-\(UUID().uuidString).txt"

        try writeDataToFile(testData, at: tempPath)

        // Verify file was written
        let readData = try Data(contentsOf: URL(fileURLWithPath: tempPath))
        XCTAssertEqual(readData, testData)

        // Cleanup
        try FileManager.default.removeItem(atPath: tempPath)
    }

    func testWriteBinaryDataToFile() throws {
        // PNG header
        let binaryData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])
        let tempPath = "/tmp/xplorer-test-\(UUID().uuidString).png"

        try writeDataToFile(binaryData, at: tempPath)

        // Verify file was written with correct content
        let readData = try Data(contentsOf: URL(fileURLWithPath: tempPath))
        XCTAssertEqual(readData, binaryData)

        // Cleanup
        try FileManager.default.removeItem(atPath: tempPath)
    }

    func testWriteJSONDataToFile() throws {
        let jsonData = "{\"name\": \"test\", \"value\": 123}".data(using: .utf8)!
        let tempPath = "/tmp/xplorer-test-\(UUID().uuidString).json"

        try writeDataToFile(jsonData, at: tempPath)

        // Verify file was written
        let readData = try Data(contentsOf: URL(fileURLWithPath: tempPath))
        XCTAssertEqual(readData, jsonData)

        // Verify it's valid JSON
        let json = try JSONSerialization.jsonObject(with: readData)
        XCTAssertNotNil(json)

        // Cleanup
        try FileManager.default.removeItem(atPath: tempPath)
    }

    // MARK: - Integration Tests: Binary auto-save behavior

    func testBinaryResponseAutoSaveDetectsPNGExtension() {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        // Verify it's classified as binary
        let response = classifyResponse(pngData)
        if case .binary = response {
            // Verify extension detection
            let ext = detectFileExtension(from: pngData)
            XCTAssertEqual(ext, "png")
        } else {
            XCTFail("PNG data should be classified as binary")
        }
    }

    func testBinaryResponseAutoSaveDetectsJPEGExtension() {
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])

        let response = classifyResponse(jpegData)
        if case .binary = response {
            let ext = detectFileExtension(from: jpegData)
            XCTAssertEqual(ext, "jpg")
        } else {
            XCTFail("JPEG data should be classified as binary")
        }
    }

    // MARK: - Integration Tests: -o flag writes any response type

    func testOutputFlagWritesJSON() throws {
        let jsonString = "{\"status\": \"ok\"}"
        let jsonData = try XCTUnwrap(jsonString.data(using: .utf8))
        let tempPath = "/tmp/xplorer-test-json-\(UUID().uuidString).json"

        // Simulate -o behavior: write raw data regardless of type
        try writeDataToFile(jsonData, at: tempPath)

        // Verify
        let readData = try Data(contentsOf: URL(fileURLWithPath: tempPath))
        XCTAssertEqual(String(data: readData, encoding: .utf8), jsonString)

        // Cleanup
        try FileManager.default.removeItem(atPath: tempPath)
    }

    func testOutputFlagWritesText() throws {
        let textString = "Plain text response"
        let textData = try XCTUnwrap(textString.data(using: .utf8))
        let tempPath = "/tmp/xplorer-test-text-\(UUID().uuidString).txt"

        try writeDataToFile(textData, at: tempPath)

        let readData = try Data(contentsOf: URL(fileURLWithPath: tempPath))
        XCTAssertEqual(String(data: readData, encoding: .utf8), textString)

        // Cleanup
        try FileManager.default.removeItem(atPath: tempPath)
    }

    func testOutputFlagWritesBinary() throws {
        let binaryData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let tempPath = "/tmp/xplorer-test-binary-\(UUID().uuidString).png"

        try writeDataToFile(binaryData, at: tempPath)

        let readData = try Data(contentsOf: URL(fileURLWithPath: tempPath))
        XCTAssertEqual(readData, binaryData)

        // Cleanup
        try FileManager.default.removeItem(atPath: tempPath)
    }
}
