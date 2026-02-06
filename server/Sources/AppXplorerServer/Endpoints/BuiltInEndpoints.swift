import Foundation

// MARK: - BuiltInEndpoints

/// Built-in endpoints for AppXplorerServer
public enum BuiltInEndpoints {
	/// Register all built-in endpoints with the request handler
	public static func registerAll(with handler: RequestHandler) {
		self.registerIndex(with: handler)
		InfoEndpoints.register(with: handler)
		FilesEndpoints.register(with: handler)
		UserDefaultsEndpoints.register(with: handler)
	}

	// MARK: - Index

	private static func registerIndex(with handler: RequestHandler) {
		handler["/"] = { _ in
			return .html("""
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
			    <h1>AppXplorer Server</h1>
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
			        <strong>GET /files/list</strong> - List directory contents
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /files/metadata</strong> - Get file/directory metadata
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /files/read</strong> - Read file contents
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /files/head</strong> - Read first N lines of text file
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /files/tail</strong> - Read last N lines of text file
			    </div>
			
			    <div class="endpoint">
			        <strong>GET /userdefaults</strong> - View UserDefaults
			    </div>
			
			    <p><small>Version 1.0.0</small></p>
			</body>
			</html>
			""")
		}
	}
}
