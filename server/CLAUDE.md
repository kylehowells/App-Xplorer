# CLAUDE.md - AppXplorerServer

## Project Overview

AppXplorerServer is a transport-agnostic debugging server that runs inside iOS apps. It provides remote access to app internals (screenshots, view hierarchy, file system, UserDefaults, etc.) over HTTP, WebSocket, Iroh, Bluetooth, or any other transport mechanism.

## Key Architecture

The server follows a transport-agnostic design. See `docs/architecture.md` for full details.

**Core components:**
- `Request` / `Response` - Transport-agnostic request/response types
- `RequestHandler` - Central router that dispatches requests to handlers
- `TransportAdapter` - Protocol for transport implementations (HTTP, WebSocket, etc.)
- `RootRouter` - Configures built-in endpoints (/info, /files, /userdefaults, etc.)

## Development Guidelines

### Documentation

- **Read** `docs/` before making significant changes
- **Update** `docs/architecture.md` when modifying core architecture
- **Create** new docs in `docs/` for major new features or subsystems

### Testing

- Key components should have unit tests
- Run tests before committing: `swift test`
- Tests are in `Tests/AppXplorerServerTests/`
- Test files should be named to match their implementation files (e.g., `FilesEndpointsTests.swift` for `FilesEndpoints.swift`)

### Code Formatting

Run SwiftFormat after making changes:
```bash
swiftformat .
```

Configuration is in `.swiftformat`. Key rules:
- Explicit `self` for all property/method access
- Tab indentation (4-space width)
- Trailing commas in collections

### Git Workflow

**Before starting a large change or refactor:**
1. Ensure all current work is committed
2. This allows rollback if needed

**After completing a feature:**
1. Run `swiftformat .`
2. Run `swift test` to verify tests pass
3. Run `swift build` to verify build succeeds
4. Commit with a descriptive message

### Building

```bash
swift build        # Debug build
swift build -c release  # Release build
swift test         # Run tests
```

## File Structure

```
server/
├── CLAUDE.md                    # This file
├── Package.swift                # Swift package manifest
├── .swiftformat                 # SwiftFormat configuration
├── docs/
│   └── architecture.md          # Architecture documentation
├── Sources/AppXplorerServer/
│   ├── AppXplorerServer.swift   # Main server class
│   ├── Core/
│   │   ├── Request.swift        # Transport-agnostic request
│   │   ├── Response.swift       # Transport-agnostic response
│   │   ├── RequestHandler.swift # Central router
│   │   ├── TransportAdapter.swift # Transport protocol
│   │   ├── LogStore.swift       # SQLite log storage
│   │   └── SafeAddressLookup.swift # Memory address validation
│   ├── Endpoints/
│   │   ├── RootRouter.swift      # Root router configuration
│   │   ├── InfoEndpoints.swift   # /info, /screenshot
│   │   ├── FilesEndpoints.swift  # /files/* sub-router
│   │   ├── UserDefaultsEndpoints.swift # /userdefaults/*
│   │   ├── HierarchyEndpoints.swift # /hierarchy/* sub-router
│   │   ├── PermissionsEndpoints.swift # /permissions/* sub-router
│   │   ├── InteractEndpoints.swift # /interact/* sub-router
│   │   └── LogEndpoints.swift    # /logs/* sub-router
│   └── Transports/
│       └── HTTPTransportAdapter.swift # HTTP via Swifter
└── Tests/
    └── AppXplorerServerTests/
```

## Usage Example

```swift
// Simple HTTP server
let server = AppXplorerServer.withHTTP(port: 8080)
try server.start()

// Custom endpoint
server["/custom"] = { request in
    return .json(["hello": "world"])
}
```

## API Reference

### Root Endpoints

- `GET /` - API index and discovery (lists all endpoints)
- `GET /info` - App bundle info and device info
- `GET /screenshot` - Capture app screenshot (PNG)

### Sub-Routers

#### `/files/*` - File System Access
- `GET /files/` - List directory contents
- `GET /files/read` - Read file content
- `POST /files/write` - Write file content
- `DELETE /files/delete` - Delete file
- `GET /files/containers` - List app containers (documents, library, etc.)

#### `/hierarchy/*` - View Hierarchy Inspection
- `GET /hierarchy/views` - Complete view hierarchy tree (JSON or XML format)
- `GET /hierarchy/windows` - List all windows with properties
- `GET /hierarchy/window-scenes` - List UIWindowScenes with details
- `GET /hierarchy/view-controllers` - View controller hierarchy
- `GET /hierarchy/responder-chain` - Responder chain from a view/first responder
- `GET /hierarchy/first-responder` - Current first responder and path to it

#### `/userdefaults/*` - UserDefaults Access
- `GET /userdefaults/` - List all UserDefaults keys
- `GET /userdefaults/get` - Get value for key
- `POST /userdefaults/set` - Set value for key
- `DELETE /userdefaults/delete` - Delete key

#### `/permissions/*` - System Permission States
- `GET /permissions/all` - All permission states (photos, camera, location, etc.)
- `GET /permissions/list` - List supported permission types
- `GET /permissions/get?type=X` - Check specific permission
- `GET /permissions/refresh` - Trigger async permission checks (notifications, siri)

Supported permission types: photos, camera, microphone, contacts, calendar, reminders, location, notifications, health, motion, speech, bluetooth, homekit, medialibrary, siri

#### `/interact/*` - UI Interaction
- `GET /interact/tap?address=0x...` - Tap a UI element (UIControl or accessibility)
- `GET /interact/type?text=X` - Type text into first responder or specific view
- `GET /interact/focus?address=0x...` - Make a view become first responder
- `GET /interact/resign` - Resign first responder (dismiss keyboard)
- `GET /interact/scroll?address=0x...` - Scroll a UIScrollView
- `GET /interact/swipe?address=0x...&direction=left` - Trigger swipe gesture
- `GET /interact/accessibility?address=0x...` - Perform accessibility actions
- `GET /interact/select-cell?address=0x...&row=N` - Select table/collection view cell

#### `/logs/*` - Log Ingestion & Retrieval
Apps can pipe their logs to App-Xplorer for remote viewing.

- `GET /logs/` - Fetch logs (JSONL format by default)
  - Query params: `start`, `end` (ISO8601), `type`, `match` (SQL LIKE pattern), `limit`, `offset`, `sort` (newest/oldest), `format` (jsonl/json)
- `GET /logs/info` - Session info (sessionId, databasePath, count)
- `GET /logs/clear` - Clear all logs

**Swift API for logging:**
```swift
// Log messages from your app
AppXplorerServer.log("User logged in", type: "auth")
AppXplorerServer.log("API request failed", type: "network")
```

Logs are stored in SQLite at `/Library/Xplorer/sessions/<session-id>/logs.db`

### Output Formats

- **JSON** (default) - Standard JSON responses
- **XML** - HTML-like DOM tree for `/hierarchy/views?format=xml`
- **JSONL** - One JSON object per line for `/logs/` endpoint

## Adding New Features

### Adding a new endpoint:
1. Each root-level endpoint (e.g., `/files/`, `/info`) should have its own file in `Endpoints/`
2. Wire up the new endpoint in `RootRouter.swift`
3. Add tests in a matching test file (e.g., `FilesEndpoints.swift` → `FilesEndpointsTests.swift`)
4. Update `docs/` if it's a significant feature

### Adding a new transport:
1. Create new file in `Transports/` implementing `TransportAdapter`
2. Add tests for the transport adapter
3. Update `docs/architecture.md` with transport details
