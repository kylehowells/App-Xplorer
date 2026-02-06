import Foundation

// MARK: - BuiltInEndpoints

/// Built-in endpoints for AppXplorerServer
public enum BuiltInEndpoints {
	/// Register all built-in endpoints with the request handler
	public static func registerAll(with handler: RequestHandler) {
		// Set the root router description
		handler.description = "AppXplorer Debug Server"

		// Register the index endpoint
		self.registerIndex(with: handler)

		// Register top-level endpoints
		InfoEndpoints.register(with: handler)
		UserDefaultsEndpoints.register(with: handler)

		// Mount sub-routers
		let filesRouter: RequestHandler = FilesEndpoints.createRouter()
		handler.mount("/files", router: filesRouter)
	}

	// MARK: - Index

	private static func registerIndex(with handler: RequestHandler) {
		handler.register("/", description: "API index and discovery") { request in
			// Check for depth parameter
			let depth: String = request.queryParams["depth"] ?? "shallow"
			let isDeep: Bool = depth.lowercased() == "deep"

			return .json(handler.routerInfo(deep: isDeep))
		}
	}
}
