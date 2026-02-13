import Foundation
#if canImport(UIKit)
	import UIKit
#endif

// MARK: - InfoEndpoints

/// App and device information endpoints
public enum InfoEndpoints {
	/// Register info endpoints with the request handler
	public static func register(with handler: RequestHandler) {
		self.registerInfo(with: handler)
		self.registerScreenshot(with: handler)
	}

	// MARK: - Info

	private static func registerInfo(with handler: RequestHandler) {
		handler.register(
			"/info",
			description: "Get app, device, screen, and locale information. Returns bundle info (name, version, build, bundleId), device info (name, model, systemVersion), screen dimensions with scale factor, and locale/language settings."
		) { _ in
			// Build locale info (available on all platforms)
			let locale: Locale = .current
			let preferredLanguages: [String] = Locale.preferredLanguages
			let localeInfo: [String: Any] = [
				"identifier": locale.identifier,
				"languageCode": locale.languageCode ?? "Unknown",
				"regionCode": locale.regionCode as Any,
				"preferredLanguages": preferredLanguages,
				"usesMetricSystem": locale.usesMetricSystem,
				"currencyCode": locale.currencyCode as Any,
				"currencySymbol": locale.currencySymbol as Any,
				"decimalSeparator": locale.decimalSeparator as Any,
				"groupingSeparator": locale.groupingSeparator as Any,
				"calendar": locale.calendar.identifier.debugDescription,
			]

			#if canImport(UIKit)
				let device: UIDevice = .current
				let bundle: Bundle = .main
				let screen: UIScreen = .main

				let info: [String: Any] = [
					"app": [
						"name": bundle.object(forInfoDictionaryKey: "CFBundleName") ?? "Unknown",
						"version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "Unknown",
						"build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "Unknown",
						"bundleId": bundle.bundleIdentifier ?? "Unknown",
					],
					"device": [
						"name": device.name,
						"model": device.model,
						"systemVersion": device.systemVersion,
						"systemName": device.systemName,
					],
					"screen": [
						"width": screen.bounds.width,
						"height": screen.bounds.height,
						"scale": screen.scale,
					],
					"locale": localeInfo,
					"timestamp": ISO8601DateFormatter().string(from: Date()),
				]
				return .json(info)
			#else
				let bundle: Bundle = .main
				let info: [String: Any] = [
					"app": [
						"name": bundle.object(forInfoDictionaryKey: "CFBundleName") ?? "Unknown",
						"version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "Unknown",
						"build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "Unknown",
						"bundleId": bundle.bundleIdentifier ?? "Unknown",
					],
					"locale": localeInfo,
					"platform": "macOS",
					"timestamp": ISO8601DateFormatter().string(from: Date()),
				]
				return .json(info)
			#endif
		}
	}

	// MARK: - Screenshot

	private static func registerScreenshot(with handler: RequestHandler) {
		handler.register(
			"/screenshot",
			description: "Capture screen or a specific view as an image. Returns PNG or JPEG data with appropriate Content-Type header. By default captures all windows; use 'view' parameter to capture a specific view by its memory address.",
			parameters: [
				ParameterInfo(
					name: "view",
					description: "Memory address of a specific UIView to capture (e.g., '0x12345678'). Get addresses from /hierarchy/views. If omitted, captures the full screen.",
					required: false,
					examples: ["0x12345678"]
				),
				ParameterInfo(
					name: "format",
					description: "Image format for the screenshot",
					required: false,
					defaultValue: "png",
					examples: ["png", "jpeg"]
				),
				ParameterInfo(
					name: "quality",
					description: "JPEG compression quality (0.0-1.0). Only applies when format=jpeg",
					required: false,
					defaultValue: "0.9",
					examples: ["0.5", "0.8", "1.0"]
				),
				ParameterInfo(
					name: "scale",
					description: "Scale factor for the output image. 1.0 = screen scale, 0.5 = half size, 2.0 = double size",
					required: false,
					defaultValue: "1.0",
					examples: ["0.5", "1.0", "2.0"]
				),
				ParameterInfo(
					name: "afterScreenUpdates",
					description: "Wait for pending screen updates before capturing. Slower but more accurate.",
					required: false,
					defaultValue: "false",
					examples: ["true", "false"]
				),
			]
		) { request in
			#if canImport(UIKit)
				// Parse parameters
				let viewAddress: String? = request.queryParams["view"]
				let format: String = request.queryParams["format"]?.lowercased() ?? "png"
				let quality: CGFloat = request.queryParams["quality"].flatMap { Double($0) }.map { CGFloat($0) } ?? 0.9
				let scale: CGFloat = request.queryParams["scale"].flatMap { Double($0) }.map { CGFloat($0) } ?? 1.0
				let afterScreenUpdates: Bool = request.queryParams["afterScreenUpdates"] == "true"

				// Validate parameters
				guard format == "png" || format == "jpeg" || format == "jpg" else {
					return .error("Invalid format. Use 'png' or 'jpeg'", status: .badRequest)
				}

				guard scale > 0 && scale <= 10 else {
					return .error("Scale must be between 0 and 10", status: .badRequest)
				}

				// Capture screenshot
				let data: Data?

				if let addressString = viewAddress {
					// Capture specific view by address
					guard let address = SafeAddressLookup.parseAddress(addressString) else {
						return .error("Invalid view address format. Use hex format like '0x12345678'", status: .badRequest)
					}

					guard let view = SafeAddressLookup.view(at: address) else {
						return .error("No UIView found at address \(addressString). The view may have been deallocated or the address is invalid.", status: .notFound)
					}

					data = self.captureView(view, imageFormat: format, quality: quality, scale: scale, afterScreenUpdates: afterScreenUpdates)
				}
				else {
					// Capture full screen
					data = self.captureScreenshot(imageFormat: format, quality: quality, scale: scale)
				}

				guard let imageData = data else {
					return .error("Failed to capture screenshot", status: .internalError)
				}

				// Return image with appropriate content type
				if format == "jpeg" || format == "jpg" {
					return .jpeg(imageData)
				}
				else {
					return .png(imageData)
				}
			#else
				return .error("Screenshot capture is only available on iOS/tvOS", status: .badRequest)
			#endif
		}
	}

