import Foundation

// MARK: - PermissionsEndpoints

/// System permissions inspection endpoints
/// Uses runtime framework detection to avoid forcing host apps to link unused frameworks
public enum PermissionsEndpoints {
	// MARK: - Permission Cache

	/// Cached permission result
	private struct CachedPermission {
		let status: PermissionStatus
		let timestamp: Date
		let isChecking: Bool

		init(status: PermissionStatus, isChecking: Bool = false) {
			self.status = status
			self.timestamp = Date()
			self.isChecking = isChecking
		}

		static func checking() -> CachedPermission {
			return CachedPermission(status: .checking, isChecking: true)
		}
	}

	/// Thread-safe cache for permission states
	private static var permissionCache: [PermissionType: CachedPermission] = [:]
	private static let cacheLock = NSLock()

	private static func getCachedPermission(for type: PermissionType) -> CachedPermission? {
		self.cacheLock.lock()
		defer { self.cacheLock.unlock() }
		return self.permissionCache[type]
	}

	private static func setCachedPermission(_ permission: CachedPermission, for type: PermissionType) {
		self.cacheLock.lock()
		defer { self.cacheLock.unlock() }
		self.permissionCache[type] = permission
	}

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
		self.registerRefresh(with: router)

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

		/// Whether this permission requires async checking
		var isAsync: Bool {
			switch self {
				case .notifications, .siri:
					return true

				default:
					return false
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
		case checking
		case notChecked = "not_checked"
		case entitlementMissing = "entitlement_missing"

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

				case .checking: return "Async check in progress"

				case .notChecked: return "Not yet checked - call /permissions/refresh first"

				case .entitlementMissing: return "Required entitlement not present in app"
			}
		}
	}

	// MARK: - Framework Detection

	/// Check if a framework is linked by looking for a known class
	private static func isFrameworkLinked(_ className: String) -> Bool {
		return NSClassFromString(className) != nil
	}

	// MARK: - Permission Checking

	/// Get the permission status for a specific type (sync check or cached result)
	private static func getPermissionStatus(for type: PermissionType) -> [String: Any] {
		// First check if framework is linked
		guard self.isFrameworkLinked(type.detectionClassName) else {
			return self.buildResponse(for: type, status: .notLinked, cached: nil)
		}

		// For async permissions, return cached result
		if type.isAsync {
			if let cached = self.getCachedPermission(for: type) {
				return self.buildResponse(for: type, status: cached.status, cached: cached)
			}
			else {
				return self.buildResponse(for: type, status: .notChecked, cached: nil)
			}
		}

		// Framework is linked, check actual permission synchronously
		let status: PermissionStatus = self.checkPermissionSync(for: type)
		return self.buildResponse(for: type, status: status, cached: nil)
	}

	private static func buildResponse(for type: PermissionType, status: PermissionStatus, cached: CachedPermission?) -> [String: Any] {
		var response: [String: Any] = [
			"type": type.rawValue,
			"displayName": type.displayName,
			"status": status.rawValue,
			"description": status.description,
			"framework": type.framework,
			"isAsync": type.isAsync,
		]

		if let cached = cached {
			response["lastChecked"] = ISO8601DateFormatter().string(from: cached.timestamp)
		}

		return response
	}

	/// Check the actual permission status using runtime method calls (sync only)
	private static func checkPermissionSync(for type: PermissionType) -> PermissionStatus {
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
				// Async - should use cache
				return .notChecked

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
				// Async due to entitlement check complexity
				return .notChecked
		}
	}

	// MARK: - Async Permission Refresh

	/// Trigger async permission checks
	private static func refreshAsyncPermissions() {
		// Notifications
		self.refreshNotificationsPermission()

		// Siri
		self.refreshSiriPermission()
	}

	/// Refresh notification permission status
	private static func refreshNotificationsPermission() {
		guard let unClass = NSClassFromString("UNUserNotificationCenter") else {
			self.setCachedPermission(CachedPermission(status: .notLinked), for: .notifications)
			return
		}

		// Mark as checking
		self.setCachedPermission(CachedPermission.checking(), for: .notifications)

		// Get current notification center
		let currentSelector = NSSelectorFromString("currentNotificationCenter")
		guard unClass.responds(to: currentSelector),
		      let centerUnmanaged = (unClass as AnyObject).perform(currentSelector),
		      let center = centerUnmanaged.takeUnretainedValue() as? NSObject
		else {
			self.setCachedPermission(CachedPermission(status: .unknown), for: .notifications)
			return
		}

		// Create completion handler block
		let completion: @convention(block) (NSObject) -> Void = { settings in
			// Get authorizationStatus from settings
			let statusSelector = NSSelectorFromString("authorizationStatus")
			guard settings.responds(to: statusSelector) else {
				self.setCachedPermission(CachedPermission(status: .unknown), for: .notifications)
				return
			}

			let statusResult = settings.perform(statusSelector)
			let statusValue: Int = .init(bitPattern: statusResult?.toOpaque())

			// UNAuthorizationStatus: 0 = notDetermined, 1 = denied, 2 = authorized, 3 = provisional
			let status: PermissionStatus
			switch statusValue {
				case 0: status = .notDetermined

				case 1: status = .denied

				case 2: status = .authorized

				case 3: status = .provisional

				default: status = .unknown
			}

			self.setCachedPermission(CachedPermission(status: status), for: .notifications)
		}

		// Call getNotificationSettingsWithCompletionHandler:
		let settingsSelector = NSSelectorFromString("getNotificationSettingsWithCompletionHandler:")
		if center.responds(to: settingsSelector) {
			center.perform(settingsSelector, with: completion)
		}
		else {
			self.setCachedPermission(CachedPermission(status: .unknown), for: .notifications)
		}
	}

	/// Refresh Siri permission status (handles entitlement exception)
	private static func refreshSiriPermission() {
		guard let inClass = NSClassFromString("INPreferences") as? NSObject.Type else {
			self.setCachedPermission(CachedPermission(status: .notLinked), for: .siri)
			return
		}

		// Mark as checking
		self.setCachedPermission(CachedPermission.checking(), for: .siri)

		// Check if app has Siri entitlement by looking at Info.plist
		// Apps using Siri must have NSSiriUsageDescription
		let hasSiriUsageDescription: Bool = Bundle.main.object(forInfoDictionaryKey: "NSSiriUsageDescription") != nil

		if !hasSiriUsageDescription {
			// No usage description = entitlement likely missing
			self.setCachedPermission(CachedPermission(status: .entitlementMissing), for: .siri)
			return
		}

		// Try to get the authorization status
		// This might throw an exception if entitlement is missing despite usage description
		let selector = NSSelectorFromString("siriAuthorizationStatus")
		guard inClass.responds(to: selector) else {
			self.setCachedPermission(CachedPermission(status: .unknown), for: .siri)
			return
		}

		// Use DispatchQueue to catch any potential crashes/exceptions
		// by running in a separate context
		DispatchQueue.global(qos: .userInitiated).async {
			// We'll attempt the call and handle failure via the cache
			// Note: This doesn't catch ObjC exceptions, but the NSSiriUsageDescription check
			// should prevent most cases

			let result = inClass.perform(selector)
			let statusValue: Int = .init(bitPattern: result?.toOpaque())

			// INSiriAuthorizationStatus: 0 = notDetermined, 1 = restricted, 2 = denied, 3 = authorized
			let status: PermissionStatus
			switch statusValue {
				case 0: status = .notDetermined

				case 1: status = .restricted

				case 2: status = .denied

				case 3: status = .authorized

				default: status = .unknown
			}

			DispatchQueue.main.async {
				self.setCachedPermission(CachedPermission(status: status), for: .siri)
			}
		}
	}

	// MARK: - Individual Permission Checks (Sync)

	private static func checkPhotosPermission() -> PermissionStatus {
		guard let phClass = NSClassFromString("PHPhotoLibrary") as? NSObject.Type else {
			return .notLinked
		}

		let selector = NSSelectorFromString("authorizationStatus")
		guard phClass.responds(to: selector) else {
			return .unknown
		}

		let result = phClass.perform(selector)
		let statusValue: Int = .init(bitPattern: result?.toOpaque())

		// PHAuthorizationStatus: 0 = notDetermined, 1 = restricted, 2 = denied, 3 = authorized, 4 = limited
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

			let selector = NSSelectorFromString("authorizationStatusForMediaType:")
			guard avClass.responds(to: selector) else {
				return .unknown
			}

			let mediaType: NSString = "vide"
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

	private static func checkMicrophonePermission() -> PermissionStatus {
		#if os(iOS) || os(tvOS)
			guard let avClass = NSClassFromString("AVCaptureDevice") as? NSObject.Type else {
				return .notLinked
			}

			let selector = NSSelectorFromString("authorizationStatusForMediaType:")
			guard avClass.responds(to: selector) else {
				return .unknown
			}

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

		let entityType: Int = 0
		let result = cnClass.perform(selector, with: entityType as AnyObject)
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

		let entityType: Int = 0
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

	private static func checkRemindersPermission() -> PermissionStatus {
		guard let ekClass = NSClassFromString("EKEventStore") as? NSObject.Type else {
			return .notLinked
		}

		let selector = NSSelectorFromString("authorizationStatusForEntityType:")
		guard ekClass.responds(to: selector) else {
			return .unknown
		}

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

		let selector = NSSelectorFromString("authorizationStatus")
		guard clClass.responds(to: selector) else {
			return .unknown
		}

		let result = clClass.perform(selector)
		let statusValue: Int = .init(bitPattern: result?.toOpaque())

		switch statusValue {
			case 0: return .notDetermined

			case 1: return .restricted

			case 2: return .denied

			case 3, 4: return .authorized

			default: return .unknown
		}
	}

	private static func checkHealthPermission() -> PermissionStatus {
		guard let hkClass = NSClassFromString("HKHealthStore") as? NSObject.Type else {
			return .notLinked
		}

		// Check if HealthKit is available on this device
		let availableSelector = NSSelectorFromString("isHealthDataAvailable")
		guard hkClass.responds(to: availableSelector) else {
			return .unknown
		}

		let result = hkClass.perform(availableSelector)
		let isAvailable: Bool = result != nil

		if !isAvailable {
			return .restricted
		}

		// HealthKit doesn't have a simple authorization check - it requires specific data types
		// We return notDetermined as a placeholder indicating the user can request
		// Actual permission checking requires specifying which data types to check
		return .notDetermined
	}

	private static func checkMotionPermission() -> PermissionStatus {
		guard let cmClass = NSClassFromString("CMMotionActivityManager") as? NSObject.Type else {
			return .notLinked
		}

		let selector = NSSelectorFromString("authorizationStatus")
		guard cmClass.responds(to: selector) else {
			return .unknown
		}

		let result = cmClass.perform(selector)
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

		let selector = NSSelectorFromString("authorizationStatus")
		guard sfClass.responds(to: selector) else {
			return .unknown
		}

		let result = sfClass.perform(selector)
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
		guard NSClassFromString("CBCentralManager") != nil else {
			return .notLinked
		}

		guard let cbManagerClass = NSClassFromString("CBManager") as? NSObject.Type else {
			return .unknown
		}

		let selector = NSSelectorFromString("authorization")
		guard cbManagerClass.responds(to: selector) else {
			return .unknown
		}

		let result = cbManagerClass.perform(selector)
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
		guard NSClassFromString("HMHomeManager") != nil else {
			return .notLinked
		}

		// HomeKit doesn't have a simple authorization status API
		// It requires creating an HMHomeManager and waiting for delegate callback
		// For now, check if the app has the HomeKit usage description
		let hasUsageDescription: Bool = Bundle.main.object(forInfoDictionaryKey: "NSHomeKitUsageDescription") != nil

		if !hasUsageDescription {
			return .entitlementMissing
		}

		// We can't easily check the actual status without creating manager
		return .notDetermined
	}

	private static func checkMediaLibraryPermission() -> PermissionStatus {
		guard let mpClass = NSClassFromString("MPMediaLibrary") as? NSObject.Type else {
			return .notLinked
		}

		let selector = NSSelectorFromString("authorizationStatus")
		guard mpClass.responds(to: selector) else {
			return .unknown
		}

		let result = mpClass.perform(selector)
		let statusValue: Int = .init(bitPattern: result?.toOpaque())

		switch statusValue {
			case 0: return .notDetermined

			case 1: return .denied

			case 2: return .restricted

			case 3: return .authorized

			default: return .unknown
		}
	}

	// MARK: - Endpoints

	private static func registerAll(with handler: RequestHandler) {
		handler.register(
			"/all",
			description: "Get all permission states. Sync permissions are checked live; async permissions (notifications, siri) return cached last-known values. Call /permissions/refresh first to update cached values.",
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

			// Count async permissions that need refresh
			let asyncNeedingRefresh: Int = permissions.filter {
				($0["isAsync"] as? Bool == true) && ($0["status"] as? String == "not_checked")
			}
			.count

			return .json([
				"count": permissions.count,
				"summary": statusCounts,
				"permissions": permissions,
				"timestamp": ISO8601DateFormatter().string(from: Date()),
				"asyncNeedingRefresh": asyncNeedingRefresh,
			])
		}
	}

	private static func registerList(with handler: RequestHandler) {
		handler.register(
			"/list",
			description: "List all supported permission types. Returns the type identifiers and display names without checking status.",
			runsOnMainThread: false
		) { _ in
			var types: [[String: Any]] = []

			for type in PermissionType.allCases {
				types.append([
					"type": type.rawValue,
					"displayName": type.displayName,
					"framework": type.framework,
					"detectionClass": type.detectionClassName,
					"isAsync": type.isAsync,
				])
			}

			return .json([
				"count": types.count,
				"types": types,
				"note": "Use /permissions/refresh to trigger async permission checks, then /permissions/all to read results",
			])
		}
	}

	private static func registerGet(with handler: RequestHandler) {
		handler.register(
			"/get",
			description: "Get the permission status for a specific type. For async permissions (notifications, siri), returns cached last-known value. Call /permissions/refresh first to update.",
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

			var status: [String: Any] = self.getPermissionStatus(for: type)
			status["timestamp"] = ISO8601DateFormatter().string(from: Date())

			return .json(status)
		}
	}

	private static func registerRefresh(with handler: RequestHandler) {
		handler.register(
			"/refresh",
			description: "Trigger fresh async permission checks and update cached values. Async permissions (notifications, siri) are checked in the background. Call /permissions/all or /permissions/get after a short delay to read the updated cached results.",
			runsOnMainThread: true
		) { _ in
			// Trigger all async checks
			self.refreshAsyncPermissions()

			// Build response showing what was triggered
			var refreshed: [[String: String]] = []
			for type in PermissionType.allCases where type.isAsync {
				refreshed.append([
					"type": type.rawValue,
					"displayName": type.displayName,
					"status": "checking",
				])
			}

			return .json([
				"message": "Async permission checks triggered",
				"refreshing": refreshed,
				"note": "Call /permissions/all after a short delay to see updated results",
				"timestamp": ISO8601DateFormatter().string(from: Date()),
			])
		}
	}
}
