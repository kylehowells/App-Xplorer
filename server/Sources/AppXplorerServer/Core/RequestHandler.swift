import Foundation

// MARK: - ResponseBox

/// Thread-safe box for passing Response across dispatch boundaries
private final class ResponseBox: @unchecked Sendable {
	var value: Response? = nil
}

// MARK: - RouteHandler

/// Type alias for route handler functions
public typealias RouteHandler = @Sendable (Request) -> Response

// MARK: - ParameterInfo

/// Information about a query parameter
public struct ParameterInfo: Encodable {
	/// Parameter name
	public let name: String

	/// Description of the parameter
	public let description: String

	/// Whether this parameter is required
	public let required: Bool

	/// Default value if not provided
	public let defaultValue: String?

	/// Example values
	public let examples: [String]?

	public init(
		name: String,
		description: String,
		required: Bool = false,
		defaultValue: String? = nil,
		examples: [String]? = nil
	) {
		self.name = name
		self.description = description
		self.required = required
		self.defaultValue = defaultValue
		self.examples = examples
	}
}

// MARK: - RouteInfo

/// Information about a registered route
public struct RouteInfo {
	/// The path for this route
	public let path: String

	/// A short description of what this endpoint does
	public let description: String

	/// Query parameters accepted by this endpoint
	public let parameters: [ParameterInfo]

	/// Whether this handler should run on the main thread
	public let runsOnMainThread: Bool

	/// The handler function
	public let handler: RouteHandler

	public init(
		path: String,
		description: String,
		parameters: [ParameterInfo] = [],
		runsOnMainThread: Bool = true,
		handler: @escaping RouteHandler
	) {
		self.path = path
		self.description = description
		self.parameters = parameters
		self.runsOnMainThread = runsOnMainThread
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

	/// Query parameters accepted by this endpoint
	public let parameters: [ParameterInfo]?

	public init(path: String, description: String, parameters: [ParameterInfo]? = nil) {
		self.path = path
		self.description = description
		self.parameters = parameters
	}
}

// MARK: - RequestHandler

/// The central router/dispatcher for handling requests
///
/// Routes are registered by path, and incoming requests are matched
/// to the appropriate handler. This class is transport-agnostic.
/// Supports sub-routers for hierarchical organization.
///
/// Note: This class is marked @unchecked Sendable because route handlers
/// that need UIKit access are automatically dispatched to the main thread.
public final class RequestHandler: @unchecked Sendable {
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

	/// Register a handler for a path with a description and parameters
	/// - Parameters:
	///   - path: The path to register
	///   - description: A description of what this endpoint does
	///   - parameters: Query parameters accepted by this endpoint
	///   - runsOnMainThread: If true (default), handler runs on main thread for UIKit access. Set to false for file I/O or other non-UI work.
	///   - handler: The handler function
	public func register(
		_ path: String,
		description: String,
		parameters: [ParameterInfo] = [],
		runsOnMainThread: Bool = true,
		handler: @escaping RouteHandler
	) {
		let info: RouteInfo = .init(
			path: path,
			description: description,
			parameters: parameters,
			runsOnMainThread: runsOnMainThread,
			handler: handler
		)
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
			return self.executeHandler(routeInfo: routeInfo, request: request)
		}

		// Try path with trailing slash removed
		let pathWithoutTrailingSlash: String = path.hasSuffix("/") && path != "/"
			? String(path.dropLast())
			: path
		if let routeInfo: RouteInfo = self.routes[pathWithoutTrailingSlash] {
			return self.executeHandler(routeInfo: routeInfo, request: request)
		}

		// No match found
		return self.notFoundHandler(request)
	}

	/// Execute a route handler, dispatching to main thread if required
	private func executeHandler(routeInfo: RouteInfo, request: Request) -> Response {
		// If already on main thread or handler doesn't need main thread, execute directly
		if !routeInfo.runsOnMainThread || Thread.isMainThread {
			return routeInfo.handler(request)
		}

		// Dispatch to main thread and wait for result using thread-safe box
		let responseBox: ResponseBox = .init()
		let semaphore: DispatchSemaphore = .init(value: 0)
		let handler: RouteHandler = routeInfo.handler
		let req: Request = request

		DispatchQueue.main.async {
			responseBox.value = handler(req)
			semaphore.signal()
		}

		// Wait with timeout to prevent deadlocks
		let result: DispatchTimeoutResult = semaphore.wait(timeout: .now() + 30.0)

		if result == .timedOut {
			return .error("Request handler timed out", status: .internalError)
		}

		return responseBox.value ?? .error("Handler returned nil", status: .internalError)
	}

	// MARK: - API Discovery

	/// Get information about this router
	/// - Parameter deep: If true, recursively includes sub-router endpoints; if false, only shows sub-router summaries
	public func routerInfo(deep: Bool = false) -> RouterInfo {
		// Always include this router's own endpoints
		let endpoints: [EndpointInfo] = self.routes
			.values
			.sorted { $0.path < $1.path }
			.map { EndpointInfo(
				path: $0.path,
				description: $0.description,
				parameters: $0.parameters.isEmpty ? nil : $0.parameters
			) }

		let routers: [RouterInfo]?

		if deep {
			// Deep: recursively include full sub-router info with their endpoints
			routers = self.subRouters
				.sorted { $0.key < $1.key }
				.map { $0.value.routerInfo(deep: true) }
		}
		else {
			// Shallow: only show sub-router summaries (path, description, count)
			routers = self.subRouters.isEmpty ? nil : self.subRouters
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
			endpoints: endpoints.isEmpty ? nil : endpoints,
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
			.map { EndpointInfo(
				path: $0.path,
				description: $0.description,
				parameters: $0.parameters.isEmpty ? nil : $0.parameters
			) }
	}
}
