# Testing with the iOS Simulator

This guide explains how to test new server features using the demo app and CLI.

## Overview

The development workflow for testing new server endpoints:

1. Build and run the demo app in the iOS Simulator
2. Use the `xplorer` CLI to interact with the server
3. Verify endpoints return expected data

## Building the Demo App

From the `demo/` directory:

```bash
# Generate/regenerate the Xcode project (if project.yml changed)
cd demo
xcodegen generate

# Build for simulator
xcodebuild -project AppXplorerDemo.xcodeproj \
  -scheme AppXplorerDemo \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

## Running in the Simulator

### Option 1: Command Line

```bash
# List available simulators
xcrun simctl list devices available | grep iPhone

# Boot a simulator (if not already running)
xcrun simctl boot "iPhone 16"

# Install the app
xcrun simctl install booted \
  ~/Library/Developer/Xcode/DerivedData/AppXplorerDemo-*/Build/Products/Debug-iphonesimulator/AppXplorerDemo.app

# Launch the app
xcrun simctl launch booted com.appxplorer.demo
```

### Option 2: Xcode

1. Open `demo/AppXplorerDemo.xcodeproj`
2. Select an iPhone simulator
3. Press Cmd+R to build and run

## Using the CLI

The `xplorer` CLI connects to the running server. Build it first:

```bash
cd cli
swift build
```

### Basic Usage

```bash
# Get API index (lists all endpoints)
swift run xplorer localhost:8080

# Get app/device info
swift run xplorer localhost:8080 info

# Capture full screen screenshot
swift run xplorer localhost:8080 screenshot -o screenshot.png

# Capture screenshot as JPEG with custom quality
swift run xplorer localhost:8080 "screenshot?format=jpeg&quality=0.8" -o screenshot.jpg
```

### File System

```bash
# List app's home directory
swift run xplorer localhost:8080 files/list

# List using directory aliases
swift run xplorer localhost:8080 "files/list?path=documents"
swift run xplorer localhost:8080 "files/list?path=caches"
swift run xplorer localhost:8080 "files/list?path=bundle"

# List key directories (shows all aliases)
swift run xplorer localhost:8080 files/key-directories

# Read a file
swift run xplorer localhost:8080 "files/read?path=bundle/Info.plist"

# Get file metadata
swift run xplorer localhost:8080 "files/metadata?path=documents/data.json"

# Read first/last lines of a file
swift run xplorer localhost:8080 "files/head?path=tmp/log.txt&lines=20"
swift run xplorer localhost:8080 "files/tail?path=tmp/log.txt&lines=50"
```

### View Hierarchy

```bash
# List all windows
swift run xplorer localhost:8080 hierarchy/windows

# Get view controller hierarchy
swift run xplorer localhost:8080 hierarchy/view-controllers

# Get full view hierarchy (includes memory addresses)
swift run xplorer localhost:8080 hierarchy/views

# Get view hierarchy with limited depth
swift run xplorer localhost:8080 "hierarchy/views?maxDepth=3&properties=minimal"

# Get view hierarchy with full property detail
swift run xplorer localhost:8080 "hierarchy/views?properties=full"

# List window scenes
swift run xplorer localhost:8080 hierarchy/window-scenes

# Get first responder
swift run xplorer localhost:8080 hierarchy/first-responder

# Get responder chain from first responder
swift run xplorer localhost:8080 hierarchy/responder-chain

# Get responder chain starting from a specific view (by memory address)
swift run xplorer localhost:8080 "hierarchy/responder-chain?from=0x12345678"
```

### Screenshots of Specific Views

The screenshot endpoint supports capturing individual views by their memory address:

```bash
# First, get the view hierarchy to find addresses
swift run xplorer localhost:8080 "hierarchy/views?maxDepth=4&properties=minimal"

# Capture the full screen
swift run xplorer localhost:8080 screenshot -o fullscreen.png

# Capture a specific view by address
swift run xplorer localhost:8080 "screenshot?view=0x12345678" -o myview.png

