import Foundation
#if canImport(QuartzCore)
	import QuartzCore
#endif

// MARK: - FPSEndpoints

/// FPS monitoring endpoints
/// Provides frame timing data for performance analysis
public enum FPSEndpoints {

	/// Create a router for FPS endpoints
	public static func createRouter() -> RequestHandler {
		let router = RequestHandler(description: "FPS monitoring and frame timing data")

		// Index endpoint
		router.register("/", description: "List FPS endpoints", runsOnMainThread: false) { _ in
			return .json(router.routerInfo(deep: true))
		}

		// Register all endpoints
		self.registerEnableEndpoint(with: router)
		self.registerDisableEndpoint(with: router)
		self.registerStatusEndpoint(with: router)
		self.registerRecentEndpoint(with: router)
		self.registerHistoryEndpoint(with: router)
		self.registerClearEndpoint(with: router)

		return router
	}

	// MARK: - Enable

	private static func registerEnableEndpoint(with handler: RequestHandler) {
		handler.register(
			"/enable",
			description: "Enable FPS monitoring via CADisplayLink",
			runsOnMainThread: false
		) { _ in
			FPSMonitor.shared.enable()

			return .json([
				"success": true,
				"message": "FPS monitoring enabled",
				"note": "Frame data will be collected. Use /fps/status to check current state.",
			])
		}
	}

	// MARK: - Disable

	private static func registerDisableEndpoint(with handler: RequestHandler) {
		handler.register(
			"/disable",
			description: "Disable FPS monitoring",
			runsOnMainThread: false
		) { _ in
			FPSMonitor.shared.disable()

			return .json([
				"success": true,
				"message": "FPS monitoring disabled",
				"note": "Existing data is retained. Use /fps/clear to remove stored data.",
			])
		}
	}

	// MARK: - Status

	private static func registerStatusEndpoint(with handler: RequestHandler) {
		handler.register(
			"/status",
			description: "Get current FPS monitoring status",
			runsOnMainThread: false
		) { _ in
			let status = FPSMonitor.shared.getStatus()
			return .json(status)
		}
	}

	// MARK: - Recent (last 5 minutes, full resolution)

	private static func registerRecentEndpoint(with handler: RequestHandler) {
		handler.register(
			"/recent",
			description: "Get recent frame timing data (last 5 minutes, full resolution)",
			parameters: [
				ParameterInfo(
					name: "count",
					description: "Maximum number of frames to return",
					required: false,
					examples: ["100", "1000"]
				),
				ParameterInfo(
					name: "start",
					description: "Start timestamp (CACurrentMediaTime)",
					required: false,
					examples: ["12345.678"]
				),
				ParameterInfo(
					name: "end",
					description: "End timestamp (CACurrentMediaTime)",
					required: false,
					examples: ["12350.000"]
				),
				ParameterInfo(
					name: "order",
					description: "Sort order: 'asc' (oldest first) or 'desc' (newest first, default)",
					required: false,
					defaultValue: "desc",
					examples: ["asc", "desc"]
				),
				ParameterInfo(
					name: "seconds",
					description: "Shorthand: get last N seconds of data (alternative to start/end)",
					required: false,
					defaultValue: "10",
					examples: ["10", "60", "300"]
				),
			],
			runsOnMainThread: false
		) { request in
			let count = request.queryParams["count"].flatMap { Int($0) }
			let ascending = request.queryParams["order"] == "asc"

			// Handle time range
			var start: TimeInterval? = request.queryParams["start"].flatMap { Double($0) }
			let end: TimeInterval? = request.queryParams["end"].flatMap { Double($0) }

			// Get current time for relative calculations
			let currentTime = self.getCurrentTime()

			// Shorthand: last N seconds
			if start == nil, end == nil, let seconds = request.queryParams["seconds"].flatMap({ Double($0) }) {
				start = currentTime - seconds
			}

			// Default to last 10 seconds if no params
			if start == nil, end == nil, count == nil {
				start = currentTime - 10.0
			}

			let frames = FPSMonitor.shared.getRecentFrames(
				count: count,
				start: start,
				end: end,
				ascending: ascending
			)

			// Calculate summary stats
			let summary: [String: Any]
			if frames.isEmpty {
				summary = [
					"frameCount": 0,
					"note": "No frame data available. Is FPS monitoring enabled?",
				]
			}
			else {
				let durations = frames.map { $0.duration }
				let avgDuration = durations.reduce(0, +) / Double(durations.count)
				let minDuration = durations.min() ?? 0
				let maxDuration = durations.max() ?? 0

				summary = [
					"frameCount": frames.count,
					"averageFPS": avgDuration > 0 ? 1.0 / avgDuration : 0,
					"minFPS": maxDuration > 0 ? 1.0 / maxDuration : 0,
					"maxFPS": minDuration > 0 ? 1.0 / minDuration : 0,
					"averageFrameTime": avgDuration,
					"minFrameTime": minDuration,
					"maxFrameTime": maxDuration,
					"timeSpan": (frames.last?.timestamp ?? 0) - (frames.first?.timestamp ?? 0),
				]
			}

			return .json([
				"summary": summary,
				"frames": frames.map { frame in
					[
						"timestamp": frame.timestamp,
						"duration": frame.duration,
						"fps": frame.fps,
					]
				},
			])
		}
	}

