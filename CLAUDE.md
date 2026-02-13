# CLAUDE.md - App-Xplorer

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

App-Xplorer is a debugging toolkit for iOS apps consisting of:

1. **server/** - A Swift package that runs inside iOS apps, providing a self-documenting API for remote debugging (screenshots, view hierarchy, files, UserDefaults, permissions, UI interaction, logs, etc.)
2. **client/** - A Swift client library for connecting to the server
3. **demo/** - A simple iOS app for testing the server functionality
4. **cli/** - A command-line interface for interacting with the server

## API Endpoints Overview

The server exposes the following API endpoints:

### Root Endpoints
- `GET /` - API index and discovery
- `GET /info` - App and device information
- `GET /screenshot` - Capture app screenshot

### Sub-Routers
- `/files/*` - File system access (read/write/delete/list)
- `/hierarchy/*` - View hierarchy inspection (views, windows, view controllers, responder chain)
- `/userdefaults/*` - UserDefaults read/write
- `/permissions/*` - System permission states (photos, camera, location, notifications, etc.)
- `/interact/*` - UI interaction (tap, type, scroll, swipe, focus/resign, select cells)
- `/logs/*` - Log ingestion and retrieval (SQLite-backed, JSONL output)

See `server/CLAUDE.md` for full API documentation.

## Development Guidelines

### Coding Style

- Tabs for indentation
- Explicit `self.` for all property/method access
- Type annotations for variables
- `else` statements on their own line (never `} else {`)
- Follow patterns in existing code

### Testing

- Run tests before committing: `swift test` (in server/ directory)
- Tests are in `server/Tests/AppXplorerServerTests/`
- Test files should match implementation files (e.g., `FilesEndpoints.swift` → `FilesEndpointsTests.swift`)

---

## Development Workflow for New Features

When implementing new server features, follow this workflow:

### 1. Implement the Feature

- Add new endpoints or modify existing ones in `server/Sources/AppXplorerServer/Endpoints/`
- For reusable utilities, add them to `server/Sources/AppXplorerServer/Core/`
- Follow existing code patterns and style guidelines

### 2. Add Unit Tests

- Create or update test file in `server/Tests/AppXplorerServerTests/`
- Test parameter validation, error cases, and expected responses
- Run tests: `cd server && swift test`

### 3. Live Testing with Demo App

Build and deploy the demo app to the simulator:

```bash
# Find a booted simulator
xcrun simctl list devices | grep "Booted"

# Build the demo app (uses local server package)
cd demo
xcodebuild -project AppXplorerDemo.xcodeproj \
  -scheme AppXplorerDemo \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  build

# Install and launch
xcrun simctl install <SIMULATOR_UUID> \
  ~/Library/Developer/Xcode/DerivedData/AppXplorerDemo-*/Build/Products/Debug-iphonesimulator/AppXplorerDemo.app
xcrun simctl launch <SIMULATOR_UUID> com.appxplorer.demo
```

### 4. Test with CLI

Use the CLI to interact with your new feature:

```bash
cd cli

# Get API index to see all endpoints
swift run xplorer localhost:8080

# Test your new endpoint
swift run xplorer localhost:8080 "your/endpoint?param=value"

# Save binary output (screenshots, files) to a file
swift run xplorer localhost:8080 "screenshot" -o output.png
```

### 5. Example: Testing View Screenshot Feature

```bash
# Get view hierarchy to find memory addresses
swift run xplorer localhost:8080 "hierarchy/views?maxDepth=3&properties=minimal"

# Screenshot a specific view by address
swift run xplorer localhost:8080 "screenshot?view=0x12345678" -o view.png

# Test error handling with invalid address
swift run xplorer localhost:8080 "screenshot?view=0xDEADBEEF"
```

### 6. Complete the Feature

1. Ensure all tests pass: `cd server && swift test`
2. Run SwiftFormat: `cd server && swiftformat .`
3. Commit with a descriptive message

See **`docs/testing-with-simulator.md`** for more CLI examples and troubleshooting.

### Code Formatting

Run SwiftFormat after making changes:
```bash
cd server && swiftformat .
```

---

## Plans

While working on implementing features, break it down into a planned TODO list.
At the top of the file should be a brief explanation of the goal and then a series of todo items which you should keep up to date as you work.

<example>
Implement this new feature X because Y. To do so we create ABC.swift file and change example.swift to use this new API.

- [ ] Create new ABC.swift file.
- [ ] Update example.swift to use new API.
- [ ] Build project to check file build errors.
- [ ] Perform a quick code review of the changes
- [ ] Check the changes use existing code patterns in the project
</example>

As you work, "tick off" `[x]` items so if interrupted you can pick up where you left off.

**Plan files should be stored in:** `plans/<YYYY-MM-DD>-<HHmm>-change-description.md`

**Important Note for Claude**: Always run `date "+%Y-%m-%d-%H%M"` to check the current date and time before creating plan document filenames. Never assume or guess the date.

### On Completing a Plan

Once you finish a feature:
1. Test the project still builds
2. Run tests if applicable
3. Git commit your changes with a proper commit message

---

## Temp Scripts & Python Scripts

If you need to run a quick script while working, default to Python and create it in the `scratchpad/` directory.

---

## File Structure

```
App-Xplorer/
├── CLAUDE.md              # This file (root project guidance)
├── plans/                 # Plan documents for features/changes
├── scratchpad/            # Temporary scripts for testing
├── server/                # Swift package - debugging server
│   ├── CLAUDE.md          # Server-specific guidance
│   ├── Package.swift
│   ├── Sources/
│   └── Tests/
├── client/                # Swift client library
├── demo/                  # iOS demo app for testing
└── cli/                   # Command-line interface
```

---

## Future Transport Plans

Currently the server uses HTTP for transport. Future plans include:
- **Iroh** - Peer-to-peer networking for direct device connections
- **WebSocket** - For real-time bidirectional communication
- **Bluetooth** - For local debugging without network

The CLI and client are designed to be transport-agnostic to support these future options.
