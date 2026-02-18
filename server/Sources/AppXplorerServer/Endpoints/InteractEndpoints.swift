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
		self.registerSelectCell(with: router)
		self.registerMenu(with: router)

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
				if let uiSwitch = view as? UISwitch {
					// UISwitch needs to be toggled manually, then valueChanged sent
					let previousState = uiSwitch.isOn
					uiSwitch.setOn(!previousState, animated: true)
					uiSwitch.sendActions(for: .valueChanged)
					result["action"] = "setOn(!isOn) + sendActions(for: .valueChanged)"
					result["success"] = true
					result["previousState"] = previousState
					result["switchIsOn"] = uiSwitch.isOn
				}
				else if let control = view as? UIControl {
					control.sendActions(for: .touchUpInside)
					result["action"] = "sendActions(for: .touchUpInside)"
					result["success"] = true
					result["controlState"] = self.controlStateString(control.state)

					if let button = control as? UIButton {
						result["buttonTitle"] = button.title(for: .normal)
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

					// Trigger all text change notifications
					// 1. Send control event for target-action bindings
					textField.sendActions(for: .editingChanged)

					// 2. Post notification for NotificationCenter observers
					NotificationCenter.default.post(
						name: UITextField.textDidChangeNotification,
						object: textField
					)

					// 3. Call delegate method if implemented
					if let delegate = textField.delegate {
						let selector = #selector(UITextFieldDelegate.textFieldDidChangeSelection(_:))
						if delegate.responds(to: selector) {
							_ = delegate.perform(selector, with: textField)
						}
					}
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

					// Trigger all text change notifications
					// 1. Post notification for NotificationCenter observers
					NotificationCenter.default.post(
						name: UITextView.textDidChangeNotification,
						object: textView
					)

					// 2. Call delegate method if implemented
					if let delegate = textView.delegate {
						let selector = #selector(UITextViewDelegate.textViewDidChange(_:))
						if delegate.responds(to: selector) {
							_ = delegate.perform(selector, with: textView)
						}
					}
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

					// Trigger delegate method for search bar text changes
					if let delegate = searchBar.delegate {
						let selector = #selector(UISearchBarDelegate.searchBar(_:textDidChange:))
						if delegate.responds(to: selector) {
							_ = delegate.perform(selector, with: searchBar, with: searchBar.text ?? "")
						}
					}
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

	// MARK: - Select Cell

	private static func registerSelectCell(with handler: RequestHandler) {
		handler.register(
			"/select-cell",
			description: "Select a cell in a UITableView or UICollectionView by index path. Triggers the appropriate delegate method (didSelectRowAt/didSelectItemAt).",
			parameters: [
				ParameterInfo(
					name: "address",
					description: "Memory address of the UITableView or UICollectionView",
					required: true,
					examples: ["0x12345678"]
				),
				ParameterInfo(
					name: "section",
					description: "Section index (0-based)",
					required: false,
					defaultValue: "0",
					examples: ["0", "1", "2"]
				),
				ParameterInfo(
					name: "row",
					description: "Row index for UITableView (0-based)",
					required: false,
					examples: ["0", "5", "10"]
				),
				ParameterInfo(
					name: "item",
					description: "Item index for UICollectionView (0-based). Use 'row' or 'item' interchangeably.",
					required: false,
					examples: ["0", "5", "10"]
				),
				ParameterInfo(
					name: "scroll",
					description: "Whether to scroll to make the cell visible before selecting",
					required: false,
					defaultValue: "true",
					examples: ["true", "false"]
				),
				ParameterInfo(
					name: "animated",
					description: "Whether to animate the scroll and selection",
					required: false,
					defaultValue: "true",
					examples: ["true", "false"]
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

				let section = Int(request.queryParams["section"] ?? "0") ?? 0
				// Accept either "row" or "item"
				let rowOrItem = request.queryParams["row"] ?? request.queryParams["item"]
				guard let rowOrItemString = rowOrItem, let row = Int(rowOrItemString) else {
					return .error("Missing required parameter: row (or item)", status: .badRequest)
				}

				let shouldScroll = request.queryParams["scroll"] != "false"
				let animated = request.queryParams["animated"] != "false"

				var result: [String: Any] = [
					"address": addressString,
					"class": String(describing: type(of: view)),
					"indexPath": [
						"section": section,
						"row": row,
					],
				]

				// Handle UITableView
				if let tableView = view as? UITableView {
					let indexPath = IndexPath(row: row, section: section)

					// Validate index path
					guard section < tableView.numberOfSections else {
						return .error("Section \(section) out of range (0-\(tableView.numberOfSections - 1))", status: .badRequest)
					}

					let rowCount = tableView.numberOfRows(inSection: section)
					guard row < rowCount else {
						return .error("Row \(row) out of range (0-\(rowCount - 1)) in section \(section)", status: .badRequest)
					}

					// Scroll to cell if requested
					if shouldScroll {
						tableView.scrollToRow(at: indexPath, at: .middle, animated: animated)
					}

					// Select the row
					tableView.selectRow(at: indexPath, animated: animated, scrollPosition: shouldScroll ? .none : .middle)

					// Trigger the delegate method via performSelector to work around main actor isolation
					if let delegate = tableView.delegate {
						let selector = #selector(UITableViewDelegate.tableView(_:didSelectRowAt:))
						if delegate.responds(to: selector) {
							_ = delegate.perform(selector, with: tableView, with: indexPath)
						}
					}

					result["success"] = true
					result["tableView"] = [
						"numberOfSections": tableView.numberOfSections,
						"numberOfRowsInSection": rowCount,
					]

					// Try to get cell info
					if let cell = tableView.cellForRow(at: indexPath) {
						result["cell"] = [
							"class": String(describing: type(of: cell)),
							"address": String(format: "0x%lx", unsafeBitCast(cell, to: Int.self)),
							"textLabel": cell.textLabel?.text as Any,
							"detailTextLabel": cell.detailTextLabel?.text as Any,
							"accessibilityLabel": cell.accessibilityLabel as Any,
						]
					}
				}
				// Handle UICollectionView
				else if let collectionView = view as? UICollectionView {
					let indexPath = IndexPath(item: row, section: section)

					// Validate index path
					guard section < collectionView.numberOfSections else {
						return .error("Section \(section) out of range (0-\(collectionView.numberOfSections - 1))", status: .badRequest)
					}

					let itemCount = collectionView.numberOfItems(inSection: section)
					guard row < itemCount else {
						return .error("Item \(row) out of range (0-\(itemCount - 1)) in section \(section)", status: .badRequest)
					}

					// Scroll to cell if requested
					if shouldScroll {
						collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: animated)
					}

					// Select the item
					collectionView.selectItem(at: indexPath, animated: animated, scrollPosition: shouldScroll ? [] : .centeredVertically)

					// Trigger the delegate method via performSelector to work around main actor isolation
					if let delegate = collectionView.delegate {
						let selector = #selector(UICollectionViewDelegate.collectionView(_:didSelectItemAt:))
						if delegate.responds(to: selector) {
							_ = delegate.perform(selector, with: collectionView, with: indexPath)
						}
					}

					result["success"] = true
					result["collectionView"] = [
						"numberOfSections": collectionView.numberOfSections,
						"numberOfItemsInSection": itemCount,
					]

					// Try to get cell info
					if let cell = collectionView.cellForItem(at: indexPath) {
						result["cell"] = [
							"class": String(describing: type(of: cell)),
							"address": String(format: "0x%lx", unsafeBitCast(cell, to: Int.self)),
							"accessibilityLabel": cell.accessibilityLabel as Any,
						]
					}
				}
				else {
					return .error("View at address is not a UITableView or UICollectionView (found: \(type(of: view)))", status: .badRequest)
				}

				return .json(result)
			#else
				return .error("UI interaction is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	// MARK: - Menu

	private static func registerMenu(with handler: RequestHandler) {
		handler.register(
			"/menu",
			description: "Trigger a UIMenu on a UIButton or other control. Can show the menu, list menu items, or select a specific menu item by index or title.",
			parameters: [
				ParameterInfo(
					name: "address",
					description: "Memory address of the view with a menu (typically UIButton)",
					required: true,
					examples: ["0x12345678"]
				),
				ParameterInfo(
					name: "action",
					description: "Action to perform: 'show' presents the menu, 'list' returns menu structure, 'select' triggers a menu item",
					required: false,
					defaultValue: "list",
					examples: ["show", "list", "select"]
				),
				ParameterInfo(
					name: "index",
					description: "Index of menu item to select (0-based, for action=select). Supports nested paths like '0.2' for submenu item.",
					required: false,
					examples: ["0", "2", "1.0"]
				),
				ParameterInfo(
					name: "title",
					description: "Title of menu item to select (for action=select). Searches recursively through submenus.",
					required: false,
					examples: ["Copy", "Delete", "Share"]
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

				let action = request.queryParams["action"] ?? "list"

				var result: [String: Any] = [
					"address": addressString,
					"class": String(describing: type(of: view)),
				]

				// Get the menu from the view
				var menu: UIMenu?

				if let button = view as? UIButton {
					menu = button.menu
					result["showsMenuAsPrimaryAction"] = button.showsMenuAsPrimaryAction
				}
				else if let barButtonItem = (view as? UIView)?.value(forKey: "_barButtonItem") as? UIBarButtonItem {
					menu = barButtonItem.menu
				}

				// Also check for context menu interaction
				var contextMenuInteraction: UIContextMenuInteraction?
				if let interactions = view.interactions as? [UIInteraction] {
					contextMenuInteraction = interactions.compactMap({ $0 as? UIContextMenuInteraction }).first
				}

				result["hasContextMenuInteraction"] = contextMenuInteraction != nil

				guard let foundMenu = menu else {
					if contextMenuInteraction != nil {
						result["note"] = "View has UIContextMenuInteraction but no static UIMenu. Use action=show to trigger context menu."
						result["hasMenu"] = false

						if action == "show" {
							// Attempt to show context menu by simulating long press
							if let contextInteraction = contextMenuInteraction {
								// Try to present the menu programmatically
								// This uses private API but is useful for testing
								let selector = NSSelectorFromString("_presentMenuAtLocation:")
								if contextInteraction.responds(to: selector) {
									let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
									contextInteraction.perform(selector, with: NSValue(cgPoint: center))
									result["action"] = "show"
									result["success"] = true
									result["method"] = "contextMenuInteraction._presentMenuAtLocation"
									return .json(result)
								}
							}

							// Fall back to synthesizing a long press
							if let longPressGesture = view.gestureRecognizers?.first(where: { $0 is UILongPressGestureRecognizer }) as? UILongPressGestureRecognizer {
								if let targets = longPressGesture.value(forKey: "_targets") as? [AnyObject] {
									for target in targets {
										if let actionSel = target.value(forKey: "_action") as? Selector,
										   let targetObj = target.value(forKey: "_target") as? NSObject
										{
											targetObj.perform(actionSel, with: longPressGesture)
											result["action"] = "show"
											result["success"] = true
											result["method"] = "longPressGestureRecognizer"
											return .json(result)
										}
									}
								}
							}

							result["success"] = false
							result["error"] = "Could not programmatically trigger context menu"
							return .json(result)
						}

						return .json(result)
					}

					return .error("No UIMenu found on this view. Button.menu is nil and no UIContextMenuInteraction present.", status: .badRequest)
				}

				result["hasMenu"] = true
				result["menuTitle"] = foundMenu.title
				result["menuIdentifier"] = foundMenu.identifier.rawValue

				switch action {
					case "list":
						result["menu"] = self.serializeMenu(foundMenu)
						result["success"] = true

					case "show":
						// For UIButton with menu, we can trigger the menu presentation
						if let button = view as? UIButton {
							// If showsMenuAsPrimaryAction is true, sendActions will show menu
							if button.showsMenuAsPrimaryAction {
								button.sendActions(for: .menuActionTriggered)
								result["success"] = true
								result["method"] = "sendActions(for: .menuActionTriggered)"
							}
							else {
								// Need to simulate a long press or use context menu presentation
								// Try the context menu interaction if available
								if let contextInteraction = contextMenuInteraction {
									let selector = NSSelectorFromString("_presentMenuAtLocation:")
									if contextInteraction.responds(to: selector) {
										let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
										contextInteraction.perform(selector, with: NSValue(cgPoint: center))
										result["success"] = true
										result["method"] = "contextMenuInteraction._presentMenuAtLocation"
									}
									else {
										result["success"] = false
										result["error"] = "Button has menu but showsMenuAsPrimaryAction is false. Long-press required."
										result["suggestion"] = "Set showsMenuAsPrimaryAction=true or use a long press gesture"
									}
								}
								else {
									result["success"] = false
									result["error"] = "Button has menu but showsMenuAsPrimaryAction is false. Long-press required."
								}
							}
						}
						else {
							result["success"] = false
							result["error"] = "Cannot programmatically show menu on non-button views"
						}

					case "select":
						// Find and execute a menu item
						var targetAction: UIAction?
						var actionPath: String = ""

						if let indexPath = request.queryParams["index"] {
							// Parse index path (e.g., "0", "1.2", "0.1.3")
							let indices = indexPath.split(separator: ".").compactMap({ Int($0) })
							if indices.isEmpty {
								return .error("Invalid index format: \(indexPath)", status: .badRequest)
							}

							targetAction = self.findMenuAction(in: foundMenu, at: indices)
							actionPath = indexPath
						}
						else if let title = request.queryParams["title"] {
							targetAction = self.findMenuAction(in: foundMenu, titled: title)
							actionPath = title
						}
						else {
							return .error("action=select requires either 'index' or 'title' parameter", status: .badRequest)
						}

						if let action = targetAction {
							result["selectedAction"] = [
								"title": action.title,
								"identifier": action.identifier.rawValue,
								"state": self.menuElementStateString(action.state),
								"attributes": self.menuElementAttributesString(action.attributes),
							]

							// Execute the action's handler
							// UIAction stores its handler internally - we need to trigger it
							// The handler is called when the action is performed
							if #available(iOS 16.0, *) {
								action.performWithSender(nil, target: nil)
								result["success"] = true
								result["method"] = "performWithSender"
							}
							else {
								// Fallback for iOS 15: try to invoke via private API
								let selector = NSSelectorFromString("_performActionWithSender:")
								if action.responds(to: selector) {
									action.perform(selector, with: nil)
									result["success"] = true
									result["method"] = "_performActionWithSender (fallback)"
								}
								else {
									result["success"] = false
									result["error"] = "Cannot execute menu action on iOS < 16. Use action=show to present the menu instead."
								}
							}
							result["actionPath"] = actionPath
						}
						else {
							result["success"] = false
							result["error"] = "Menu item not found: \(actionPath)"
							result["menu"] = self.serializeMenu(foundMenu)
						}

					default:
						return .error("Unknown action: \(action). Use 'list', 'show', or 'select'.", status: .badRequest)
				}

				return .json(result)
			#else
				return .error("UI interaction is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	#if canImport(UIKit)
		// MARK: - Menu Helpers

		private static func serializeMenu(_ menu: UIMenu) -> [String: Any] {
			var result: [String: Any] = [
				"title": menu.title,
				"identifier": menu.identifier.rawValue,
				"options": self.menuOptionsString(menu.options),
			]

			var children: [[String: Any]] = []
			for (index, element) in menu.children.enumerated() {
				var childInfo: [String: Any] = ["index": index]

				if let action = element as? UIAction {
					childInfo["type"] = "action"
					childInfo["title"] = action.title
					childInfo["identifier"] = action.identifier.rawValue
					childInfo["state"] = self.menuElementStateString(action.state)
					childInfo["attributes"] = self.menuElementAttributesString(action.attributes)
					if let image = action.image {
						childInfo["hasImage"] = true
						childInfo["imageSystemName"] = image.accessibilityIdentifier ?? "(custom)"
					}
				}
				else if let submenu = element as? UIMenu {
					childInfo["type"] = "submenu"
					childInfo["title"] = submenu.title
					childInfo["identifier"] = submenu.identifier.rawValue
					childInfo["children"] = self.serializeMenu(submenu)["children"] ?? []
					childInfo["childCount"] = submenu.children.count
				}
				else {
					childInfo["type"] = "unknown"
					childInfo["class"] = String(describing: type(of: element))
				}

				children.append(childInfo)
			}

			result["children"] = children
			result["childCount"] = children.count

			return result
		}

		private static func findMenuAction(in menu: UIMenu, at indices: [Int]) -> UIAction? {
			guard !indices.isEmpty else { return nil }

			let index = indices[0]
			guard index >= 0, index < menu.children.count else { return nil }

			let element = menu.children[index]

			if indices.count == 1 {
				return element as? UIAction
			}
			else if let submenu = element as? UIMenu {
				return self.findMenuAction(in: submenu, at: Array(indices.dropFirst()))
			}

			return nil
		}

		private static func findMenuAction(in menu: UIMenu, titled title: String) -> UIAction? {
			for element in menu.children {
				if let action = element as? UIAction, action.title == title {
					return action
				}
				else if let submenu = element as? UIMenu {
					if let found = self.findMenuAction(in: submenu, titled: title) {
						return found
					}
				}
			}
			return nil
		}

		private static func menuOptionsString(_ options: UIMenu.Options) -> [String] {
			var result: [String] = []
			if options.contains(.displayInline) { result.append("displayInline") }
			if options.contains(.destructive) { result.append("destructive") }
			if options.contains(.singleSelection) { result.append("singleSelection") }
			return result
		}

		private static func menuElementStateString(_ state: UIMenuElement.State) -> String {
			switch state {
				case .off: return "off"
				case .on: return "on"
				case .mixed: return "mixed"
				@unknown default: return "unknown"
			}
		}

		private static func menuElementAttributesString(_ attributes: UIMenuElement.Attributes) -> [String] {
			var result: [String] = []
			if attributes.contains(.disabled) { result.append("disabled") }
			if attributes.contains(.destructive) { result.append("destructive") }
			if attributes.contains(.hidden) { result.append("hidden") }
			if #available(iOS 16.0, *) {
				if attributes.contains(.keepsMenuPresented) { result.append("keepsMenuPresented") }
			}
			return result
		}
	#endif

	// MARK: - Helper Methods

	#if canImport(UIKit)
		private static func findFirstResponder() -> UIResponder? {
			let scenes = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })

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
