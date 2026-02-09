# Fix Async Permissions and Siri Exception Handling

**Date:** 2026-02-08
**Goal:** Make ALL permission states accessible, including async ones (notifications, health, homeKit) and properly handle Siri's entitlement exception.

## Current Problems

1. **Siri** - Hardcoded to `.restricted` instead of catching the NSException
2. **Notifications** - Returns `.unknown` because it requires async completion handler
3. **Health** - Returns `.unknown` because checking requires async completion handler
4. **HomeKit** - Returns `.unknown` because it requires delegate callbacks

## Solution: Two-Phase API with Caching

### New Endpoints

1. **`/permissions/refresh`** - Trigger async permission checks, returns immediately
   - Moves async permissions to `checking` state
   - Triggers async checks in background
   - Results are cached when callbacks complete

2. **`/permissions/all`** (existing) - Returns cached states
   - Sync permissions: checked live
   - Async permissions: return cached state (or `not_checked` if never refreshed)

3. **`/permissions/get?type=<type>`** (existing) - Same behavior

### New Permission States

- `checking` - Async check in progress
- `not_checked` - Never checked (async permissions before first refresh)

### Implementation Approach

#### 1. Permission Cache
```swift
private static var permissionCache: [PermissionType: CachedPermission] = [:]

private struct CachedPermission {
    let status: PermissionStatus
    let timestamp: Date
    let isChecking: Bool
}
```

#### 2. Siri Exception Handling

Use ObjC exception catching via a helper:
```swift
private static func checkSiriPermission() -> PermissionStatus {
    guard let inClass = NSClassFromString("INPreferences") as? NSObject.Type else {
        return .notLinked
    }

    // Try to catch ObjC exception
    var status: PermissionStatus = .unknown
    let success = tryObjCBlock {
        let selector = NSSelectorFromString("siriAuthorizationStatus")
        guard inClass.responds(to: selector) else {
            status = .unknown
            return
        }
        let result = inClass.perform(selector)
        // ... decode status
    }

    if !success {
        // Exception was thrown - missing entitlement
        return .restricted  // Or a new state like .entitlementMissing
    }
    return status
}
```

#### 3. Notifications Async Check

```swift
private static func refreshNotificationsPermission(completion: @escaping (PermissionStatus) -> Void) {
    guard let unClass = NSClassFromString("UNUserNotificationCenter") else {
        completion(.notLinked)
        return
    }

    // Get current notification center using runtime
    let currentSelector = NSSelectorFromString("currentNotificationCenter")
    guard let center = unClass.perform(currentSelector)?.takeUnretainedValue() else {
        completion(.unknown)
        return
    }

    // Call getNotificationSettingsWithCompletionHandler:
    let settingsSelector = NSSelectorFromString("getNotificationSettingsWithCompletionHandler:")
    // ... invoke with completion block
}
```

## Tasks

- [x] Add `CachedPermission` struct and cache storage
- [x] Add new states: `checking`, `not_checked`, `entitlement_missing`
- [x] Implement Siri entitlement check (via Info.plist NSSiriUsageDescription)
- [x] Implement async notification permission check
- [x] Mark Health as not-async (requires specific data types - left as sync)
- [x] Mark HomeKit as not-async (requires HMHomeManager delegate - left as sync)
- [x] Add `/permissions/refresh` endpoint
- [x] Update `/permissions/all` to use cache for async permissions
- [x] Update response to include `lastChecked` timestamp and `isAsync` field
- [x] Add unit tests (132 tests pass)
- [x] Test with demo app

## Response Format Update

```json
{
  "permissions": [
    {
      "type": "notifications",
      "status": "authorized",
      "description": "Full access granted",
      "lastChecked": "2026-02-08T21:16:00Z",
      "isAsync": true
    },
    {
      "type": "photos",
      "status": "not_linked",
      "description": "Framework not linked by app",
      "lastChecked": null,
      "isAsync": false
    }
  ]
}
```

## Notes

- Health permission requires specifying which data types to check - may need to return "requires_configuration" or check a default set
- HomeKit has no simple status API - requires creating HMHomeManager and waiting for delegate
- Consider adding `entitlement_missing` state for Siri case specifically