	// MARK: - History (older than 5 minutes, 1-second buckets)

	private static func registerHistoryEndpoint(with handler: RequestHandler) {
		handler.register(
			"/history",
			description: "Get historical frame data (older than 5 minutes, aggregated to 1-second buckets)",
			parameters: [
				ParameterInfo(
					name: "count",
					description: "Maximum number of buckets to return",
					required: false,
					examples: ["100", "1000"]
				),
				ParameterInfo(
					name: "start",
					description: "Start timestamp (CACurrentMediaTime)",
					required: false,
					examples: ["12345.678"]
				),
				ParameterInfo(
					name: "end",
					description: "End timestamp (CACurrentMediaTime)",
					required: false,
					examples: ["12350.000"]
				),
				ParameterInfo(
					name: "order",
					description: "Sort order: 'asc' (oldest first) or 'desc' (newest first, default)",
					required: false,
					defaultValue: "desc",
					examples: ["asc", "desc"]
				),
			],
			runsOnMainThread: false
		) { request in
			let count = request.queryParams["count"].flatMap { Int($0) }
			let start = request.queryParams["start"].flatMap { Double($0) }
			let end = request.queryParams["end"].flatMap { Double($0) }
			let ascending = request.queryParams["order"] == "asc"

			let buckets = FPSMonitor.shared.getHistoryBuckets(
				count: count,
				start: start,
				end: end,
				ascending: ascending
			)

			// Calculate overall summary
			let summary: [String: Any]
			if buckets.isEmpty {
				summary = [
					"bucketCount": 0,
					"note": "No historical data available. Data older than 5 minutes is aggregated into 1-second buckets.",
				]
			}
			else {
				let totalFrames = buckets.reduce(0) { $0 + $1.frameCount }
				let avgFPS = buckets.reduce(0.0) { $0 + $1.averageFPS } / Double(buckets.count)

				// Find global min/max
				var globalMinTime = buckets[0].minFrameTime
				var globalMinTimestamp = buckets[0].minFrameTimestamp
				var globalMaxTime = buckets[0].maxFrameTime
				var globalMaxTimestamp = buckets[0].maxFrameTimestamp

				for bucket in buckets {
					if bucket.minFrameTime < globalMinTime {
						globalMinTime = bucket.minFrameTime
						globalMinTimestamp = bucket.minFrameTimestamp
					}
					if bucket.maxFrameTime > globalMaxTime {
						globalMaxTime = bucket.maxFrameTime
						globalMaxTimestamp = bucket.maxFrameTimestamp
					}
				}

				summary = [
					"bucketCount": buckets.count,
					"totalFrameCount": totalFrames,
					"averageFPS": avgFPS,
					"globalMinFrameTime": globalMinTime,
					"globalMinFrameTimestamp": globalMinTimestamp,
					"globalMaxFrameTime": globalMaxTime,
					"globalMaxFrameTimestamp": globalMaxTimestamp,
					"timeSpan": (buckets.last?.bucketEnd ?? 0) - (buckets.first?.bucketStart ?? 0),
				]
			}

			return .json([
				"summary": summary,
				"buckets": buckets.map { bucket in
					[
						"bucketStart": bucket.bucketStart,
						"bucketEnd": bucket.bucketEnd,
						"frameCount": bucket.frameCount,
						"averageFPS": bucket.averageFPS,
						"averageFrameTime": bucket.averageFrameTime,
						"minFrameTime": bucket.minFrameTime,
						"minFrameTimestamp": bucket.minFrameTimestamp,
						"maxFrameTime": bucket.maxFrameTime,
						"maxFrameTimestamp": bucket.maxFrameTimestamp,
					]
				},
			])
		}
	}

	// MARK: - Clear

	private static func registerClearEndpoint(with handler: RequestHandler) {
		handler.register(
			"/clear",
			description: "Clear all stored FPS data (does not disable monitoring)",
			runsOnMainThread: false
		) { _ in
			FPSMonitor.shared.clearData()

			return .json([
				"success": true,
				"message": "All FPS data cleared",
			])
		}
	}

	// MARK: - Helpers

	private static func getCurrentTime() -> TimeInterval {
		#if canImport(QuartzCore)
			return CACurrentMediaTime()
		#else
			return ProcessInfo.processInfo.systemUptime
		#endif
	}
}
