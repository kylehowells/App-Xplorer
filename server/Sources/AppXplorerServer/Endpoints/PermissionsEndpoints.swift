import Foundation

// MARK: - PermissionsEndpoints

/// System permissions inspection endpoints
/// Uses runtime framework detection to avoid forcing host apps to link unused frameworks
public enum PermissionsEndpoints {
	/// Create a router for permissions endpoints
	public static func createRouter() -> RequestHandler {
		let router: RequestHandler = .init(description: "Inspect system permission states")

		// Register index for this sub-router
		router.register("/", description: "List all permissions endpoints", runsOnMainThread: true) { _ in
			return .json(router.routerInfo(deep: true))
		}

		self.registerAll(with: router)
		self.registerList(with: router)
		self.registerGet(with: router)

		return router
	}

	// MARK: - Permission Types

	/// Supported permission types
	private enum PermissionType: String, CaseIterable {
		case photos
		case camera
		case microphone
		case contacts
		case calendar
		case reminders
		case location
		case notifications
		case health
		case motion
		case speech
		case bluetooth
		case homekit
		case medialibrary
		case siri

		var displayName: String {
			switch self {
				case .photos: return "Photos"

				case .camera: return "Camera"

				case .microphone: return "Microphone"

				case .contacts: return "Contacts"

				case .calendar: return "Calendar"

				case .reminders: return "Reminders"

				case .location: return "Location"

				case .notifications: return "Notifications"

				case .health: return "Health"

				case .motion: return "Motion"

				case .speech: return "Speech"

				case .bluetooth: return "Bluetooth"

				case .homekit: return "HomeKit"

				case .medialibrary: return "Media Library"

				case .siri: return "Siri"
			}
		}

		var framework: String {
			switch self {
				case .photos: return "Photos"

				case .camera: return "AVFoundation"

				case .microphone: return "AVFoundation"

				case .contacts: return "Contacts"

				case .calendar: return "EventKit"

				case .reminders: return "EventKit"

				case .location: return "CoreLocation"

				case .notifications: return "UserNotifications"

				case .health: return "HealthKit"

				case .motion: return "CoreMotion"

				case .speech: return "Speech"

				case .bluetooth: return "CoreBluetooth"

				case .homekit: return "HomeKit"

				case .medialibrary: return "MediaPlayer"

				case .siri: return "Intents"
			}
		}

		/// Class name used to detect if framework is linked
		var detectionClassName: String {
			switch self {
				case .photos: return "PHPhotoLibrary"

				case .camera: return "AVCaptureDevice"

				case .microphone: return "AVCaptureDevice"

				case .contacts: return "CNContactStore"

				case .calendar: return "EKEventStore"

				case .reminders: return "EKEventStore"

				case .location: return "CLLocationManager"

				case .notifications: return "UNUserNotificationCenter"

				case .health: return "HKHealthStore"

				case .motion: return "CMMotionActivityManager"

				case .speech: return "SFSpeechRecognizer"

				case .bluetooth: return "CBCentralManager"

				case .homekit: return "HMHomeManager"

				case .medialibrary: return "MPMediaLibrary"

				case .siri: return "INPreferences"
			}
		}
	}

	/// Permission status values
	private enum PermissionStatus: String {
		case authorized
		case limited
		case denied
		case notDetermined = "not_determined"
		case restricted
		case notLinked = "not_linked"
		case provisional
		case unknown

		var description: String {
			switch self {
				case .authorized: return "Full access granted"

				case .limited: return "Limited access granted"

				case .denied: return "User denied permission"

				case .notDetermined: return "User has not been asked yet"

				case .restricted: return "Access restricted (parental controls or MDM)"

				case .notLinked: return "Framework not linked by app"

				case .provisional: return "Provisional permission granted"

				case .unknown: return "Status could not be determined"
			}
		}
	}

	// MARK: - Framework Detection

	/// Check if a framework is linked by looking for a known class
	private static func isFrameworkLinked(_ className: String) -> Bool {
		return NSClassFromString(className) != nil
	}