# Capture with custom scale and format
swift run xplorer localhost:8080 "screenshot?view=0x12345678&scale=2.0&format=jpeg&quality=0.9" -o myview.jpg

# Use afterScreenUpdates for views with pending animations
swift run xplorer localhost:8080 "screenshot?view=0x12345678&afterScreenUpdates=true" -o myview.png
```

### UserDefaults

```bash
# List all UserDefaults endpoints
swift run xplorer localhost:8080 userdefaults

# Get all key-value pairs
swift run xplorer localhost:8080 userdefaults/all

# Filter out Apple system keys
swift run xplorer localhost:8080 "userdefaults/all?filterSystem=true"

# List just the keys
swift run xplorer localhost:8080 "userdefaults/keys?filterSystem=true"

# Search for keys/values
swift run xplorer localhost:8080 "userdefaults/search?query=demo"

# Get a specific key
swift run xplorer localhost:8080 "userdefaults/get?key=demo.userName"

# Group keys by type
swift run xplorer localhost:8080 userdefaults/types

# List available suites and domains
swift run xplorer localhost:8080 userdefaults/suites
swift run xplorer localhost:8080 userdefaults/domains
```

### Permissions

```bash
# List all permission endpoints
swift run xplorer localhost:8080 permissions

# List all supported permission types
swift run xplorer localhost:8080 permissions/list

# Get all permission states at once
swift run xplorer localhost:8080 permissions/all

# Get a specific permission state
swift run xplorer localhost:8080 "permissions/get?type=photos"
swift run xplorer localhost:8080 "permissions/get?type=camera"
swift run xplorer localhost:8080 "permissions/get?type=location"
```

Note: Permissions uses runtime framework detection. If a framework isn't linked by the host app, the status will be `not_linked`. Some permissions (notifications, health, homeKit) require async checks and may show `unknown`.

## Troubleshooting

### Connection Refused

If you get "Could not connect to localhost:8080":

1. Ensure the demo app is running in the simulator
2. Check the app shows "Server: Running" on screen
3. Try restarting the app

### Local Network Permission

On a physical device, you may see a "Local Network" permission prompt. Accept it to allow CLI connections.

In the simulator, this permission is typically not required.

### Port Already in Use

If port 8080 is busy, the server will fail to start. Check for other processes:

```bash
lsof -i :8080
```

## Quick Test Script

Here's a quick script to verify all major endpoints work:

```bash
#!/bin/bash
HOST="localhost:8080"

echo "=== Testing App-Xplorer Server ==="

cd cli

echo -e "\n--- Root Index ---"
swift run xplorer $HOST | head -20

echo -e "\n--- App Info ---"
swift run xplorer $HOST info

echo -e "\n--- Screenshot ---"
swift run xplorer $HOST screenshot -o /tmp/test-screenshot.png
echo "Screenshot saved to /tmp/test-screenshot.png"

echo -e "\n--- Windows ---"
swift run xplorer $HOST hierarchy/windows

echo -e "\n--- View Controllers ---"
swift run xplorer $HOST hierarchy/view-controllers

echo -e "\n--- View Hierarchy (with addresses) ---"
swift run xplorer $HOST "hierarchy/views?maxDepth=2&properties=minimal"

echo -e "\n--- Key Directories ---"
swift run xplorer $HOST files/key-directories

echo -e "\n--- Files ---"
swift run xplorer $HOST files/list | head -30

echo -e "\n--- UserDefaults ---"
swift run xplorer $HOST "userdefaults/all?filterSystem=true" | head -20

echo -e "\n--- Permissions ---"
swift run xplorer $HOST permissions/all

echo -e "\n=== All tests complete ==="
```

## Memory Address Lookup

Several endpoints support looking up objects by their memory address (displayed as hex like `0x12345678`):

| Endpoint | Parameter | Description |
|----------|-----------|-------------|
| `/hierarchy/responder-chain` | `from` | Start responder chain from a specific UIResponder |
| `/screenshot` | `view` | Capture screenshot of a specific UIView |

These use the `SafeAddressLookup` utility which validates addresses using the ObjC runtime before dereferencing, preventing crashes from invalid addresses.
