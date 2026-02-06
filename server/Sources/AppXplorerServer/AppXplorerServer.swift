import Foundation
import Swifter
#if canImport(UIKit)
	import UIKit
#endif

// MARK: - AppXplorerServer

/// AppXplorerServer - A debugging server that runs inside iOS apps
/// Provides remote access to app internals for debugging purposes
public class AppXplorerServer {
	private let server = HttpServer()
	private var isRunning = false
	public private(set) var port: UInt16 = 8080

	public init(port: UInt16 = 8080) {
		self.port = port
		self.setupRoutes()
	}

	/// Start the debugging server
	public func start() throws {
		guard !self.isRunning else { return }

		try self.server.start(self.port, forceIPv4: false, priority: .background)
		self.isRunning = true

		print("🚀 AppXplorerServer started on port \(self.port)")
		print("📱 Connect to: http://\(self.getWiFiAddress() ?? "localhost"):\(self.port)")
	}

	/// Stop the debugging server
	public func stop() {
		self.server.stop()
		self.isRunning = false
		print("🛑 AppXplorerServer stopped")
	}

	// MARK: - Routes Setup

	private func setupRoutes() {
		// Hello world endpoint
		self.server["/"] = { request in
			return .ok(.html("""
			<!DOCTYPE html>
			<html>
			<head>
			    <title>AppXplorer Server</title>
			    <meta name="viewport" content="width=device-width, initial-scale=1">
			    <style>
			        body {
			            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
			            padding: 20px;
			            max-width: 800px;
			            margin: 0 auto;
			        }
			        h1 { color: #007AFF; }
			        .endpoint {
			            background: #f5f5f5;
			            padding: 10px;
			            margin: 10px 0;
			            border-radius: 5px;
			        }
			        code {
			            background: #e0e0e0;
			            padding: 2px 5px;
			            border-radius: 3px;
			        }
			    </style>
			</head>
			<body>
			    <h1>📱 AppXplorer Server</h1>
			    <p>Debug server is running! Available endpoints:</p>
			
			    <div class="endpoint">
			        <strong>GET /info</strong> - Get app and device information
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /screenshot</strong> - Capture current screen
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /hierarchy</strong> - Get view hierarchy
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /files</strong> - Browse file system
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /userdefaults</strong> - View UserDefaults
			    </div>
			
			    <p><small>Version 1.0.0</small></p>
			</body>
			</html>
			"""))
		}

		// App info endpoint
		self.server["/info"] = { request in
			#if canImport(UIKit)
				let device = UIDevice.current
				let bundle = Bundle.main
				let screen = UIScreen.main

				let info: [String: Any] = [
					"app": [
						"name": bundle.object(forInfoDictionaryKey: "CFBundleName") ?? "Unknown",
						"version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "Unknown",
						"build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "Unknown",
						"bundleId": bundle.bundleIdentifier ?? "Unknown",
					],
					"device": [
						"name": device.name,
						"model": device.model,
						"systemVersion": device.systemVersion,
						"systemName": device.systemName,
					],
					"screen": [
						"width": screen.bounds.width,
						"height": screen.bounds.height,
						"scale": screen.scale,
					],
					"timestamp": ISO8601DateFormatter().string(from: Date()),
				]
			#else
				let bundle = Bundle.main
				let info: [String: Any] = [
					"app": [
						"name": bundle.object(forInfoDictionaryKey: "CFBundleName") ?? "Unknown",
						"version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "Unknown",
						"build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") ?? "Unknown",
						"bundleId": bundle.bundleIdentifier ?? "Unknown",
					],
					"platform": "macOS",
					"timestamp": ISO8601DateFormatter().string(from: Date()),
				]
			#endif

			return .ok(.json(info as AnyObject))
		}

		// Screenshot endpoint (placeholder for now)
		self.server["/screenshot"] = { request in
			return .ok(.json([
				"status": "pending",
				"message": "Screenshot functionality will be implemented soon",
			] as AnyObject))
		}

		// View hierarchy endpoint (placeholder for now)
		self.server["/hierarchy"] = { request in
			return .ok(.json([
				"status": "pending",
				"message": "View hierarchy functionality will be implemented soon",
			] as AnyObject))
		}
	}

	// MARK: - Helpers

	/// Get the device's WiFi IP address
	private func getWiFiAddress() -> String? {
		var address: String?

		// Get list of all interfaces on the local machine
		var ifaddr: UnsafeMutablePointer<ifaddrs>?
		guard getifaddrs(&ifaddr) == 0 else { return nil }

		guard let firstAddr = ifaddr else { return nil }

		// For each interface
		for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
			let interface = ifptr.pointee

			// Check for IPv4 interface
			let addrFamily = interface.ifa_addr.pointee.sa_family
			if addrFamily == UInt8(AF_INET) {
				// Check interface name
				let name = String(cString: interface.ifa_name)
				if name == "en0" { // WiFi interface

					// Convert interface address to a human readable string
					var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
					getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
					            &hostname, socklen_t(hostname.count),
					            nil, socklen_t(0), NI_NUMERICHOST)
					address = String(cString: hostname)
				}
			}
		}

		freeifaddrs(ifaddr)
		return address
	}
}