	// MARK: - Permission Checking

	/// Get the permission status for a specific type
	private static func getPermissionStatus(for type: PermissionType) -> [String: Any] {
		// First check if framework is linked
		guard self.isFrameworkLinked(type.detectionClassName) else {
			return [
				"type": type.rawValue,
				"displayName": type.displayName,
				"status": PermissionStatus.notLinked.rawValue,
				"description": PermissionStatus.notLinked.description,
				"framework": type.framework,
			]
		}

		// Framework is linked, check actual permission
		let status: PermissionStatus = self.checkPermission(for: type)

		return [
			"type": type.rawValue,
			"displayName": type.displayName,
			"status": status.rawValue,
			"description": status.description,
			"framework": type.framework,
		]
	}

	/// Check the actual permission status using runtime method calls
	private static func checkPermission(for type: PermissionType) -> PermissionStatus {
		switch type {
			case .photos:
				return self.checkPhotosPermission()

			case .camera:
				return self.checkCameraPermission()

			case .microphone:
				return self.checkMicrophonePermission()

			case .contacts:
				return self.checkContactsPermission()

			case .calendar:
				return self.checkCalendarPermission()

			case .reminders:
				return self.checkRemindersPermission()

			case .location:
				return self.checkLocationPermission()

			case .notifications:
				return self.checkNotificationsPermission()

			case .health:
				return self.checkHealthPermission()

			case .motion:
				return self.checkMotionPermission()

			case .speech:
				return self.checkSpeechPermission()

			case .bluetooth:
				return self.checkBluetoothPermission()

			case .homekit:
				return self.checkHomeKitPermission()

			case .medialibrary:
				return self.checkMediaLibraryPermission()

			case .siri:
				return self.checkSiriPermission()
		}
	}

	// MARK: - Individual Permission Checks

	private static func checkPhotosPermission() -> PermissionStatus {
		guard let phClass = NSClassFromString("PHPhotoLibrary") as? NSObject.Type else {
			return .notLinked
		}

		// PHPhotoLibrary.authorizationStatus(for:) requires iOS 14+
		// PHPhotoLibrary.authorizationStatus() is available earlier
		// We use performSelector to call class methods at runtime

		let selector = NSSelectorFromString("authorizationStatus")
		guard phClass.responds(to: selector) else {
			return .unknown
		}

		let result = phClass.perform(selector)

		// Cast the result to an integer representing PHAuthorizationStatus
		// PHAuthorizationStatus: 0 = notDetermined, 1 = restricted, 2 = denied, 3 = authorized, 4 = limited
		let statusValue: Int = .init(bitPattern: result?.toOpaque())

		switch statusValue {
			case 0: return .notDetermined

			case 1: return .restricted

			case 2: return .denied

			case 3: return .authorized

			case 4: return .limited

			default: return .unknown
		}
	}

	private static func checkCameraPermission() -> PermissionStatus {
		#if os(iOS) || os(tvOS)
			guard let avClass = NSClassFromString("AVCaptureDevice") as? NSObject.Type else {
				return .notLinked
			}

			// AVCaptureDevice.authorizationStatus(for:) - we need to pass mediaType
			let selector = NSSelectorFromString("authorizationStatusForMediaType:")
			guard avClass.responds(to: selector) else {
				return .unknown
			}

			// AVMediaTypeVideo = "vide"
			let mediaType: NSString = "vide"
			let result = avClass.perform(selector, with: mediaType)

			// AVAuthorizationStatus: 0 = notDetermined, 1 = restricted, 2 = denied, 3 = authorized
			let statusValue: Int = .init(bitPattern: result?.toOpaque())

			switch statusValue {
				case 0: return .notDetermined

				case 1: return .restricted

				case 2: return .denied

				case 3: return .authorized

				default: return .unknown
			}
		#else
			return .unknown
		#endif
	}