	#if canImport(UIKit)
		/// Capture a screenshot of all windows
		/// Must be called on the main thread
		private static func captureScreenshot(imageFormat: String, quality: CGFloat, scale: CGFloat) -> Data? {
			// Get the key window scene
			guard let windowScene = UIApplication.shared
				.connectedScenes
				.compactMap({ $0 as? UIWindowScene })
				.first(where: { $0.activationState == .foregroundActive })
				?? UIApplication.shared
				.connectedScenes
				.compactMap({ $0 as? UIWindowScene })
				.first
			else {
				return nil
			}

			// Filter out system windows that can cause black screenshots when rendered
			// UITextEffectsWindow is used for keyboard and renders as black/opaque when captured
			let windows: [UIWindow] = windowScene.windows
				.filter { window in
					let className = String(describing: type(of: window))
					// Exclude keyboard/text effects windows that cause black screenshots
					return className != "UITextEffectsWindow"
				}
				.sorted { $0.windowLevel.rawValue < $1.windowLevel.rawValue }

			guard !windows.isEmpty else {
				return nil
			}

			// Get screen bounds
			let screenBounds: CGRect = windowScene.screen.bounds
			let screenScale: CGFloat = windowScene.screen.scale * scale

			// Create image context
			let rendererFormat: UIGraphicsImageRendererFormat = .init()
			rendererFormat.scale = screenScale
			rendererFormat.opaque = true

			let renderer: UIGraphicsImageRenderer = .init(bounds: screenBounds, format: rendererFormat)

			let image: UIImage = renderer.image { context in
				// Fill with white background
				UIColor.white.setFill()
				context.fill(screenBounds)

				// Render each window in order
				for window in windows {
					if !window.isHidden, window.alpha > 0 {
						window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
					}
				}
			}

			// Convert to requested format
			if imageFormat == "jpeg" || imageFormat == "jpg" {
				return image.jpegData(compressionQuality: quality)
			}
			else {
				return image.pngData()
			}
		}

		/// Capture a specific UIView as an image
		/// Must be called on the main thread
		private static func captureView(
			_ view: UIView,
			imageFormat: String,
			quality: CGFloat,
			scale: CGFloat,
			afterScreenUpdates: Bool
		) -> Data? {
			// Get the view's bounds
			let bounds: CGRect = view.bounds

			guard bounds.width > 0, bounds.height > 0 else {
				return nil
			}

			// Determine scale - use the view's window scale, or default to main screen
			let viewScale: CGFloat = (view.window?.screen.scale ?? UIScreen.main.scale) * scale

			// Create image context
			let rendererFormat: UIGraphicsImageRendererFormat = .init()
			rendererFormat.scale = viewScale
			rendererFormat.opaque = view.isOpaque

			let renderer: UIGraphicsImageRenderer = .init(bounds: bounds, format: rendererFormat)

			let image: UIImage = renderer.image { _ in
				// Draw the view hierarchy
				view.drawHierarchy(in: bounds, afterScreenUpdates: afterScreenUpdates)
			}

			// Convert to requested format
			if imageFormat == "jpeg" || imageFormat == "jpg" {
				return image.jpegData(compressionQuality: quality)
			}
			else {
				return image.pngData()
			}
		}
	#endif
}
