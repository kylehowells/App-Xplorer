import Foundation

// MARK: - RouteHandler

/// Type alias for route handler functions
public typealias RouteHandler = (Request) -> Response

// MARK: - RouteInfo

/// Information about a registered route
public struct RouteInfo {
	/// The path for this route
	public let path: String

	/// A short description of what this endpoint does
	public let description: String

	/// The handler function
	public let handler: RouteHandler

	public init(path: String, description: String, handler: @escaping RouteHandler) {
		self.path = path
		self.description = description
		self.handler = handler
	}
}

// MARK: - RouterInfo

/// Information about a router for API discovery
public struct RouterInfo: Encodable {
	/// The base path for this router
	public let path: String

	/// A short description of this router
	public let description: String

	/// Number of endpoints in this router
	public let endpointCount: Int

	/// Child endpoints (only included in deep mode)
	public let endpoints: [EndpointInfo]?

	/// Child routers (only included in deep mode)
	public let routers: [RouterInfo]?

	public init(
		path: String,
		description: String,
		endpointCount: Int,
		endpoints: [EndpointInfo]? = nil,
		routers: [RouterInfo]? = nil
	) {
		self.path = path
		self.description = description
		self.endpointCount = endpointCount
		self.endpoints = endpoints
		self.routers = routers
	}
}

// MARK: - EndpointInfo

/// Information about an endpoint for API discovery
public struct EndpointInfo: Encodable {
	/// The path for this endpoint
	public let path: String

	/// A short description of what this endpoint does
	public let description: String

	public init(path: String, description: String) {
		self.path = path
		self.description = description
	}
}

// MARK: - RequestHandler

/// The central router/dispatcher for handling requests
///
/// Routes are registered by path, and incoming requests are matched
/// to the appropriate handler. This class is transport-agnostic.
/// Supports sub-routers for hierarchical organization.
public class RequestHandler {
	/// A description of this router
	public var description: String = ""

	/// The base path for this router (set when mounted as sub-router)
	public private(set) var basePath: String = ""

	/// Registered routes with their info
	private var routes: [String: RouteInfo] = [:]

	/// Child routers mounted at sub-paths
	private var subRouters: [String: RequestHandler] = [:]

	/// Default handler for unmatched routes
	private var notFoundHandler: RouteHandler = { _ in
		return .notFound("Endpoint not found")
	}

	public init(description: String = "") {
		self.description = description
	}

	// MARK: - Route Registration

	/// Register a handler for a path with a description
	public func register(_ path: String, description: String, handler: @escaping RouteHandler) {
		let info: RouteInfo = .init(path: path, description: description, handler: handler)
		self.routes[path] = info
	}

	/// Register a handler for a path (legacy, empty description)
	public func register(_ path: String, handler: @escaping RouteHandler) {
		self.register(path, description: "", handler: handler)
	}

	/// Register a handler using subscript syntax (legacy, empty description)
	public subscript(path: String) -> RouteHandler? {
		get {
			return self.routes[path]?.handler
		}
		set {
			if let handler: RouteHandler = newValue {
				self.register(path, description: "", handler: handler)
			}
			else {
				self.routes.removeValue(forKey: path)
			}
		}
	}

	/// Mount a sub-router at a path prefix
	public func mount(_ prefix: String, router: RequestHandler) {
		let normalizedPrefix: String = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
		router.basePath = normalizedPrefix
		self.subRouters[normalizedPrefix] = router
	}

	/// Set a custom not found handler
	public func setNotFoundHandler(_ handler: @escaping RouteHandler) {
		self.notFoundHandler = handler
	}

	// MARK: - Request Handling

	/// Handle an incoming request and return a response
	public func handle(_ request: Request) -> Response {
		let path: String = request.path

		// Check sub-routers first
		for (prefix, router) in self.subRouters {
			if path == prefix || path.hasPrefix(prefix + "/") {
				// Create a new request with the path relative to the sub-router
				var subPath: String = .init(path.dropFirst(prefix.count))
				if subPath.isEmpty {
					subPath = "/"
				}
				let subRequest: Request = .init(
					path: subPath,
					queryParams: request.queryParams,
					body: request.body,
					metadata: request.metadata
				)
				return router.handle(subRequest)
			}
		}

		// Try to find exact match in local routes
		if let routeInfo: RouteInfo = self.routes[path] {
			return routeInfo.handler(request)
		}

		// Try path with trailing slash removed
		let pathWithoutTrailingSlash: String = path.hasSuffix("/") && path != "/"
			? String(path.dropLast())
			: path
		if let routeInfo: RouteInfo = self.routes[pathWithoutTrailingSlash] {
			return routeInfo.handler(request)
		}

		// No match found
		return self.notFoundHandler(request)
	}

	// MARK: - API Discovery

	/// Get information about this router
	/// - Parameter deep: If true, includes full endpoint details; if false, just counts
	public func routerInfo(deep: Bool = false) -> RouterInfo {
		let endpoints: [EndpointInfo]?
		let routers: [RouterInfo]?

		if deep {
			endpoints = self.routes
				.values
				.sorted { $0.path < $1.path }
				.map { EndpointInfo(path: $0.path, description: $0.description) }

			routers = self.subRouters
				.sorted { $0.key < $1.key }
				.map { $0.value.routerInfo(deep: true) }
		}
		else {
			endpoints = nil
			routers = self.subRouters
				.sorted { $0.key < $1.key }
				.map { RouterInfo(
					path: $0.value.basePath,
					description: $0.value.description,
					endpointCount: $0.value.totalEndpointCount
				) }
		}

		return RouterInfo(
			path: self.basePath.isEmpty ? "/" : self.basePath,
			description: self.description,
			endpointCount: self.totalEndpointCount,
			endpoints: deep ? endpoints : nil,
			routers: routers
		)
	}

	/// Get total count of endpoints including sub-routers
	public var totalEndpointCount: Int {
		let localCount: Int = self.routes.count
		let subCount: Int = self.subRouters.values.reduce(0) { $0 + $1.totalEndpointCount }
		return localCount + subCount
	}

	// MARK: - Utility

	/// Get all registered paths (local routes only)
	public var registeredPaths: [String] {
		return Array(self.routes.keys).sorted()
	}

	/// Get all endpoint info for local routes
	public var endpointInfos: [EndpointInfo] {
		return self.routes
			.values
			.sorted { $0.path < $1.path }
			.map { EndpointInfo(path: $0.path, description: $0.description) }
	}
}
