# Demo App and CLI Implementation

**Date:** 2026-02-06
**Goal:** Create a demo iOS app to test the AppXplorerServer functionality, and a CLI tool to interact with the server.

## Overview

We need two new components:
1. **demo/** - A minimal iOS app that loads the server Swift package and starts it on launch
2. **cli/** - A command-line tool that connects to the server and queries its APIs

The CLI should be transport-agnostic in design (currently HTTP, future: Iroh, WebSocket, etc.).

## Tasks

- [x] Create root CLAUDE.md with plan file conventions
- [x] Create plans/ and scratchpad/ directories
- [x] Create this plan document

### CLI Implementation
- [x] Create cli/ Swift package structure
- [x] Implement HTTP transport client
- [x] Implement CLI argument parsing
- [x] Handle `cli <host>` - calls root index `/`
- [x] Handle `cli <host> <command>` - calls `/<command>` API
- [x] Support full URL-style requests (`files/list?path=/tmp`)
- [x] Format JSON output nicely
- [x] Add README.md with usage and future transport notes
- [x] Build and test CLI standalone

### Demo App Implementation
- [x] Create demo/ Xcode project structure
- [x] Add dependency on server Swift package
- [x] Create minimal UI showing server status and connection URL
- [x] Start server on app launch
- [x] Handle local network permission prompt
- [x] Build for simulator

### Integration Testing
- [x] Run demo app in simulator
- [x] Test CLI against demo app
- [x] Test various endpoints (/, /info, /files/list, etc.)
- [x] Debug any issues using scratchpad/ scripts if needed
- [x] Handle local network permission if prompted (not needed in simulator)

## Architecture Notes

### CLI Design
```
cli <host> [command]

Examples:
  cli 192.168.1.100:8080           # GET /
  cli 192.168.1.100:8080 info      # GET /info
  cli 192.168.1.100:8080 files/list?path=/tmp  # GET /files/list?path=/tmp
```

The CLI should:
- Accept host (with optional port, default 8080)
- Accept command (path + query string)
- Make HTTP GET request
- Pretty-print JSON response
- Show errors clearly

### Demo App Design
- Single-screen app showing:
  - Server status (running/stopped)
  - Connection URL (IP:port)
  - Instructions for CLI usage
- Server starts automatically on launch
- Handles local network permission

## Files to Create

### cli/
```
cli/
├── Package.swift
├── README.md
└── Sources/
    └── xplorer/
        └── main.swift
```

### demo/
```
demo/
├── AppXplorerDemo.xcodeproj/
├── AppXplorerDemo/
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── ViewController.swift
│   ├── Info.plist
│   └── Assets.xcassets/
└── README.md
```
