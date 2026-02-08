import Foundation

// MARK: - RootRouter

/// Configures the root router with all built-in endpoints and sub-routers
public enum RootRouter {
	/// Register all built-in endpoints with the request handler
	public static func registerAll(with handler: RequestHandler) {
		// Set the root router description
		handler.description = "AppXplorer Debug Server"

		// Register the index endpoint
		self.registerIndex(with: handler)

		// Register top-level endpoints
		InfoEndpoints.register(with: handler)

		// Mount sub-routers
		let filesRouter: RequestHandler = FilesEndpoints.createRouter()
		handler.mount("/files", router: filesRouter)

		let hierarchyRouter: RequestHandler = HierarchyEndpoints.createRouter()
		handler.mount("/hierarchy", router: hierarchyRouter)

		let userDefaultsRouter: RequestHandler = UserDefaultsEndpoints.createRouter()
		handler.mount("/userdefaults", router: userDefaultsRouter)

		let permissionsRouter: RequestHandler = PermissionsEndpoints.createRouter()
		handler.mount("/permissions", router: permissionsRouter)
	}

	// MARK: - Index

	private static func registerIndex(with handler: RequestHandler) {
		handler.register(
			"/",
			description: "API index and discovery. Lists all available endpoints and sub-routers with their descriptions. Use depth=shallow to only show sub-router summaries instead of their full endpoints.",
			parameters: [
				ParameterInfo(
					name: "depth",
					description: "Level of detail for sub-routers. 'deep' recursively includes all sub-router endpoints, 'shallow' only shows sub-router path/description/count.",
					required: false,
					defaultValue: "deep",
					examples: ["deep", "shallow"]
				),
			]
		) { request in
			// Check for depth parameter (default to deep)
			let depth: String = request.queryParams["depth"] ?? "deep"
			let isDeep: Bool = depth.lowercased() != "shallow"

			return .json(handler.routerInfo(deep: isDeep))
		}
	}
}
