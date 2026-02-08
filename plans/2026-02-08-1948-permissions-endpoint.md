# Permissions API Endpoint

**Date:** 2026-02-08
**Goal:** Create a `/permissions` API endpoint that reports permission states for iOS system features (Photos, Contacts, Notifications, etc.) using runtime framework detection.

## Overview

The permissions endpoint must:
1. Detect at runtime which frameworks are linked by the host app
2. Report permission states for linked frameworks
3. Return "not_linked" for frameworks the host app doesn't use
4. Never force the host app to link additional frameworks

## Key Technical Approach

Use `NSClassFromString()` for runtime framework detection:
```swift
if let phClass = NSClassFromString("PHPhotoLibrary") {
    // PhotoKit is linked, check permission
}
else {
    // PhotoKit not linked, return "not_linked"
}
```

## API Design

### Endpoint: `/permissions`

Returns permission states for all supported system features.

#### Response Format
```json
{
  "permissions": {
    "photos": {
      "status": "authorized",
      "description": "Full access to photos"
    },
    "contacts": {
      "status": "not_linked",
      "description": "Contacts framework not linked by app"
    },
    "notifications": {
      "status": "denied",
      "description": "User denied notification permission"
    }
  },
  "timestamp": "2026-02-08T19:48:00Z"
}
```

#### Permission States
- `authorized` - Full access granted
- `limited` - Limited access (iOS 14+ Photos)
- `denied` - User explicitly denied
- `not_determined` - User hasn't been asked yet
- `restricted` - Parental controls or MDM restrictions
- `not_linked` - Framework not linked by host app
- `provisional` - Provisional notifications (iOS 12+)

### Endpoint: `/permissions/list`

Returns just the list of supported permission types (for discovery).

### Endpoint: `/permissions/{type}`

Get detailed status for a specific permission (e.g., `/permissions/photos`).

## Supported Permissions

| Permission | Framework | Class to Check | iOS Version |
|------------|-----------|----------------|-------------|
| Photos | PhotosUI/Photos | `PHPhotoLibrary` | 8.0+ |
| Camera | AVFoundation | `AVCaptureDevice` | 7.0+ |
| Microphone | AVFoundation | `AVCaptureDevice` | 7.0+ |
| Contacts | Contacts | `CNContactStore` | 9.0+ |
| Calendar | EventKit | `EKEventStore` | 6.0+ |
| Reminders | EventKit | `EKEventStore` | 6.0+ |
| Location | CoreLocation | `CLLocationManager` | 2.0+ |
| Notifications | UserNotifications | `UNUserNotificationCenter` | 10.0+ |
| Health | HealthKit | `HKHealthStore` | 8.0+ |
| Motion | CoreMotion | `CMMotionActivityManager` | 7.0+ |
| Speech | Speech | `SFSpeechRecognizer` | 10.0+ |
| Bluetooth | CoreBluetooth | `CBCentralManager` | 5.0+ |
| HomeKit | HomeKit | `HMHomeManager` | 8.0+ |
| Media Library | MediaPlayer | `MPMediaLibrary` | 9.3+ |
| Siri | Intents | `INPreferences` | 10.0+ |

## Tasks

- [x] Create PermissionsEndpoints.swift in Endpoints/
- [x] Implement framework detection helper using NSClassFromString
- [x] Implement permission status checking for each supported type
- [x] Create `/permissions` index endpoint (router pattern)
- [x] Create `/permissions/all` endpoint returning all permission states
- [x] Create `/permissions/list` endpoint listing supported types
- [x] Create `/permissions/get?type=<type>` endpoint for specific permission
- [x] Register with RootRouter
- [x] Build and verify no compile errors
- [x] Run existing tests to verify no regressions (130 tests pass)
- [x] Add unit tests for PermissionsEndpoints (15 new tests)
- [x] Test with demo app via CLI
- [x] Run swiftformat

## Implementation Notes - Discovered During Implementation

### Siri Entitlement Requirement

The Siri permission check (`INPreferences.siriAuthorizationStatus()`) throws an NSException if the app doesn't have the `com.apple.developer.siri` entitlement. We handle this by returning `.restricted` for Siri if the framework is linked but the entitlement is missing.

## Implementation Notes

### Framework Detection Pattern

```swift
private static func isFrameworkLinked(_ className: String) -> Bool {
    return NSClassFromString(className) != nil
}
```

### Permission Checking Pattern

For each permission type, use `performSelector` or similar runtime calls to avoid compile-time dependencies:

```swift
private static func checkPhotosPermission() -> PermissionStatus {
    guard let phClass = NSClassFromString("PHPhotoLibrary") as? NSObject.Type else {
        return .notLinked
    }
    // Use runtime method invocation to get authorization status
}
```

### Async Permission Checks

Some permissions require async checks. For the initial implementation:
- Return current cached state if available
- For notifications, need to use completion handler approach

### Main Thread Considerations

Some permission checks must run on main thread. Set `runsOnMainThread: true` if needed.

## File Structure

```
server/Sources/AppXplorerServer/
├── Endpoints/
│   ├── PermissionsEndpoints.swift  # New file
│   └── RootRouter.swift            # Update to register permissions
```
