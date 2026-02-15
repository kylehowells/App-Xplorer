#if canImport(UIKit)
	import UIKit
#endif
#if canImport(QuartzCore)
	import QuartzCore
#endif
import Foundation

// MARK: - FPSMonitor

/// FPS Monitor using CADisplayLink
/// Stores full frame times for last 5 minutes, then aggregates to 1-second buckets
public final class FPSMonitor: @unchecked Sendable {

	public static let shared = FPSMonitor()

	// MARK: - Configuration

	/// How long to keep full frame time data (seconds)
	private let recentDataRetention: TimeInterval = 5 * 60 // 5 minutes

	/// Bucket duration for historical aggregated data
	private let bucketDuration: TimeInterval = 1.0 // 1 second

	// MARK: - Data Structures

	/// A single frame timing record
	public struct FrameTime: Codable, Sendable {
		public let timestamp: TimeInterval
		public let duration: TimeInterval // Frame duration in seconds

		public var fps: Double {
			return self.duration > 0 ? 1.0 / self.duration : 0
		}
	}

	/// Aggregated bucket for historical data (1-second intervals)
	public struct HistoryBucket: Codable, Sendable {
		public let bucketStart: TimeInterval
		public let bucketEnd: TimeInterval
		public let frameCount: Int
		public let averageFrameTime: TimeInterval
		public let minFrameTime: TimeInterval
		public let minFrameTimestamp: TimeInterval
		public let maxFrameTime: TimeInterval
		public let maxFrameTimestamp: TimeInterval

		public var averageFPS: Double {
			return self.averageFrameTime > 0 ? 1.0 / self.averageFrameTime : 0
		}
	}

	/// Status information
	public struct Status: Codable, Sendable {
		public let enabled: Bool
		public let currentFPS: Double
		public let recentFrameCount: Int
		public let historyBucketCount: Int
		public let oldestRecentTimestamp: TimeInterval?
		public let oldestHistoryTimestamp: TimeInterval?
		public let memoryEstimateBytes: Int
	}

	// MARK: - State

	private let lock = NSLock()

	#if canImport(UIKit)
		private var displayLink: CADisplayLink?
	#endif

	private var lastFrameTimestamp: CFTimeInterval = 0
	private var _isEnabled: Bool = false

	/// Recent frame times (last 5 minutes) - full resolution
	private var recentFrames: [FrameTime] = []

	/// Historical buckets (older than 5 minutes) - 1-second aggregates
	private var historyBuckets: [HistoryBucket] = []

	/// Frames being accumulated for the current bucket
	private var currentBucketFrames: [FrameTime] = []
	private var currentBucketStart: TimeInterval = 0

	// MARK: - Public API

	public var isEnabled: Bool {
		self.lock.lock()
		defer { lock.unlock() }
		return self._isEnabled
	}

	private init() { }

	/// Enable FPS monitoring
	public func enable() {
		#if canImport(UIKit)
			DispatchQueue.main.async { [weak self] in
				self?.enableOnMainThread()
			}
		#endif
	}

	/// Disable FPS monitoring
	public func disable() {
		#if canImport(UIKit)
			DispatchQueue.main.async { [weak self] in
				self?.disableOnMainThread()
			}
		#endif
	}

