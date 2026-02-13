import Foundation

// MARK: - AppXplorerServer

/// AppXplorerServer - A debugging server that runs inside iOS apps
/// Provides remote access to app internals for debugging purposes
///
/// The server is transport-agnostic and can communicate over HTTP, WebSocket,
/// Iroh, Bluetooth, or any other transport mechanism.
public class AppXplorerServer {
	/// The central request handler that routes requests to endpoints
	public let requestHandler: RequestHandler = .init()

	/// Active transport adapters
	private var transports: [TransportAdapter] = []

	/// Whether any transport is running
	public var isRunning: Bool {
		return self.transports.contains { $0.isRunning }
	}

	public init() {
		// Configure the root router with all built-in endpoints
		RootRouter.registerAll(with: self.requestHandler)
	}

	// MARK: - Transport Management

	/// Add a transport adapter
	public func addTransport(_ transport: TransportAdapter) {
		transport.requestHandler = self.requestHandler
		self.transports.append(transport)
	}

	/// Remove a transport adapter
	public func removeTransport(_ transport: TransportAdapter) {
		transport.stop()
		self.transports.removeAll { $0 === transport }
	}

	// MARK: - Server Control

	/// Start all transport adapters
	public func start() throws {
		print("🚀 AppXplorerServer starting...")

		for transport in self.transports {
			try transport.start()
		}

		if let address: String = self.getWiFiAddress() {
			print("📱 Device IP: \(address)")
		}
	}

	/// Stop all transport adapters
	public func stop() {
		for transport in self.transports {
			transport.stop()
		}
		print("🛑 AppXplorerServer stopped")
	}

	// MARK: - Convenience

	/// Create a server with HTTP transport on the specified port
	public static func withHTTP(port: UInt16 = 8080) -> AppXplorerServer {
		let server: AppXplorerServer = .init()
		let httpTransport: HTTPTransportAdapter = .init(port: port)
		server.addTransport(httpTransport)
		return server
	}

	// MARK: - Custom Endpoints

	/// Register a custom endpoint with full configuration
	///
	/// This is the same API used internally by AppXplorer's built-in endpoints.
	/// Use this to add your own custom routes that integrate seamlessly with
	/// the API discovery system.
	///
	/// Example:
	/// ```swift
	/// server.register(
	///     "/custom/user",
	///     description: "Get current user information",
	///     parameters: [
	///         ParameterInfo(name: "include_avatar", description: "Include base64 avatar", required: false)
	///     ]
	/// ) { request in
	///     let includeAvatar = request.queryParams["include_avatar"] == "true"
	///     return .json(["username": "john", "email": "john@example.com"])
	/// }
	/// ```
	///
	/// - Parameters:
	///   - path: The path for this endpoint (e.g., "/custom/user")
	///   - description: A description shown in API discovery
	///   - parameters: Query parameters accepted by this endpoint
	///   - runsOnMainThread: If true (default), handler runs on main thread for UIKit access
	///   - handler: The handler function
	public func register(
		_ path: String,
		description: String,
		parameters: [ParameterInfo] = [],
		runsOnMainThread: Bool = true,
		handler: @escaping RouteHandler
	) {
		self.requestHandler.register(
			path,
			description: description,
			parameters: parameters,
			runsOnMainThread: runsOnMainThread,
			handler: handler
		)
	}

	/// Register a custom endpoint (simple form without metadata)
	public func register(_ path: String, handler: @escaping RouteHandler) {
		self.requestHandler.register(path, handler: handler)
	}

	/// Mount a custom sub-router at a path prefix
	///
	/// This allows you to create modular endpoint groups that integrate with
	/// AppXplorer's API discovery. Create a `RequestHandler`, register endpoints
	/// on it, then mount it at a prefix path.
	///
	/// Example:
	/// ```swift
	/// // Create a custom router for your app's user endpoints
	/// let userRouter = RequestHandler(description: "User account endpoints")
	///
	/// userRouter.register("/profile", description: "Get user profile") { request in
	///     return .json(["name": "John Doe", "email": "john@example.com"])
	/// }
	///
	/// userRouter.register("/settings", description: "Get user settings") { request in
	///     return .json(["theme": "dark", "notifications": true])
	/// }
	///
	/// // Mount at /user prefix - endpoints become /user/profile, /user/settings
	/// server.mount("/user", router: userRouter)
	/// ```
	///
	/// - Parameters:
	///   - prefix: The path prefix for all routes in this router (e.g., "/user")
	///   - router: The RequestHandler containing the routes to mount
	public func mount(_ prefix: String, router: RequestHandler) {
		self.requestHandler.mount(prefix, router: router)
	}

	/// Register a custom endpoint using subscript syntax
	public subscript(path: String) -> RouteHandler? {
		get {
			return self.requestHandler[path]
		}
		set {
			self.requestHandler[path] = newValue
		}
	}

	// MARK: - Logging

	/// Access the shared log store for the current session
	/// Use this to send logs from your app that can be retrieved via the /logs API
	///
	/// Example integration with a custom logging system:
	/// ```swift
	/// // In your app's logging setup
	/// debugLogMonitor = { message in
	///     AppXplorerServer.log.log(message)
	/// }
	/// ```
	public static var log: LogStore {
		return LogStore.shared
	}

	/// Convenience method to log a message with optional type
	public static func log(_ message: String, type: String = "") {
		LogStore.shared.log(message, type: type)
	}

	// MARK: - Helpers

	/// Get the device's WiFi IP address
	public func getWiFiAddress() -> String? {
		var address: String?

		// Get list of all interfaces on the local machine
		var ifaddr: UnsafeMutablePointer<ifaddrs>?
		guard getifaddrs(&ifaddr) == 0 else { return nil }

		guard let firstAddr = ifaddr else { return nil }

		// For each interface
		for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
			let interface: ifaddrs = ifptr.pointee

			// Check for IPv4 interface
			let addrFamily: sa_family_t = interface.ifa_addr.pointee.sa_family
			if addrFamily == UInt8(AF_INET) {
				// Check interface name
				let name: String = .init(cString: interface.ifa_name)
				if name == "en0" { // WiFi interface

					// Convert interface address to a human readable string
					var hostname: [CChar] = .init(repeating: 0, count: Int(NI_MAXHOST))
					getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
					            &hostname, socklen_t(hostname.count),
					            nil, socklen_t(0), NI_NUMERICHOST)
					address = String(cString: hostname)
				}
			}
		}

		freeifaddrs(ifaddr)
		return address
	}
}
