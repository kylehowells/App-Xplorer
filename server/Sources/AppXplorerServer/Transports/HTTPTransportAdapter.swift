import Foundation
import Swifter

// MARK: - HTTPTransportAdapter

/// HTTP transport adapter using Swifter
public class HTTPTransportAdapter: TransportAdapter {
	private let server: HttpServer = .init()
	public var requestHandler: RequestHandler? = nil
	public private(set) var isRunning: Bool = false
	public let port: UInt16

	public init(port: UInt16 = 8080) {
		self.port = port
	}

	// MARK: - TransportAdapter

	public func start() throws {
		guard !self.isRunning else { return }

		// Set up catch-all handler that routes to RequestHandler
		self.server.notFoundHandler = { [weak self] httpRequest in
			guard let self = self, let handler = self.requestHandler else {
				return .notFound
			}

			// Convert Swifter request to our Request
			let request: Request = self.convertRequest(httpRequest)

			// Handle the request
			let response: Response = handler.handle(request)

			// Convert our Response to Swifter response
			return self.convertResponse(response)
		}

		try self.server.start(self.port, forceIPv4: false, priority: .background)
		self.isRunning = true

		print("🌐 HTTP transport started on port \(self.port)")
	}

	public func stop() {
		self.server.stop()
		self.isRunning = false
		print("🌐 HTTP transport stopped")
	}

	// MARK: - Conversion

	/// Convert Swifter HttpRequest to our Request
	private func convertRequest(_ httpRequest: HttpRequest) -> Request {
		// Parse query parameters
		var queryParams: [String: String] = [:]
		for param in httpRequest.queryParams {
			queryParams[param.0] = param.1
		}

		// Parse headers as metadata
		var metadata: [String: String] = [:]
		for (key, value) in httpRequest.headers {
			metadata[key] = value
		}

		// Get body data
		let body: Data? = httpRequest.body.isEmpty ? nil : Data(httpRequest.body)

		return Request(
			path: httpRequest.path,
			queryParams: queryParams,
			body: body,
			metadata: metadata
		)
	}

	/// Convert our Response to Swifter HttpResponse
	private func convertResponse(_ response: Response) -> HttpResponse {
		let contentType: String = response.contentType.rawValue

		switch response.status {
			case .ok:
				return .raw(200, "OK", ["Content-Type": contentType]) { writer in
					try writer.write(response.body)
				}

			case .badRequest:
				return .raw(400, "Bad Request", ["Content-Type": contentType]) { writer in
					try writer.write(response.body)
				}

			case .notFound:
				return .raw(404, "Not Found", ["Content-Type": contentType]) { writer in
					try writer.write(response.body)
				}

			case .internalError:
				return .raw(500, "Internal Server Error", ["Content-Type": contentType]) { writer in
					try writer.write(response.body)
				}
		}
	}
}