	#if canImport(UIKit)
		private func enableOnMainThread() {
			self.lock.lock()
			defer { lock.unlock() }

			guard !self._isEnabled else { return }

			self.displayLink = CADisplayLink(target: self, selector: #selector(self.displayLinkFired(_:)))
			self.displayLink?.add(to: .main, forMode: .common)
			self.lastFrameTimestamp = CACurrentMediaTime()
			self._isEnabled = true
		}

		private func disableOnMainThread() {
			self.lock.lock()
			defer { lock.unlock() }

			self.displayLink?.invalidate()
			self.displayLink = nil
			self._isEnabled = false
		}

		@objc private func displayLinkFired(_ link: CADisplayLink) {
			let now = CACurrentMediaTime()
			let frameDuration = now - self.lastFrameTimestamp
			self.lastFrameTimestamp = now

			// Skip first frame (no valid duration)
			guard frameDuration > 0, frameDuration < 1.0 else { return }

			let frame = FrameTime(timestamp: now, duration: frameDuration)

			self.lock.lock()
			self.recentFrames.append(frame)
			self.lock.unlock()

			// Periodically compact old data (every ~1 second worth of frames)
			if self.recentFrames.count % 60 == 0 {
				self.compactOldData()
			}
		}
	#endif

	/// Compact data older than retention period into buckets
	private func compactOldData() {
		self.lock.lock()
		defer { lock.unlock() }

		let now = self.currentTime()
		let cutoff = now - self.recentDataRetention

		// Find frames older than cutoff
		var framesToAggregate: [FrameTime] = []
		var framesToKeep: [FrameTime] = []

		for frame in self.recentFrames {
			if frame.timestamp < cutoff {
				framesToAggregate.append(frame)
			}
			else {
				framesToKeep.append(frame)
			}
		}

		self.recentFrames = framesToKeep

		// Add old frames to current bucket processing
		self.currentBucketFrames.append(contentsOf: framesToAggregate)

		// Process complete buckets
		if self.currentBucketFrames.isEmpty { return }

		// Sort by timestamp
		self.currentBucketFrames.sort { $0.timestamp < $1.timestamp }

		// Initialize bucket start if needed
		if self.currentBucketStart == 0, !self.currentBucketFrames.isEmpty {
			self.currentBucketStart = floor(self.currentBucketFrames[0].timestamp)
		}

		// Process frames into buckets
		while !self.currentBucketFrames.isEmpty {
			let bucketEnd = self.currentBucketStart + self.bucketDuration

			// Get frames in this bucket
			var bucketFrames: [FrameTime] = []
			var remainingFrames: [FrameTime] = []

			for frame in self.currentBucketFrames {
				if frame.timestamp < bucketEnd {
					bucketFrames.append(frame)
				}
				else {
					remainingFrames.append(frame)
				}
			}

			// If we have frames for this bucket and it's complete (past cutoff)
			if !bucketFrames.isEmpty, bucketEnd < cutoff {
				let bucket = self.createBucket(from: bucketFrames, start: self.currentBucketStart, end: bucketEnd)
				self.historyBuckets.append(bucket)
				self.currentBucketFrames = remainingFrames
				self.currentBucketStart = bucketEnd
			}
			else {
				// Bucket not complete yet
				break
			}
		}
	}

	private func createBucket(from frames: [FrameTime], start: TimeInterval, end: TimeInterval) -> HistoryBucket {
		let totalDuration = frames.reduce(0.0) { $0 + $1.duration }
		let avgDuration = totalDuration / Double(frames.count)

		var minFrame = frames[0]
		var maxFrame = frames[0]

		for frame in frames {
			if frame.duration < minFrame.duration {
				minFrame = frame
			}
			if frame.duration > maxFrame.duration {
				maxFrame = frame
			}
		}

		return HistoryBucket(
			bucketStart: start,
			bucketEnd: end,
			frameCount: frames.count,
			averageFrameTime: avgDuration,
			minFrameTime: minFrame.duration,
			minFrameTimestamp: minFrame.timestamp,
			maxFrameTime: maxFrame.duration,
			maxFrameTimestamp: maxFrame.timestamp
		)
	}

	// MARK: - Query API

	/// Get current status
	public func getStatus() -> Status {
		self.lock.lock()
		defer { lock.unlock() }

		// Calculate current FPS from last few frames
		let currentFPS: Double
		if self.recentFrames.count >= 10 {
			let lastFrames = self.recentFrames.suffix(10)
			let avgDuration = lastFrames.reduce(0.0) { $0 + $1.duration } / Double(lastFrames.count)
			currentFPS = avgDuration > 0 ? 1.0 / avgDuration : 0
		}
		else if let last = recentFrames.last {
			currentFPS = last.fps
		}
		else {
			currentFPS = 0
		}

		// Memory estimate: ~16 bytes per FrameTime, ~64 bytes per bucket
		let memoryEstimate = (recentFrames.count * 16) + (self.historyBuckets.count * 64) + (self.currentBucketFrames.count * 16)

		return Status(
			enabled: self._isEnabled,
			currentFPS: currentFPS,
			recentFrameCount: self.recentFrames.count,
			historyBucketCount: self.historyBuckets.count,
			oldestRecentTimestamp: self.recentFrames.first?.timestamp,
			oldestHistoryTimestamp: self.historyBuckets.first?.bucketStart,
			memoryEstimateBytes: memoryEstimate
		)
	}

	/// Get recent frame data (last 5 minutes, full resolution)
	/// - Parameters:
	///   - count: Maximum number of frames to return (newest first by default)
	///   - start: Start timestamp filter
	///   - end: End timestamp filter
	///   - ascending: Sort order (false = newest first)
	public func getRecentFrames(count: Int? = nil, start: TimeInterval? = nil, end: TimeInterval? = nil, ascending: Bool = false) -> [FrameTime] {
		self.lock.lock()
		defer { lock.unlock() }

		var frames = self.recentFrames

		// Apply time filters
		if let startTime = start {
			frames = frames.filter { $0.timestamp >= startTime }
		}
		if let endTime = end {
			frames = frames.filter { $0.timestamp <= endTime }
		}

		// Sort
		if ascending {
			frames.sort { $0.timestamp < $1.timestamp }
		}
		else {
			frames.sort { $0.timestamp > $1.timestamp }
		}

		// Apply count limit
		if let maxCount = count, frames.count > maxCount {
			frames = Array(frames.prefix(maxCount))
		}

		return frames
	}

	/// Get historical bucket data (older than 5 minutes, 1-second aggregates)
	/// - Parameters:
	///   - count: Maximum number of buckets to return
	///   - start: Start timestamp filter
	///   - end: End timestamp filter
	///   - ascending: Sort order (false = newest first)
	public func getHistoryBuckets(count: Int? = nil, start: TimeInterval? = nil, end: TimeInterval? = nil, ascending: Bool = false) -> [HistoryBucket] {
		self.lock.lock()
		defer { lock.unlock() }

		var buckets = self.historyBuckets

		// Apply time filters
		if let startTime = start {
			buckets = buckets.filter { $0.bucketEnd >= startTime }
		}
		if let endTime = end {
			buckets = buckets.filter { $0.bucketStart <= endTime }
		}

		// Sort
		if ascending {
			buckets.sort { $0.bucketStart < $1.bucketStart }
		}
		else {
			buckets.sort { $0.bucketStart > $1.bucketStart }
		}

		// Apply count limit
		if let maxCount = count, buckets.count > maxCount {
			buckets = Array(buckets.prefix(maxCount))
		}

		return buckets
	}

	/// Clear all stored data
	public func clearData() {
		self.lock.lock()
		defer { lock.unlock() }

		self.recentFrames.removeAll()
		self.historyBuckets.removeAll()
		self.currentBucketFrames.removeAll()
		self.currentBucketStart = 0
	}

	// MARK: - Helpers

	private func currentTime() -> TimeInterval {
		#if canImport(QuartzCore)
			return CACurrentMediaTime()
		#else
			return ProcessInfo.processInfo.systemUptime
		#endif
	}
}
