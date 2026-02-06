import Foundation

// MARK: - ResponseStatus

/// Response status codes
public enum ResponseStatus: Int {
	case ok = 200
	case badRequest = 400
	case notFound = 404
	case internalError = 500
}

// MARK: - ContentType

/// Common content types
public enum ContentType: String {
	case json = "application/json"
	case html = "text/html"
	case text = "text/plain"
	case png = "image/png"
	case jpeg = "image/jpeg"
	case binary = "application/octet-stream"
}

// MARK: - Response

/// A transport-agnostic response
public struct Response {
	/// Response status
	public let status: ResponseStatus

	/// Content type of the response body
	public let contentType: ContentType

	/// Response body data
	public let body: Data

	public init(status: ResponseStatus, contentType: ContentType, body: Data) {
		self.status = status
		self.contentType = contentType
		self.body = body
	}

	// MARK: - Convenience Initializers

	/// Create a JSON response
	public static func json(_ object: Any, status: ResponseStatus = .ok) -> Response {
		let data: Data
		if let jsonData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
			data = jsonData
		}
		else {
			data = "{}".data(using: .utf8) ?? Data()
		}
		return Response(status: status, contentType: .json, body: data)
	}

	/// Create a JSON response from Encodable
	public static func json<T: Encodable>(_ object: T, status: ResponseStatus = .ok) -> Response {
		let encoder: JSONEncoder = .init()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		let data: Data
		if let jsonData = try? encoder.encode(object) {
			data = jsonData
		}
		else {
			data = "{}".data(using: .utf8) ?? Data()
		}
		return Response(status: status, contentType: .json, body: data)
	}

	/// Create an HTML response
	public static func html(_ string: String, status: ResponseStatus = .ok) -> Response {
		let data: Data = string.data(using: .utf8) ?? Data()
		return Response(status: status, contentType: .html, body: data)
	}

	/// Create a plain text response
	public static func text(_ string: String, status: ResponseStatus = .ok) -> Response {
		let data: Data = string.data(using: .utf8) ?? Data()
		return Response(status: status, contentType: .text, body: data)
	}

	/// Create a PNG image response
	public static func png(_ data: Data, status: ResponseStatus = .ok) -> Response {
		return Response(status: status, contentType: .png, body: data)
	}

	/// Create a JPEG image response
	public static func jpeg(_ data: Data, status: ResponseStatus = .ok) -> Response {
		return Response(status: status, contentType: .jpeg, body: data)
	}

	/// Create a binary response
	public static func binary(_ data: Data, status: ResponseStatus = .ok) -> Response {
		return Response(status: status, contentType: .binary, body: data)
	}

	/// Create a not found response
	public static func notFound(_ message: String = "Not Found") -> Response {
		return .json(["error": message], status: .notFound)
	}

	/// Create an error response
	public static func error(_ message: String, status: ResponseStatus = .internalError) -> Response {
		return .json(["error": message], status: status)
	}
}
