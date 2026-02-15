// Simple test server for Iroh transport testing
// Run with: swift run IrohTestServer

import AppXplorerIroh
import AppXplorerServer
import Foundation

print("Starting Iroh Test Server...")
fflush(stdout)

/// Use temporary directory for this test instance
let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("iroh-test-server-\(ProcessInfo.processInfo.processIdentifier)")
print("Storage path: \(tempDir.path)")
fflush(stdout)

// Create server with Iroh transport only (no HTTP to avoid port conflicts)
let server = AppXplorerServer()
let irohTransport = IrohTransportAdapter(storagePath: tempDir.path)
server.addTransport(irohTransport)

print("Starting server with Iroh transport...")
fflush(stdout)

do {
	try server.start()

	print("")
	print("========================================")
	print("Server is running!")
	print("========================================")
	print("")
	print("Iroh Node ID:")
	print(irohTransport.nodeId ?? "unknown")
	print("")
	if let relay = irohTransport.relayUrl {
		print("Relay URL: \(relay)")
		print("")
	}
	print("========================================")
	print("")
	print("Test with CLI:")
	print("  xplorer iroh:\(irohTransport.nodeId ?? "<node_id>") info")
	print("  xplorer iroh:\(irohTransport.nodeId ?? "<node_id>") test")
	print("")
	print("Press Ctrl+C to stop")
	print("")
	fflush(stdout)
}
catch {
	print("Failed to start server: \(error)")
	fflush(stdout)
	exit(1)
}

// Keep the process running
RunLoop.main.run()