	private static func checkMicrophonePermission() -> PermissionStatus {
		#if os(iOS) || os(tvOS)
			guard let avClass = NSClassFromString("AVCaptureDevice") as? NSObject.Type else {
				return .notLinked
			}

			let selector = NSSelectorFromString("authorizationStatusForMediaType:")
			guard avClass.responds(to: selector) else {
				return .unknown
			}

			// AVMediaTypeAudio = "soun"
			let mediaType: NSString = "soun"
			let result = avClass.perform(selector, with: mediaType)

			let statusValue: Int = .init(bitPattern: result?.toOpaque())

			switch statusValue {
				case 0: return .notDetermined

				case 1: return .restricted

				case 2: return .denied

				case 3: return .authorized

				default: return .unknown
			}
		#else
			return .unknown
		#endif
	}

	private static func checkContactsPermission() -> PermissionStatus {
		guard let cnClass = NSClassFromString("CNContactStore") as? NSObject.Type else {
			return .notLinked
		}

		let selector = NSSelectorFromString("authorizationStatusForEntityType:")
		guard cnClass.responds(to: selector) else {
			return .unknown
		}

		// CNEntityType.contacts = 0
		let entityType: Int = 0
		let result = cnClass.perform(selector, with: entityType as AnyObject)

		// CNAuthorizationStatus: 0 = notDetermined, 1 = restricted, 2 = denied, 3 = authorized
		let statusValue: Int = .init(bitPattern: result?.toOpaque())

		switch statusValue {
			case 0: return .notDetermined

			case 1: return .restricted

			case 2: return .denied

			case 3: return .authorized

			default: return .unknown
		}
	}

	private static func checkCalendarPermission() -> PermissionStatus {
		guard let ekClass = NSClassFromString("EKEventStore") as? NSObject.Type else {
			return .notLinked
		}

		let selector = NSSelectorFromString("authorizationStatusForEntityType:")
		guard ekClass.responds(to: selector) else {
			return .unknown
		}

		// EKEntityType.event = 0
		let entityType: Int = 0
		let result = ekClass.perform(selector, with: entityType as AnyObject)

		// EKAuthorizationStatus: 0 = notDetermined, 1 = restricted, 2 = denied, 3 = authorized
		// iOS 17+: 4 = writeOnly, 5 = fullAccess (but older statuses still work)
		let statusValue: Int = .init(bitPattern: result?.toOpaque())

		switch statusValue {
			case 0: return .notDetermined

			case 1: return .restricted

			case 2: return .denied

			case 3, 4, 5: return .authorized

			default: return .unknown
		}
	}

	private static func checkRemindersPermission() -> PermissionStatus {
		guard let ekClass = NSClassFromString("EKEventStore") as? NSObject.Type else {
			return .notLinked
		}

		let selector = NSSelectorFromString("authorizationStatusForEntityType:")
		guard ekClass.responds(to: selector) else {
			return .unknown
		}

		// EKEntityType.reminder = 1
		let entityType: Int = 1
		let result = ekClass.perform(selector, with: entityType as AnyObject)

		let statusValue: Int = .init(bitPattern: result?.toOpaque())

		switch statusValue {
			case 0: return .notDetermined

			case 1: return .restricted

			case 2: return .denied

			case 3, 4, 5: return .authorized

			default: return .unknown
		}
	}

	private static func checkLocationPermission() -> PermissionStatus {
		guard let clClass = NSClassFromString("CLLocationManager") as? NSObject.Type else {
			return .notLinked
		}

		// CLLocationManager.authorizationStatus() is deprecated in iOS 14+
		// but still works as a class method
		let selector = NSSelectorFromString("authorizationStatus")
		guard clClass.responds(to: selector) else {
			return .unknown
		}

		let result = clClass.perform(selector)

		// CLAuthorizationStatus: 0 = notDetermined, 1 = restricted, 2 = denied,
		// 3 = authorizedAlways, 4 = authorizedWhenInUse
		let statusValue: Int = .init(bitPattern: result?.toOpaque())

		switch statusValue {
			case 0: return .notDetermined

			case 1: return .restricted

			case 2: return .denied

			case 3, 4: return .authorized

			default: return .unknown
		}
	}

