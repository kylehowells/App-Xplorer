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
│   │   └── TransportAdapter.swift # Transport protocol
│   ├── Endpoints/
│   │   ├── RootRouter.swift      # Root router configuration
│   │   ├── InfoEndpoints.swift   # /info, /screenshot, /hierarchy
│   │   ├── FilesEndpoints.swift  # /files/* sub-router
│   │   └── UserDefaultsEndpoints.swift # /userdefaults
│   └── Transports/
│       └── HTTPTransportAdapter.swift # HTTP via Swifter
└── Tests/
    └── AppXplorerServerTests/
        ├── RequestTests.swift        # Request type tests
        ├── ResponseTests.swift       # Response type tests
        ├── RequestHandlerTests.swift # Router and sub-router tests
        ├── FilesEndpointsTests.swift # /files/* endpoint tests
        └── RootRouterTests.swift     # Root router integration tests
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
