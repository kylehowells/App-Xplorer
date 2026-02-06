import Foundation

// MARK: - UserDefaultsEndpoints

/// UserDefaults inspection endpoints
public enum UserDefaultsEndpoints {
	/// Register UserDefaults endpoints with the request handler
	public static func register(with handler: RequestHandler) {
		self.registerUserDefaults(with: handler)
	}

	// MARK: - UserDefaults

	private static func registerUserDefaults(with handler: RequestHandler) {
		handler.register(
			"/userdefaults",
			description: "View UserDefaults contents"
		) { request in
			let suiteName: String? = request.queryParams["suite"]
			let defaults: UserDefaults

			if let suite: String = suiteName {
				defaults = UserDefaults(suiteName: suite) ?? UserDefaults.standard
			}
			else {
				defaults = UserDefaults.standard
			}

			let dict: [String: Any] = defaults.dictionaryRepresentation()

			// Filter out system keys if requested
			let filterSystem: Bool = request.queryParams["filterSystem"] == "true"

			if filterSystem {
				let filtered: [String: Any] = dict.filter { key, _ in
					!key.hasPrefix("NS") &&
						!key.hasPrefix("Apple") &&
						!key.hasPrefix("com.apple") &&
						!key.hasPrefix("AK")
				}
				return .json(filtered)
			}

			return .json(dict)
		}
	}
}