	private static func checkNotificationsPermission() -> PermissionStatus {
		// UNUserNotificationCenter requires async completion handler
		// For simplicity, we return "unknown" and note that a full check would require async
		guard NSClassFromString("UNUserNotificationCenter") != nil else {
			return .notLinked
		}

		// Notifications require an async call to getNotificationSettings
		// For a synchronous API, we return unknown with a note
		// A future version could cache the last known state
		return .unknown
	}

	private static func checkHealthPermission() -> PermissionStatus {
		guard let hkClass = NSClassFromString("HKHealthStore") as? NSObject.Type else {
			return .notLinked
		}

		// HKHealthStore.isHealthDataAvailable() - check if HealthKit is available
		let availableSelector = NSSelectorFromString("isHealthDataAvailable")
		guard hkClass.responds(to: availableSelector) else {
			return .unknown
		}

		let result = hkClass.perform(availableSelector)
		let isAvailable: Bool = result != nil

		if !isAvailable {
			return .restricted
		}

		// Actual permission checking for HealthKit requires specifying data types
		// and uses async completion handlers. Return unknown for now.
		return .unknown
	}

	private static func checkMotionPermission() -> PermissionStatus {
		guard let cmClass = NSClassFromString("CMMotionActivityManager") as? NSObject.Type else {
			return .notLinked
		}

		// CMMotionActivityManager.authorizationStatus()
		let selector = NSSelectorFromString("authorizationStatus")
		guard cmClass.responds(to: selector) else {
			return .unknown
		}

		let result = cmClass.perform(selector)

		// CMAuthorizationStatus: 0 = notDetermined, 1 = restricted, 2 = denied, 3 = authorized
		let statusValue: Int = .init(bitPattern: result?.toOpaque())

		switch statusValue {
			case 0: return .notDetermined

			case 1: return .restricted

			case 2: return .denied

			case 3: return .authorized

			default: return .unknown
		}
	}

	private static func checkSpeechPermission() -> PermissionStatus {
		guard let sfClass = NSClassFromString("SFSpeechRecognizer") as? NSObject.Type else {
			return .notLinked
		}

		// SFSpeechRecognizer.authorizationStatus()
		let selector = NSSelectorFromString("authorizationStatus")
		guard sfClass.responds(to: selector) else {
			return .unknown
		}

		let result = sfClass.perform(selector)

		// SFSpeechRecognizerAuthorizationStatus: 0 = notDetermined, 1 = denied, 2 = restricted, 3 = authorized
		let statusValue: Int = .init(bitPattern: result?.toOpaque())

		switch statusValue {
			case 0: return .notDetermined

			case 1: return .denied

			case 2: return .restricted

			case 3: return .authorized

			default: return .unknown
		}
	}

	private static func checkBluetoothPermission() -> PermissionStatus {
		// CBCentralManager requires instantiation to check state
		// We can only detect if framework is linked
		guard NSClassFromString("CBCentralManager") != nil else {
			return .notLinked
		}

		// CBManager.authorization is a class property (iOS 13+)
		guard let cbManagerClass = NSClassFromString("CBManager") as? NSObject.Type else {
			return .unknown
		}

		let selector = NSSelectorFromString("authorization")
		guard cbManagerClass.responds(to: selector) else {
			return .unknown
		}

		let result = cbManagerClass.perform(selector)

		// CBManagerAuthorization: 0 = notDetermined, 1 = restricted, 2 = denied, 3 = allowedAlways
		let statusValue: Int = .init(bitPattern: result?.toOpaque())

		switch statusValue {
			case 0: return .notDetermined

			case 1: return .restricted

			case 2: return .denied

			case 3: return .authorized

			default: return .unknown
		}
	}

