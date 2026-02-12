import Foundation
#if canImport(UIKit)
	import UIKit
#endif

// MARK: - InteractEndpoints

/// UI interaction endpoints for tapping, typing, scrolling, and other user interactions
public enum InteractEndpoints {
	/// Create a router for interaction endpoints
	public static func createRouter() -> RequestHandler {
		let router: RequestHandler = .init(description: "Interact with UI elements: tap buttons, type text, scroll views, and trigger gestures")

		// Register index for this sub-router
		router.register("/", description: "List all interaction endpoints") { _ in
			return .json(router.routerInfo(deep: true))
		}

		self.registerTap(with: router)
		self.registerType(with: router)
		self.registerFocus(with: router)
		self.registerResign(with: router)
		self.registerScroll(with: router)
		self.registerSwipe(with: router)
		self.registerAccessibility(with: router)

		return router
	}

	// MARK: - Tap

	private static func registerTap(with handler: RequestHandler) {
		handler.register(
			"/tap",
			description: "Tap a UI element. Works on UIControl subclasses (buttons, switches, etc.) by triggering touchUpInside, or uses accessibility activation for other views.",
			parameters: [
				ParameterInfo(
					name: "address",
					description: "Memory address of the view to tap (e.g., '0x12345678'). Get addresses from /hierarchy/views.",
					required: true,
					examples: ["0x12345678"]
				),
			]
		) { request in
			#if canImport(UIKit)
				guard let addressString = request.queryParams["address"] else {
					return .error("Missing required parameter: address", status: .badRequest)
				}

				guard let address = SafeAddressLookup.parseAddress(addressString) else {
					return .error("Invalid address format: \(addressString)", status: .badRequest)
				}

				guard let view = SafeAddressLookup.view(at: address) else {
					return .error("No valid UIView found at address \(addressString)", status: .notFound)
				}

				// Check if view is interactable
				guard view.isUserInteractionEnabled else {
					return .error("View has userInteractionEnabled = false", status: .badRequest)
				}

				guard !view.isHidden else {
					return .error("View is hidden", status: .badRequest)
				}

				var result: [String: Any] = [
					"address": addressString,
					"class": String(describing: type(of: view)),
				]

				// Handle UIControl subclasses (buttons, switches, etc.)
				if let control = view as? UIControl {
					control.sendActions(for: .touchUpInside)
					result["action"] = "sendActions(for: .touchUpInside)"
					result["success"] = true
					result["controlState"] = self.controlStateString(control.state)

					if let button = control as? UIButton {
						result["buttonTitle"] = button.title(for: .normal)
					}
					else if let uiSwitch = control as? UISwitch {
						result["switchIsOn"] = uiSwitch.isOn
					}
				}
				// Try accessibility activation for other views
				else if view.accessibilityActivate() {
					result["action"] = "accessibilityActivate()"
					result["success"] = true
				}
				// Check for tap gesture recognizers
				else if let tapGesture = view.gestureRecognizers?.first(where: { $0 is UITapGestureRecognizer }) as? UITapGestureRecognizer {
					// Trigger the gesture recognizer's targets
					if let targets = tapGesture.value(forKey: "_targets") as? [AnyObject] {
						for target in targets {
							if let action = target.value(forKey: "_action") as? Selector,
							   let targetObj = target.value(forKey: "_target") as? NSObject
							{
								targetObj.perform(action, with: tapGesture)
								result["action"] = "tapGestureRecognizer triggered"
								result["success"] = true
								break
							}
						}
					}
					else {
						result["action"] = "tapGestureRecognizer found but could not trigger"
						result["success"] = false
					}
				}
				else {
					result["action"] = "none available"
					result["success"] = false
					result["error"] = "View is not a UIControl and has no tap gesture recognizers"
				}

				return .json(result)
			#else
				return .error("UI interaction is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - Type Text

	private static func registerType(with handler: RequestHandler) {
		handler.register(
			"/type",
			description: "Type text into the current first responder (text field, text view) or a specific view. Appends text by default, or replaces existing text.",
			parameters: [
				ParameterInfo(
					name: "text",
					description: "The text to type",
					required: true,
					examples: ["Hello, World!", "user@example.com"]
				),
				ParameterInfo(
					name: "address",
					description: "Memory address of the text input view. If omitted, uses the current first responder.",
					required: false,
					examples: ["0x12345678"]
				),
				ParameterInfo(
					name: "mode",
					description: "How to insert text: 'append' adds to existing, 'replace' clears first, 'insert' inserts at cursor",
					required: false,
					defaultValue: "append",
					examples: ["append", "replace", "insert"]
				),
			]
		) { request in
			#if canImport(UIKit)
				guard let text = request.queryParams["text"] else {
					return .error("Missing required parameter: text", status: .badRequest)
				}

				let mode = request.queryParams["mode"] ?? "append"

				// Find the target view
				var targetResponder: UIResponder?

				if let addressString = request.queryParams["address"] {
					guard let address = SafeAddressLookup.parseAddress(addressString) else {
						return .error("Invalid address format: \(addressString)", status: .badRequest)
					}

					targetResponder = SafeAddressLookup.responder(at: address)
					if targetResponder == nil {
						return .error("No valid UIResponder found at address \(addressString)", status: .notFound)
					}
				}
				else {
					// Use current first responder
					targetResponder = self.findFirstResponder()
					if targetResponder == nil {
						return .error("No first responder found. Provide an address or focus a text field first.", status: .badRequest)
					}
				}

				var result: [String: Any] = [
					"class": String(describing: type(of: targetResponder!)),
					"address": SafeAddressLookup.addressString(of: targetResponder!),
					"textToType": text,
					"mode": mode,
				]

				// Handle UITextField
				if let textField = targetResponder as? UITextField {
					let previousText = textField.text ?? ""

					switch mode {
						case "replace":
							textField.text = text

						case "insert":
							if let selectedRange = textField.selectedTextRange {
								textField.replace(selectedRange, withText: text)
							}
							else {
								textField.text = (textField.text ?? "") + text
							}

						default: // append
							textField.text = (textField.text ?? "") + text
					}

					result["success"] = true
					result["previousText"] = previousText
					result["newText"] = textField.text

					// Trigger text change notifications
					textField.sendActions(for: .editingChanged)
				}
				// Handle UITextView
				else if let textView = targetResponder as? UITextView {
					let previousText = textView.text ?? ""

					switch mode {
						case "replace":
							textView.text = text

						case "insert":
							if let selectedRange = textView.selectedTextRange {
								textView.replace(selectedRange, withText: text)
							}
							else {
								textView.text = (textView.text ?? "") + text
							}

						default: // append
							textView.text = (textView.text ?? "") + text
					}

					result["success"] = true
					result["previousText"] = String(previousText.prefix(100))
					result["newText"] = String((textView.text ?? "").prefix(100))

					// Trigger delegate notification
					NotificationCenter.default.post(
						name: UITextView.textDidChangeNotification,
						object: textView
					)
				}
				// Handle UISearchBar
				else if let searchBar = targetResponder as? UISearchBar {
					let previousText = searchBar.text ?? ""

					switch mode {
						case "replace":
							searchBar.text = text

						default: // append or insert
							searchBar.text = (searchBar.text ?? "") + text
					}

					result["success"] = true
					result["previousText"] = previousText
					result["newText"] = searchBar.text
				}
				else {
					result["success"] = false
					result["error"] = "Target is not a text input view (UITextField, UITextView, or UISearchBar)"
				}

				return .json(result)
			#else
				return .error("UI interaction is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - Focus

	private static func registerFocus(with handler: RequestHandler) {
		handler.register(
			"/focus",
			description: "Make a view become the first responder (focus it). Useful for activating text fields.",
			parameters: [
				ParameterInfo(
					name: "address",
					description: "Memory address of the view to focus",
					required: true,
					examples: ["0x12345678"]
				),
			]
		) { request in
			#if canImport(UIKit)
				guard let addressString = request.queryParams["address"] else {
					return .error("Missing required parameter: address", status: .badRequest)
				}

				guard let address = SafeAddressLookup.parseAddress(addressString) else {
					return .error("Invalid address format: \(addressString)", status: .badRequest)
				}

				guard let responder = SafeAddressLookup.responder(at: address) else {
					return .error("No valid UIResponder found at address \(addressString)", status: .notFound)
				}

				var result: [String: Any] = [
					"address": addressString,
					"class": String(describing: type(of: responder)),
					"canBecomeFirstResponder": responder.canBecomeFirstResponder,
				]

				if responder.canBecomeFirstResponder {
					let success = responder.becomeFirstResponder()
					result["success"] = success
					result["isFirstResponder"] = responder.isFirstResponder

					if !success {
						result["error"] = "becomeFirstResponder() returned false"
					}
				}
				else {
					result["success"] = false
					result["error"] = "View cannot become first responder"
				}

				return .json(result)
			#else
				return .error("UI interaction is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - Resign

	private static func registerResign(with handler: RequestHandler) {
		handler.register(
			"/resign",
			description: "Make the current first responder resign (dismiss keyboard, unfocus). Optionally target a specific view.",
			parameters: [
				ParameterInfo(
					name: "address",
					description: "Memory address of the view to resign. If omitted, resigns the current first responder.",
					required: false,
					examples: ["0x12345678"]
				),
			]
		) { request in
			#if canImport(UIKit)
				var targetResponder: UIResponder?

				if let addressString = request.queryParams["address"] {
					guard let address = SafeAddressLookup.parseAddress(addressString) else {
						return .error("Invalid address format: \(addressString)", status: .badRequest)
					}

					targetResponder = SafeAddressLookup.responder(at: address)
					if targetResponder == nil {
						return .error("No valid UIResponder found at address \(addressString)", status: .notFound)
					}
				}
				else {
					targetResponder = self.findFirstResponder()
					if targetResponder == nil {
						return .json([
							"success": true,
							"message": "No first responder was active",
						])
					}
				}

				var result: [String: Any] = [
					"class": String(describing: type(of: targetResponder!)),
					"address": SafeAddressLookup.addressString(of: targetResponder!),
					"wasFirstResponder": targetResponder!.isFirstResponder,
				]

				if targetResponder!.isFirstResponder {
					let success = targetResponder!.resignFirstResponder()
					result["success"] = success
					result["isStillFirstResponder"] = targetResponder!.isFirstResponder
				}
				else {
					result["success"] = true
					result["message"] = "View was not first responder"
				}

				return .json(result)
			#else
				return .error("UI interaction is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - Scroll

	private static func registerScroll(with handler: RequestHandler) {
		handler.register(
			"/scroll",
			description: "Scroll a UIScrollView (including table views and collection views) to a specific offset or by a delta.",
			parameters: [
				ParameterInfo(
					name: "address",
					description: "Memory address of the scroll view",
					required: true,
					examples: ["0x12345678"]
				),
				ParameterInfo(
					name: "x",
					description: "Absolute X offset to scroll to, or delta if 'delta=true'",
					required: false,
					examples: ["0", "100", "-50"]
				),
				ParameterInfo(
					name: "y",
					description: "Absolute Y offset to scroll to, or delta if 'delta=true'",
					required: false,
					examples: ["0", "200", "-100"]
				),
				ParameterInfo(
					name: "delta",
					description: "If true, x and y are treated as deltas from current position",
					required: false,
					defaultValue: "false",
					examples: ["true", "false"]
				),
				ParameterInfo(
					name: "animated",
					description: "Whether to animate the scroll",
					required: false,
					defaultValue: "true",
					examples: ["true", "false"]
				),
				ParameterInfo(
					name: "position",
					description: "Scroll to a named position: 'top', 'bottom', 'left', 'right'",
					required: false,
					examples: ["top", "bottom"]
				),
			]
		) { request in
			#if canImport(UIKit)
				guard let addressString = request.queryParams["address"] else {
					return .error("Missing required parameter: address", status: .badRequest)
				}

				guard let address = SafeAddressLookup.parseAddress(addressString) else {
					return .error("Invalid address format: \(addressString)", status: .badRequest)
				}

				guard let view = SafeAddressLookup.view(at: address) else {
					return .error("No valid UIView found at address \(addressString)", status: .notFound)
				}

				guard let scrollView = view as? UIScrollView else {
					return .error("View at address is not a UIScrollView (found: \(type(of: view)))", status: .badRequest)
				}

				let animated = request.queryParams["animated"] != "false"
				let isDelta = request.queryParams["delta"] == "true"

				var result: [String: Any] = [
					"address": addressString,
					"class": String(describing: type(of: scrollView)),
					"previousOffset": [
						"x": scrollView.contentOffset.x,
						"y": scrollView.contentOffset.y,
					],
					"contentSize": [
						"width": scrollView.contentSize.width,
						"height": scrollView.contentSize.height,
					],
					"animated": animated,
				]

				var newOffset = scrollView.contentOffset

				// Handle named positions
				if let position = request.queryParams["position"] {
					switch position {
						case "top":
							newOffset.y = -scrollView.adjustedContentInset.top

						case "bottom":
							let maxY = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
							newOffset.y = max(0, maxY)

						case "left":
							newOffset.x = -scrollView.adjustedContentInset.left

						case "right":
							let maxX = scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right
							newOffset.x = max(0, maxX)

						default:
							return .error("Unknown position: \(position). Use top, bottom, left, or right.", status: .badRequest)
					}
					result["scrollTo"] = position
				}
				else {
					// Handle x/y offsets
					if let xString = request.queryParams["x"], let xDouble = Double(xString) {
						let x = CGFloat(xDouble)
						if isDelta {
							newOffset.x += x
						}
						else {
							newOffset.x = x
						}
					}

					if let yString = request.queryParams["y"], let yDouble = Double(yString) {
						let y = CGFloat(yDouble)
						if isDelta {
							newOffset.y += y
						}
						else {
							newOffset.y = y
						}
					}

					result["isDelta"] = isDelta
				}

				// Clamp to valid range
				let minX = -scrollView.adjustedContentInset.left
				let maxX = max(minX, scrollView.contentSize.width - scrollView.bounds.width + scrollView.adjustedContentInset.right)
				let minY = -scrollView.adjustedContentInset.top
				let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)

				newOffset.x = min(max(newOffset.x, minX), maxX)
				newOffset.y = min(max(newOffset.y, minY), maxY)

				scrollView.setContentOffset(newOffset, animated: animated)

				result["success"] = true
				result["newOffset"] = [
					"x": newOffset.x,
					"y": newOffset.y,
				]

				return .json(result)
			#else
				return .error("UI interaction is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - Swipe

	private static func registerSwipe(with handler: RequestHandler) {
		handler.register(
			"/swipe",
			description: "Trigger a swipe gesture on a view (if it has swipe gesture recognizers) or perform an accessibility scroll action.",
			parameters: [
				ParameterInfo(
					name: "address",
					description: "Memory address of the view to swipe",
					required: true,
					examples: ["0x12345678"]
				),
				ParameterInfo(
					name: "direction",
					description: "Swipe direction",
					required: true,
					examples: ["left", "right", "up", "down"]
				),
			]
		) { request in
			#if canImport(UIKit)
				guard let addressString = request.queryParams["address"] else {
					return .error("Missing required parameter: address", status: .badRequest)
				}

				guard let directionString = request.queryParams["direction"] else {
					return .error("Missing required parameter: direction", status: .badRequest)
				}

				guard let address = SafeAddressLookup.parseAddress(addressString) else {
					return .error("Invalid address format: \(addressString)", status: .badRequest)
				}

				guard let view = SafeAddressLookup.view(at: address) else {
					return .error("No valid UIView found at address \(addressString)", status: .notFound)
				}

				let direction: UISwipeGestureRecognizer.Direction
				let accessibilityDirection: UIAccessibilityScrollDirection

				switch directionString.lowercased() {
					case "left":
						direction = .left
						accessibilityDirection = .left

					case "right":
						direction = .right
						accessibilityDirection = .right

					case "up":
						direction = .up
						accessibilityDirection = .up

					case "down":
						direction = .down
						accessibilityDirection = .down

					default:
						return .error("Invalid direction: \(directionString). Use left, right, up, or down.", status: .badRequest)
				}

				var result: [String: Any] = [
					"address": addressString,
					"class": String(describing: type(of: view)),
					"direction": directionString,
				]

				// Try to find and trigger a matching swipe gesture recognizer
				if let swipeGesture = view.gestureRecognizers?.first(where: {
					guard let swipe = $0 as? UISwipeGestureRecognizer else { return false }
					return swipe.direction.contains(direction)
				}) as? UISwipeGestureRecognizer {
					// Trigger the gesture recognizer's targets
					if let targets = swipeGesture.value(forKey: "_targets") as? [AnyObject] {
						for target in targets {
							if let action = target.value(forKey: "_action") as? Selector,
							   let targetObj = target.value(forKey: "_target") as? NSObject
							{
								targetObj.perform(action, with: swipeGesture)
								result["action"] = "swipeGestureRecognizer triggered"
								result["success"] = true
								return .json(result)
							}
						}
					}
				}

				// Fall back to accessibility scroll
				if view.accessibilityScroll(accessibilityDirection) {
					result["action"] = "accessibilityScroll"
					result["success"] = true
				}
				else {
					result["action"] = "none available"
					result["success"] = false
					result["error"] = "View has no swipe gesture recognizers and accessibilityScroll returned false"
				}

				return .json(result)
			#else
				return .error("UI interaction is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - Accessibility Actions

	private static func registerAccessibility(with handler: RequestHandler) {
		handler.register(
			"/accessibility",
			description: "Perform an accessibility action on a view. Lists available actions if no action is specified.",
			parameters: [
				ParameterInfo(
					name: "address",
					description: "Memory address of the view",
					required: true,
					examples: ["0x12345678"]
				),
				ParameterInfo(
					name: "action",
					description: "Accessibility action to perform. Omit to list available actions.",
					required: false,
					examples: ["activate", "increment", "decrement", "escape", "magicTap"]
				),
			]
		) { request in
			#if canImport(UIKit)
				guard let addressString = request.queryParams["address"] else {
					return .error("Missing required parameter: address", status: .badRequest)
				}

				guard let address = SafeAddressLookup.parseAddress(addressString) else {
					return .error("Invalid address format: \(addressString)", status: .badRequest)
				}

				guard let view = SafeAddressLookup.view(at: address) else {
					return .error("No valid UIView found at address \(addressString)", status: .notFound)
				}

				var result: [String: Any] = [
					"address": addressString,
					"class": String(describing: type(of: view)),
					"accessibilityLabel": view.accessibilityLabel as Any,
					"accessibilityIdentifier": view.accessibilityIdentifier as Any,
					"accessibilityTraits": self.accessibilityTraitsString(view.accessibilityTraits),
				]

				// List available custom actions
				var availableActions: [String] = ["activate", "escape", "magicTap"]

				if view.accessibilityTraits.contains(.adjustable) {
					availableActions.append(contentsOf: ["increment", "decrement"])
				}

				if let customActions = view.accessibilityCustomActions {
					for action in customActions {
						availableActions.append("custom:\(action.name)")
					}
				}

				result["availableActions"] = availableActions

				// Perform action if specified
				if let actionName = request.queryParams["action"] {
					var success = false

					switch actionName {
						case "activate":
							success = view.accessibilityActivate()

						case "increment":
							view.accessibilityIncrement()
							success = true

						case "decrement":
							view.accessibilityDecrement()
							success = true

						case "escape":
							success = view.accessibilityPerformEscape()

						case "magicTap":
							success = view.accessibilityPerformMagicTap()

						default:
							// Check for custom action
							if actionName.hasPrefix("custom:") {
								let customName = String(actionName.dropFirst(7))
								if let customActions = view.accessibilityCustomActions,
								   let action = customActions.first(where: { $0.name == customName })
								{
									// Try to invoke via actionHandler (iOS 13+) or target/selector
									if let handler = action.actionHandler {
										success = handler(action)
									}
									else if let target = action.target {
										let selector = action.selector
										_ = target.perform(selector, with: action)
										success = true
									}
								}
								else {
									return .error("Custom action '\(customName)' not found", status: .badRequest)
								}
							}
							else {
								return .error("Unknown action: \(actionName)", status: .badRequest)
							}
					}

					result["actionPerformed"] = actionName
					result["success"] = success
				}

				return .json(result)
			#else
				return .error("UI interaction is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - Helper Methods

	#if canImport(UIKit)
		private static func findFirstResponder() -> UIResponder? {
			let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

			for scene in scenes {
				for window in scene.windows {
					if let responder = self.findFirstResponder(in: window) {
						return responder
					}
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

		private static func controlStateString(_ state: UIControl.State) -> String {
			var states: [String] = []
			if state.contains(.normal) || state.rawValue == 0 { states.append("normal") }
			if state.contains(.highlighted) { states.append("highlighted") }
			if state.contains(.disabled) { states.append("disabled") }
			if state.contains(.selected) { states.append("selected") }
			if state.contains(.focused) { states.append("focused") }
			return states.isEmpty ? "normal" : states.joined(separator: ", ")
		}

		private static func accessibilityTraitsString(_ traits: UIAccessibilityTraits) -> [String] {
			var result: [String] = []
			if traits.contains(.button) { result.append("button") }
			if traits.contains(.link) { result.append("link") }
			if traits.contains(.image) { result.append("image") }
			if traits.contains(.selected) { result.append("selected") }
			if traits.contains(.playsSound) { result.append("playsSound") }
			if traits.contains(.keyboardKey) { result.append("keyboardKey") }
			if traits.contains(.staticText) { result.append("staticText") }
			if traits.contains(.summaryElement) { result.append("summaryElement") }
			if traits.contains(.notEnabled) { result.append("notEnabled") }
			if traits.contains(.updatesFrequently) { result.append("updatesFrequently") }
			if traits.contains(.searchField) { result.append("searchField") }
			if traits.contains(.startsMediaSession) { result.append("startsMediaSession") }
			if traits.contains(.adjustable) { result.append("adjustable") }
			if traits.contains(.allowsDirectInteraction) { result.append("allowsDirectInteraction") }
			if traits.contains(.causesPageTurn) { result.append("causesPageTurn") }
			if traits.contains(.header) { result.append("header") }
			return result
		}
	#endif
}
