import Foundation

// MARK: - RouteHandler

/// Type alias for route handler functions
public typealias RouteHandler = (Request) -> Response

// MARK: - RequestHandler

/// The central router/dispatcher for handling requests
///
/// Routes are registered by path, and incoming requests are matched
/// to the appropriate handler. This class is transport-agnostic.
public class RequestHandler {
	/// Registered routes
	private var routes: [String: RouteHandler] = [:]

	/// Default handler for unmatched routes
	private var notFoundHandler: RouteHandler = { _ in
		return .notFound("Endpoint not found")
	}

	public init() { }

	// MARK: - Route Registration

	/// Register a handler for a path
	public func register(_ path: String, handler: @escaping RouteHandler) {
		self.routes[path] = handler
	}

	/// Register a handler using subscript syntax
	public subscript(path: String) -> RouteHandler? {
		get {
			return self.routes[path]
		}
		set {
			if let handler: RouteHandler = newValue {
				self.routes[path] = handler
			}
			else {
				self.routes.removeValue(forKey: path)
			}
		}
	}

	/// Set a custom not found handler
	public func setNotFoundHandler(_ handler: @escaping RouteHandler) {
		self.notFoundHandler = handler
	}

	// MARK: - Request Handling

	/// Handle an incoming request and return a response
	public func handle(_ request: Request) -> Response {
		// Try to find exact match first
		if let handler: RouteHandler = self.routes[request.path] {
			return handler(request)
		}

		// Try path with trailing slash removed
		let pathWithoutTrailingSlash: String = request.path.hasSuffix("/") && request.path != "/"
			? String(request.path.dropLast())
			: request.path
		if let handler: RouteHandler = self.routes[pathWithoutTrailingSlash] {
			return handler(request)
		}

		// No match found
		return self.notFoundHandler(request)
	}

	// MARK: - Utility

	/// Get all registered paths
	public var registeredPaths: [String] {
		return Array(self.routes.keys).sorted()
	}
}