	private static func checkHomeKitPermission() -> PermissionStatus {
		// HomeKit doesn't have a simple authorization status API
		// It requires creating an HMHomeManager and checking in its delegate
		guard NSClassFromString("HMHomeManager") != nil else {
			return .notLinked
		}

		// Cannot easily check without instantiation and async callback
		return .unknown
	}

	private static func checkMediaLibraryPermission() -> PermissionStatus {
		guard let mpClass = NSClassFromString("MPMediaLibrary") as? NSObject.Type else {
			return .notLinked
		}

		// MPMediaLibrary.authorizationStatus()
		let selector = NSSelectorFromString("authorizationStatus")
		guard mpClass.responds(to: selector) else {
			return .unknown
		}

		let result = mpClass.perform(selector)

		// MPMediaLibraryAuthorizationStatus: 0 = notDetermined, 1 = denied, 2 = restricted, 3 = authorized
		let statusValue: Int = .init(bitPattern: result?.toOpaque())

		switch statusValue {
			case 0: return .notDetermined

			case 1: return .denied

			case 2: return .restricted

			case 3: return .authorized

			default: return .unknown
		}
	}

	private static func checkSiriPermission() -> PermissionStatus {
		guard NSClassFromString("INPreferences") != nil else {
			return .notLinked
		}

		// INPreferences requires the com.apple.developer.siri entitlement
		// Calling siriAuthorizationStatus() without it throws an NSException
		// We cannot safely check without the entitlement, so return restricted
		// (indicating the app cannot use Siri due to missing entitlement)
		return .restricted
	}

	// MARK: - Endpoints

	private static func registerAll(with handler: RequestHandler) {
		handler.register(
			"/all",
			description: "Get all permission states. Returns the status for each supported permission type, including whether the framework is linked.",
			runsOnMainThread: true
		) { _ in
			var permissions: [[String: Any]] = []

			for type in PermissionType.allCases {
				let status: [String: Any] = self.getPermissionStatus(for: type)
				permissions.append(status)
			}

			// Count by status
			var statusCounts: [String: Int] = [:]
			for perm in permissions {
				if let status = perm["status"] as? String {
					statusCounts[status, default: 0] += 1
				}
			}

			return .json([
				"count": permissions.count,
				"summary": statusCounts,
				"permissions": permissions,
				"timestamp": ISO8601DateFormatter().string(from: Date()),
				"note": "Some permissions require async checks (notifications, health, homeKit) and may show 'unknown'",
			])
		}
	}

	private static func registerList(with handler: RequestHandler) {
		handler.register(
			"/list",
			description: "List all supported permission types. Returns the type identifiers and display names without checking status.",
			runsOnMainThread: false
		) { _ in
			var types: [[String: String]] = []

			for type in PermissionType.allCases {
				types.append([
					"type": type.rawValue,
					"displayName": type.displayName,
					"framework": type.framework,
					"detectionClass": type.detectionClassName,
				])
			}

			return .json([
				"count": types.count,
				"types": types,
				"note": "Use /permissions/all or /permissions/get?type=<type> to check status",
			])
		}
	}

	private static func registerGet(with handler: RequestHandler) {
		handler.register(
			"/get",
			description: "Get the permission status for a specific type.",
			parameters: [
				ParameterInfo(
					name: "type",
					description: "Permission type to check",
					required: true,
					examples: PermissionType.allCases.map { $0.rawValue }
				),
			],
			runsOnMainThread: true
		) { request in
			guard let typeString: String = request.queryParams["type"] else {
				return .error("Missing required parameter: type", status: .badRequest)
			}

			guard let type = PermissionType(rawValue: typeString.lowercased()) else {
				let validTypes: String = PermissionType.allCases.map { $0.rawValue }.joined(separator: ", ")
				return .error("Invalid permission type '\(typeString)'. Valid types: \(validTypes)", status: .badRequest)
			}

			let status: [String: Any] = self.getPermissionStatus(for: type)
			var result: [String: Any] = status
			result["timestamp"] = ISO8601DateFormatter().string(from: Date())

			return .json(result)
		}
	}
}
