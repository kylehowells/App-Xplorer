import Foundation
#if canImport(UIKit)
	import UIKit
#endif

// MARK: - HierarchyEndpoints

/// View hierarchy inspection endpoints
public enum HierarchyEndpoints {
	/// Create a router for hierarchy endpoints
	public static func createRouter() -> RequestHandler {
		let router: RequestHandler = .init(description: "Inspect UIKit view hierarchy, responder chain, and first responder")

		// Register index for this sub-router
		router.register("/", description: "List all hierarchy endpoints") { _ in
			return .json(router.routerInfo(deep: true))
		}

		self.registerHierarchy(with: router)
		self.registerWindows(with: router)
		self.registerWindowScenes(with: router)
		self.registerViewControllers(with: router)
		self.registerResponderChain(with: router)
		self.registerFirstResponder(with: router)

		return router
	}

	// MARK: - Main Hierarchy

	private static func registerHierarchy(with handler: RequestHandler) {
		handler.register(
			"/views",
			description: "Get the complete view hierarchy tree. Returns nested JSON or XML (HTML-like) format showing parent-child relationships.",
			parameters: [
				ParameterInfo(
					name: "window",
					description: "Index of window to inspect (0-based). Omit to get all windows.",
					required: false,
					examples: ["0", "1"]
				),
				ParameterInfo(
					name: "maxDepth",
					description: "Maximum depth to traverse. 0 = unlimited.",
					required: false,
					defaultValue: "0",
					examples: ["5", "10", "0"]
				),
				ParameterInfo(
					name: "includeHidden",
					description: "Include hidden views in the hierarchy",
					required: false,
					defaultValue: "false",
					examples: ["true", "false"]
				),
				ParameterInfo(
					name: "includePrivate",
					description: "Include private UIKit views (prefixed with _)",
					required: false,
					defaultValue: "true",
					examples: ["true", "false"]
				),
				ParameterInfo(
					name: "properties",
					description: "Level of property detail: minimal, standard, or full",
					required: false,
					defaultValue: "standard",
					examples: ["minimal", "standard", "full"]
				),
				ParameterInfo(
					name: "format",
					description: "Output format: 'json' for structured data, 'xml' for HTML-like DOM tree",
					required: false,
					defaultValue: "json",
					examples: ["json", "xml"]
				),
			]
		) { request in
			#if canImport(UIKit)
				let windowIndex: Int? = request.queryParams["window"].flatMap { Int($0) }
				let maxDepth: Int = request.queryParams["maxDepth"].flatMap { Int($0) } ?? 0
				let includeHidden: Bool = request.queryParams["includeHidden"] == "true"
				let includePrivate: Bool = request.queryParams["includePrivate"] != "false"
				let properties: String = request.queryParams["properties"] ?? "standard"
				let format: String = request.queryParams["format"]?.lowercased() ?? "json"

				let windows: [UIWindow] = self.getAllWindows()

				// XML format output
				if format == "xml" {
					var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"

					if let index = windowIndex {
						guard index >= 0, index < windows.count else {
							return .error("Window index \(index) out of range (0-\(windows.count - 1))", status: .badRequest)
						}
						let window = windows[index]
						xml += self.serializeViewAsXML(
							window,
							depth: 0,
							maxDepth: maxDepth,
							includeHidden: includeHidden,
							includePrivate: includePrivate,
							properties: properties,
							indent: 0
						)
					}
					else {
						xml += "<Windows count=\"\(windows.count)\">\n"
						for (index, window) in windows.enumerated() {
							xml += "  <!-- Window \(index) -->\n"
							xml += self.serializeViewAsXML(
								window,
								depth: 0,
								maxDepth: maxDepth,
								includeHidden: includeHidden,
								includePrivate: includePrivate,
								properties: properties,
								indent: 1
							)
						}
						xml += "</Windows>\n"
					}

					return Response(
						status: .ok,
						contentType: ContentType(rawValue: "application/xml") ?? .json,
						body: Data(xml.utf8)
					)
				}

				// JSON format output (default)
				if let index = windowIndex {
					guard index >= 0, index < windows.count else {
						return .error("Window index \(index) out of range (0-\(windows.count - 1))", status: .badRequest)
					}

					let window: UIWindow = windows[index]
					let result: [String: Any] = self.serializeView(
						window,
						depth: 0,
						maxDepth: maxDepth,
						includeHidden: includeHidden,
						includePrivate: includePrivate,
						properties: properties
					)
					return .json(result)
				}
				else {
					var windowsInfo: [[String: Any]] = []
					for (index, window) in windows.enumerated() {
						var windowInfo: [String: Any] = self.serializeView(
							window,
							depth: 0,
							maxDepth: maxDepth,
							includeHidden: includeHidden,
							includePrivate: includePrivate,
							properties: properties
						)
						windowInfo["windowIndex"] = index
						windowsInfo.append(windowInfo)
					}
					return .json([
						"windowCount": windows.count,
						"windows": windowsInfo,
					])
				}
			#else
				return .error("Hierarchy inspection is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - Windows

	private static func registerWindows(with handler: RequestHandler) {
		handler.register(
			"/windows",
			description: "List all windows with their scenes, levels, and basic properties.",
			parameters: [
				ParameterInfo(
					name: "includeHidden",
					description: "Include hidden windows",
					required: false,
					defaultValue: "false",
					examples: ["true", "false"]
				),
			]
		) { request in
			#if canImport(UIKit)
				let includeHidden: Bool = request.queryParams["includeHidden"] == "true"

				let windows: [UIWindow] = self.getAllWindows()
				var result: [[String: Any]] = []

				for (index, window) in windows.enumerated() {
					if !includeHidden, window.isHidden {
						continue
					}

					var windowInfo: [String: Any] = [
						"index": index,
						"class": String(describing: type(of: window)),
						"frame": self.frameToDict(window.frame),
						"windowLevel": window.windowLevel.rawValue,
						"isHidden": window.isHidden,
						"alpha": window.alpha,
						"isKeyWindow": window.isKeyWindow,
					]

					if let scene = window.windowScene {
						windowInfo["scene"] = [
							"title": scene.title,
							"activationState": self.activationStateString(scene.activationState),
							"interfaceOrientation": self.orientationString(scene.interfaceOrientation),
						]
					}

					if let rootVC = window.rootViewController {
						windowInfo["rootViewController"] = String(describing: type(of: rootVC))
					}

					result.append(windowInfo)
				}

				return .json([
					"count": result.count,
					"windows": result,
				])
			#else
				return .error("Window inspection is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - Window Scenes

	private static func registerWindowScenes(with handler: RequestHandler) {
		handler.register(
			"/window-scenes",
			description: "List all UIWindowScenes with their activation state, windows, and properties.",
			parameters: [
				ParameterInfo(
					name: "includeWindows",
					description: "Include detailed window information for each scene",
					required: false,
					defaultValue: "true",
					examples: ["true", "false"]
				),
			]
		) { request in
			#if canImport(UIKit)
				let includeWindows: Bool = request.queryParams["includeWindows"] != "false"

				let scenes: [UIWindowScene] = UIApplication.shared
					.connectedScenes
					.compactMap { $0 as? UIWindowScene }

				var result: [[String: Any]] = []

				for scene in scenes {
					var sceneInfo: [String: Any] = [
						"title": scene.title,
						"activationState": self.activationStateString(scene.activationState),
						"interfaceOrientation": self.orientationString(scene.interfaceOrientation),
						"traitCollectionDescription": scene.traitCollection.description,
					]

					// Add session info
					sceneInfo["session"] = [
						"role": scene.session.role.rawValue,
						"persistentIdentifier": scene.session.persistentIdentifier,
						"userActivityType": scene.session.stateRestorationActivity?.activityType as Any,
					]

					// Add screen info
					let screen = scene.screen
					sceneInfo["screen"] = [
						"bounds": self.frameToDict(screen.bounds),
						"scale": screen.scale,
						"nativeScale": screen.nativeScale,
						"brightness": screen.brightness,
					]

					// Add coordinate space info
					sceneInfo["coordinateSpace"] = self.frameToDict(scene.coordinateSpace.bounds)

					// Add size restrictions
					let minWidth: CGFloat = scene.sizeRestrictions?.minimumSize.width ?? 0
					let minHeight: CGFloat = scene.sizeRestrictions?.minimumSize.height ?? 0
					let maxWidth: CGFloat = scene.sizeRestrictions?.maximumSize.width ?? 0
					let maxHeight: CGFloat = scene.sizeRestrictions?.maximumSize.height ?? 0
					sceneInfo["sizeRestrictions"] = [
						"minimumSize": [
							"width": minWidth,
							"height": minHeight,
						],
						"maximumSize": [
							"width": maxWidth,
							"height": maxHeight,
						],
					]

					// Add window info if requested
					if includeWindows {
						var windowsInfo: [[String: Any]] = []
						for window in scene.windows {
							windowsInfo.append([
								"class": String(describing: type(of: window)),
								"frame": self.frameToDict(window.frame),
								"windowLevel": window.windowLevel.rawValue,
								"isHidden": window.isHidden,
								"isKeyWindow": window.isKeyWindow,
								"rootViewController": window.rootViewController.map { String(describing: type(of: $0)) } ?? "none",
							])
						}
						sceneInfo["windowCount"] = scene.windows.count
						sceneInfo["windows"] = windowsInfo
					}
					else {
						sceneInfo["windowCount"] = scene.windows.count
					}

					result.append(sceneInfo)
				}

				return .json([
					"count": result.count,
					"scenes": result,
				])
			#else
				return .error("Window scene inspection is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - View Controllers

	private static func registerViewControllers(with handler: RequestHandler) {
		handler.register(
			"/view-controllers",
			description: "Get the view controller hierarchy. Shows presented/child relationships.",
			parameters: [
				ParameterInfo(
					name: "window",
					description: "Index of window to inspect (0-based). Omit for all windows.",
					required: false,
					examples: ["0", "1"]
				),
				ParameterInfo(
					name: "maxDepth",
					description: "Maximum depth to traverse. 0 = unlimited.",
					required: false,
					defaultValue: "0",
					examples: ["5", "10", "0"]
				),
			]
		) { request in
			#if canImport(UIKit)
				let windowIndex: Int? = request.queryParams["window"].flatMap { Int($0) }
				let maxDepth: Int = request.queryParams["maxDepth"].flatMap { Int($0) } ?? 0

				let windows: [UIWindow] = self.getAllWindows()

				if let index = windowIndex {
					guard index >= 0, index < windows.count else {
						return .error("Window index \(index) out of range", status: .badRequest)
					}

					let window: UIWindow = windows[index]
					if let rootVC = window.rootViewController {
						return .json(self.serializeViewController(rootVC, depth: 0, maxDepth: maxDepth))
					}
					else {
						return .error("Window has no root view controller", status: .badRequest)
					}
				}
				else {
					var vcHierarchies: [[String: Any]] = []
					for (index, window) in windows.enumerated() {
						if let rootVC = window.rootViewController {
							var vcInfo: [String: Any] = self.serializeViewController(rootVC, depth: 0, maxDepth: maxDepth)
							vcInfo["windowIndex"] = index
							vcHierarchies.append(vcInfo)
						}
					}
					return .json([
						"count": vcHierarchies.count,
						"viewControllers": vcHierarchies,
					])
				}
			#else
				return .error("View controller inspection is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - Responder Chain

	private static func registerResponderChain(with handler: RequestHandler) {
		handler.register(
			"/responder-chain",
			description: "Get the responder chain starting from a specific view or the first responder. Shows the complete chain up to UIApplication.",
			parameters: [
				ParameterInfo(
					name: "from",
					description: "Starting point: 'first-responder' or a view's memory address (e.g., '0x12345678')",
					required: false,
					defaultValue: "first-responder",
					examples: ["first-responder", "0x12345678"]
				),
			]
		) { request in
			#if canImport(UIKit)
				let from: String = request.queryParams["from"] ?? "first-responder"

				var startResponder: UIResponder?

				if from == "first-responder" {
					startResponder = self.findFirstResponder()
				}
				else if from.hasPrefix("0x") {
					// Use SafeAddressLookup to validate and retrieve the responder
					if let address = SafeAddressLookup.parseAddress(from) {
						startResponder = SafeAddressLookup.responder(at: address)
					}
				}

				if let responder = startResponder {
					var chain: [[String: Any]] = []
					var current: UIResponder? = responder

					while let r = current {
						chain.append(self.serializeResponder(r))
						current = r.next
					}

					return .json([
						"startingFrom": self.serializeResponder(responder),
						"chainLength": chain.count,
						"chain": chain,
					])
				}
				else {
					return .json([
						"error": "No responder found",
						"message": from == "first-responder" ? "No view is currently first responder" : "Could not find responder at address \(from)",
					])
				}
			#else
				return .error("Responder chain inspection is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - First Responder

	private static func registerFirstResponder(with handler: RequestHandler) {
		handler.register(
			"/first-responder",
			description: "Get the current first responder and its hierarchy path from the window down to it.",
			parameters: [
				ParameterInfo(
					name: "includeProperties",
					description: "Include detailed properties for each element in the path",
					required: false,
					defaultValue: "true",
					examples: ["true", "false"]
				),
			]
		) { request in
			#if canImport(UIKit)
				let includeProperties: Bool = request.queryParams["includeProperties"] != "false"

				if let firstResponder = self.findFirstResponder() {
					// Build path from first responder up to window
					var pathUp: [[String: Any]] = []
					var current: UIResponder? = firstResponder

					while let r = current {
						if includeProperties {
							pathUp.append(self.serializeResponder(r))
						}
						else {
							pathUp.append([
								"class": String(describing: type(of: r)),
								"address": String(format: "0x%lx", unsafeBitCast(r, to: Int.self)),
							])
						}

						if r is UIWindow {
							break
						}
						current = r.next
					}

					// Reverse to get path from window down to first responder
					let pathDown: [[String: Any]] = pathUp.reversed()

					var result: [String: Any] = [
						"hasFirstResponder": true,
						"firstResponder": self.serializeResponder(firstResponder),
						"pathLength": pathDown.count,
						"pathFromWindow": pathDown,
					]

					// Add useful info about the first responder
					if let view = firstResponder as? UIView {
						result["viewInfo"] = [
							"frame": self.frameToDict(view.frame),
							"bounds": self.frameToDict(view.bounds),
							"isUserInteractionEnabled": view.isUserInteractionEnabled,
							"canBecomeFirstResponder": view.canBecomeFirstResponder,
							"canResignFirstResponder": view.canResignFirstResponder,
						]
					}

					if let textField = firstResponder as? UITextField {
						result["textFieldInfo"] = [
							"text": textField.text ?? "",
							"placeholder": textField.placeholder ?? "",
							"isSecureTextEntry": textField.isSecureTextEntry,
							"keyboardType": self.keyboardTypeString(textField.keyboardType),
						]
					}
					else if let textView = firstResponder as? UITextView {
						result["textViewInfo"] = [
							"text": String(textView.text.prefix(100)),
							"isEditable": textView.isEditable,
							"isSelectable": textView.isSelectable,
						]
					}

					return .json(result)
				}
				else {
					return .json([
						"hasFirstResponder": false,
						"message": "No view is currently first responder",
					])
				}
			#else
				return .error("First responder inspection is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - Helper Methods

	#if canImport(UIKit)
		private static func getAllWindows() -> [UIWindow] {
			let scenes: [UIWindowScene] = UIApplication.shared
				.connectedScenes
				.compactMap { $0 as? UIWindowScene }

			var allWindows: [UIWindow] = []
			for scene in scenes {
				allWindows.append(contentsOf: scene.windows)
			}

			return allWindows.sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }
		}

		private static func findFirstResponder() -> UIResponder? {
			for window in self.getAllWindows() {
				if let responder = self.findFirstResponder(in: window) {
					return responder
				}
			}
			return nil
		}

		private static func findFirstResponder(in view: UIView) -> UIResponder? {
			if view.isFirstResponder {
				return view
			}
			for subview in view.subviews {
				if let responder = self.findFirstResponder(in: subview) {
					return responder
				}
			}
			return nil
		}

		private static func serializeView(
			_ view: UIView,
			depth: Int,
			maxDepth: Int,
			includeHidden: Bool,
			includePrivate: Bool,
			properties: String
		) -> [String: Any] {
			let className: String = .init(describing: type(of: view))

			// Filter private views if requested
			if !includePrivate, className.hasPrefix("_") {
				return [:]
			}

			var info: [String: Any] = [
				"class": className,
				"address": String(format: "0x%lx", unsafeBitCast(view, to: Int.self)),
			]

			// Add properties based on level
			if properties != "minimal" {
				info["frame"] = self.frameToDict(view.frame)
				info["isHidden"] = view.isHidden
				info["alpha"] = view.alpha
				info["tag"] = view.tag
				info["isUserInteractionEnabled"] = view.isUserInteractionEnabled

				if properties == "full" {
					info["bounds"] = self.frameToDict(view.bounds)
					info["backgroundColor"] = self.colorToString(view.backgroundColor)
					info["clipsToBounds"] = view.clipsToBounds
					info["isOpaque"] = view.isOpaque
					info["contentMode"] = self.contentModeString(view.contentMode)
					info["tintColor"] = self.colorToString(view.tintColor)
					info["isFirstResponder"] = view.isFirstResponder
					info["accessibilityIdentifier"] = view.accessibilityIdentifier
					info["accessibilityLabel"] = view.accessibilityLabel

					if let label = view as? UILabel {
						info["text"] = label.text
						info["font"] = label.font.fontName
						info["fontSize"] = label.font.pointSize
					}
					else if let button = view as? UIButton {
						info["title"] = button.title(for: .normal)
						info["isEnabled"] = button.isEnabled
					}
					else if let textField = view as? UITextField {
						info["text"] = textField.text
						info["placeholder"] = textField.placeholder
					}
					else if let imageView = view as? UIImageView {
						info["hasImage"] = imageView.image != nil
						info["isAnimating"] = imageView.isAnimating
					}
				}
			}

			// Add subviews if not at max depth
			if maxDepth == 0 || depth < maxDepth {
				var subviewsInfo: [[String: Any]] = []
				for subview in view.subviews {
					if !includeHidden, subview.isHidden {
						continue
					}
					let subviewInfo: [String: Any] = self.serializeView(
						subview,
						depth: depth + 1,
						maxDepth: maxDepth,
						includeHidden: includeHidden,
						includePrivate: includePrivate,
						properties: properties
					)
					if !subviewInfo.isEmpty {
						subviewsInfo.append(subviewInfo)
					}
				}
				if !subviewsInfo.isEmpty {
					info["subviews"] = subviewsInfo
					info["subviewCount"] = subviewsInfo.count
				}
			}

			return info
		}

		/// Serialize a view hierarchy as XML (HTML-like DOM tree)
		private static func serializeViewAsXML(
			_ view: UIView,
			depth: Int,
			maxDepth: Int,
			includeHidden: Bool,
			includePrivate: Bool,
			properties: String,
			indent: Int
		) -> String {
			let className = String(describing: type(of: view))

			// Filter private views if requested
			if !includePrivate, className.hasPrefix("_") {
				return ""
			}

			let indentStr = String(repeating: "  ", count: indent)
			let address = String(format: "0x%lx", unsafeBitCast(view, to: Int.self))

			// Build attributes
			var attrs: [String] = []
			attrs.append("address=\"\(address)\"")

			if properties != "minimal" {
				let frame = view.frame
				attrs.append("frame=\"\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.size.width)),\(Int(frame.size.height))\"")

				if view.isHidden {
					attrs.append("hidden=\"true\"")
				}
				if view.alpha < 1.0 {
					attrs.append("alpha=\"\(String(format: "%.2f", view.alpha))\"")
				}
				if view.tag != 0 {
					attrs.append("tag=\"\(view.tag)\"")
				}
				if !view.isUserInteractionEnabled {
					attrs.append("userInteraction=\"false\"")
				}

				// Always include accessibility ID if present (useful for test automation)
				if let aid = view.accessibilityIdentifier, !aid.isEmpty {
					attrs.append("accessibilityId=\"\(self.escapeXML(aid))\"")
				}

				// Always include text content (clipped to 40 chars) for common controls
				let maxTextLength = 40
				if let label = view as? UILabel, let text = label.text, !text.isEmpty {
					let clipped = text.count > maxTextLength ? String(text.prefix(maxTextLength)) + "..." : text
					attrs.append("text=\"\(self.escapeXML(clipped))\"")
				}
				else if let button = view as? UIButton, let title = button.title(for: .normal), !title.isEmpty {
					let clipped = title.count > maxTextLength ? String(title.prefix(maxTextLength)) + "..." : title
					attrs.append("title=\"\(self.escapeXML(clipped))\"")
				}
				else if let textField = view as? UITextField {
					if let text = textField.text, !text.isEmpty {
						let clipped = text.count > maxTextLength ? String(text.prefix(maxTextLength)) + "..." : text
						attrs.append("text=\"\(self.escapeXML(clipped))\"")
					}
					if let placeholder = textField.placeholder, !placeholder.isEmpty {
						let clipped = placeholder.count > maxTextLength ? String(placeholder.prefix(maxTextLength)) + "..." : placeholder
						attrs.append("placeholder=\"\(self.escapeXML(clipped))\"")
					}
				}
				else if let textView = view as? UITextView, let text = textView.text, !text.isEmpty {
					let clipped = text.count > maxTextLength ? String(text.prefix(maxTextLength)) + "..." : text
					attrs.append("text=\"\(self.escapeXML(clipped))\"")
				}
				else if let searchBar = view as? UISearchBar {
					if let text = searchBar.text, !text.isEmpty {
						let clipped = text.count > maxTextLength ? String(text.prefix(maxTextLength)) + "..." : text
						attrs.append("text=\"\(self.escapeXML(clipped))\"")
					}
					if let placeholder = searchBar.placeholder, !placeholder.isEmpty {
						let clipped = placeholder.count > maxTextLength ? String(placeholder.prefix(maxTextLength)) + "..." : placeholder
						attrs.append("placeholder=\"\(self.escapeXML(clipped))\"")
					}
				}
				else if let segmented = view as? UISegmentedControl {
					let selectedIndex = segmented.selectedSegmentIndex
					if selectedIndex != UISegmentedControl.noSegment,
					   let title = segmented.titleForSegment(at: selectedIndex)
					{
						attrs.append("selectedTitle=\"\(self.escapeXML(title))\"")
					}
					attrs.append("selectedIndex=\"\(selectedIndex)\"")
				}
				else if let uiSwitch = view as? UISwitch {
					attrs.append("isOn=\"\(uiSwitch.isOn)\"")
				}
				else if let slider = view as? UISlider {
					attrs.append("value=\"\(String(format: "%.1f", slider.value))\"")
				}
				else if let stepper = view as? UIStepper {
					attrs.append("value=\"\(String(format: "%.0f", stepper.value))\"")
				}
				else if let progress = view as? UIProgressView {
					attrs.append("progress=\"\(String(format: "%.2f", progress.progress))\"")
				}
				else if let imageView = view as? UIImageView {
					attrs.append("hasImage=\"\(imageView.image != nil)\"")
				}
				else if let scrollView = view as? UIScrollView {
					attrs.append("contentOffset=\"\(Int(scrollView.contentOffset.x)),\(Int(scrollView.contentOffset.y))\"")
					attrs.append("contentSize=\"\(Int(scrollView.contentSize.width)),\(Int(scrollView.contentSize.height))\"")
				}

				// Full mode adds extra details
				if properties == "full" {
					if let label = view.accessibilityLabel, !label.isEmpty {
						attrs.append("accessibilityLabel=\"\(self.escapeXML(label))\"")
					}
					if view.isFirstResponder {
						attrs.append("firstResponder=\"true\"")
					}
				}
			}

			let attrStr = attrs.isEmpty ? "" : " " + attrs.joined(separator: " ")

			// Get subviews
			var subviewsXML = ""
			if maxDepth == 0 || depth < maxDepth {
				for subview in view.subviews {
					if !includeHidden, subview.isHidden {
						continue
					}
					let subXML = self.serializeViewAsXML(
						subview,
						depth: depth + 1,
						maxDepth: maxDepth,
						includeHidden: includeHidden,
						includePrivate: includePrivate,
						properties: properties,
						indent: indent + 1
					)
					subviewsXML += subXML
				}
			}

			// Output as self-closing tag if no children, or with children
			if subviewsXML.isEmpty {
				return "\(indentStr)<\(className)\(attrStr) />\n"
			}
			else {
				return "\(indentStr)<\(className)\(attrStr)>\n\(subviewsXML)\(indentStr)</\(className)>\n"
			}
		}

		/// Escape special XML characters
		private static func escapeXML(_ string: String) -> String {
			var result = string
			result = result.replacingOccurrences(of: "&", with: "&amp;")
			result = result.replacingOccurrences(of: "<", with: "&lt;")
			result = result.replacingOccurrences(of: ">", with: "&gt;")
			result = result.replacingOccurrences(of: "\"", with: "&quot;")
			result = result.replacingOccurrences(of: "'", with: "&apos;")
			result = result.replacingOccurrences(of: "\n", with: "&#10;")
			result = result.replacingOccurrences(of: "\r", with: "&#13;")
			return result
		}

		private static func serializeViewController(_ vc: UIViewController, depth: Int, maxDepth: Int) -> [String: Any] {
			var info: [String: Any] = [
				"class": String(describing: type(of: vc)),
				"address": String(format: "0x%lx", unsafeBitCast(vc, to: Int.self)),
				"title": vc.title ?? "",
				"isViewLoaded": vc.isViewLoaded,
			]

			if vc.isViewLoaded {
				info["viewFrame"] = self.frameToDict(vc.view.frame)
			}

			// Add presented view controller
			if let presented = vc.presentedViewController {
				info["presentedViewController"] = self.serializeViewController(presented, depth: depth + 1, maxDepth: maxDepth)
			}

			// Add child view controllers
			if !vc.children.isEmpty, (maxDepth == 0 || depth < maxDepth) {
				var children: [[String: Any]] = []
				for child in vc.children {
					children.append(self.serializeViewController(child, depth: depth + 1, maxDepth: maxDepth))
				}
				info["children"] = children
				info["childCount"] = children.count
			}

			// Add navigation controller info
			if let navVC = vc as? UINavigationController {
				info["viewControllerCount"] = navVC.viewControllers.count
				if maxDepth == 0 || depth < maxDepth {
					info["viewControllers"] = navVC.viewControllers.map {
						self.serializeViewController($0, depth: depth + 1, maxDepth: maxDepth)
					}
				}
			}

			// Add tab bar controller info
			if let tabVC = vc as? UITabBarController {
				info["selectedIndex"] = tabVC.selectedIndex
				if let viewControllers = tabVC.viewControllers {
					info["tabCount"] = viewControllers.count
					if maxDepth == 0 || depth < maxDepth {
						info["tabs"] = viewControllers.map {
							self.serializeViewController($0, depth: depth + 1, maxDepth: maxDepth)
						}
					}
				}
			}

			// Add split view controller info
			if let splitVC = vc as? UISplitViewController {
				info["isCollapsed"] = splitVC.isCollapsed
				info["displayMode"] = self.splitDisplayModeString(splitVC.displayMode)
			}

			return info
		}

		private static func serializeResponder(_ responder: UIResponder) -> [String: Any] {
			var info: [String: Any] = [
				"class": String(describing: type(of: responder)),
				"address": String(format: "0x%lx", unsafeBitCast(responder, to: Int.self)),
			]

			if let view = responder as? UIView {
				info["type"] = "view"
				info["frame"] = self.frameToDict(view.frame)
				info["isFirstResponder"] = view.isFirstResponder

				if let window = view as? UIWindow {
					info["type"] = "window"
					info["windowLevel"] = window.windowLevel.rawValue
					info["isKeyWindow"] = window.isKeyWindow
				}
			}
			else if let vc = responder as? UIViewController {
				info["type"] = "viewController"
				info["title"] = vc.title
			}
			else if responder is UIApplication {
				info["type"] = "application"
			}
			else if let scene = responder as? UIWindowScene {
				info["type"] = "windowScene"
				info["title"] = scene.title
			}

			return info
		}

		private static func frameToDict(_ frame: CGRect) -> [String: CGFloat] {
			return [
				"x": frame.origin.x,
				"y": frame.origin.y,
				"width": frame.size.width,
				"height": frame.size.height,
			]
		}

		private static func colorToString(_ color: UIColor?) -> String? {
			guard let color = color else { return nil }

			var red: CGFloat = 0
			var green: CGFloat = 0
			var blue: CGFloat = 0
			var alpha: CGFloat = 0

			if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
				return String(format: "rgba(%d, %d, %d, %.2f)", Int(red * 255), Int(green * 255), Int(blue * 255), alpha)
			}
			return color.description
		}

		private static func contentModeString(_ mode: UIView.ContentMode) -> String {
			switch mode {
				case .scaleToFill: return "scaleToFill"

				case .scaleAspectFit: return "scaleAspectFit"

				case .scaleAspectFill: return "scaleAspectFill"

				case .redraw: return "redraw"

				case .center: return "center"

				case .top: return "top"

				case .bottom: return "bottom"

				case .left: return "left"

				case .right: return "right"

				case .topLeft: return "topLeft"

				case .topRight: return "topRight"

				case .bottomLeft: return "bottomLeft"

				case .bottomRight: return "bottomRight"

				@unknown default: return "unknown"
			}
		}

		private static func activationStateString(_ state: UIScene.ActivationState) -> String {
			switch state {
				case .unattached: return "unattached"

				case .foregroundActive: return "foregroundActive"

				case .foregroundInactive: return "foregroundInactive"

				case .background: return "background"

				@unknown default: return "unknown"
			}
		}

		private static func orientationString(_ orientation: UIInterfaceOrientation) -> String {
			switch orientation {
				case .unknown: return "unknown"

				case .portrait: return "portrait"

				case .portraitUpsideDown: return "portraitUpsideDown"

				case .landscapeLeft: return "landscapeLeft"

				case .landscapeRight: return "landscapeRight"

				@unknown default: return "unknown"
			}
		}

		private static func keyboardTypeString(_ type: UIKeyboardType) -> String {
			switch type {
				case .default: return "default"

				case .asciiCapable: return "asciiCapable"

				case .numbersAndPunctuation: return "numbersAndPunctuation"

				case .URL: return "URL"

				case .numberPad: return "numberPad"

				case .phonePad: return "phonePad"

				case .namePhonePad: return "namePhonePad"

				case .emailAddress: return "emailAddress"

				case .decimalPad: return "decimalPad"

				case .twitter: return "twitter"

				case .webSearch: return "webSearch"

				case .asciiCapableNumberPad: return "asciiCapableNumberPad"

				@unknown default: return "unknown"
			}
		}

		private static func splitDisplayModeString(_ mode: UISplitViewController.DisplayMode) -> String {
			switch mode {
				case .automatic: return "automatic"

				case .secondaryOnly: return "secondaryOnly"

				case .oneBesideSecondary: return "oneBesideSecondary"

				case .oneOverSecondary: return "oneOverSecondary"

				case .twoBesideSecondary: return "twoBesideSecondary"

				case .twoOverSecondary: return "twoOverSecondary"

				case .twoDisplaceSecondary: return "twoDisplaceSecondary"

				@unknown default: return "unknown"
			}
		}
	#endif
}
