import Foundation

// MARK: - Request

/// A transport-agnostic request
public struct Request {
	/// The endpoint path (e.g., "/info", "/screenshot")
	public let path: String

	/// Query parameters as key-value pairs
	public let queryParams: [String: String]

	/// Optional request body data
	public let body: Data?

	/// Additional headers/metadata (transport-specific)
	public let metadata: [String: String]

	public init(
		path: String,
		queryParams: [String: String] = [:],
		body: Data? = nil,
		metadata: [String: String] = [:]
	) {
		self.path = path
		self.queryParams = queryParams
		self.body = body
		self.metadata = metadata
	}
}
