import Foundation
import ObjectiveC

#if canImport(UIKit)
	import UIKit
#endif

// MARK: - SafeAddressLookup

/// Utility for safely looking up Objective-C objects by memory address.
///
/// This provides a reusable, safe way to convert a memory address (e.g., from a debug API)
/// back to an object reference. It validates the address using ObjC runtime checks
/// before attempting to use it, preventing crashes from invalid or stale addresses.
///
/// ## Usage
/// ```swift
/// // Look up any NSObject
/// if let object = SafeAddressLookup.object(at: address) {
///     print("Found: \(object)")
/// }
///
/// // Look up with type checking
/// if let view: UIView = SafeAddressLookup.object(at: address, as: UIView.self) {
///     print("Found view: \(view)")
/// }
/// ```
///
/// ## Safety
/// This utility performs several validation steps:
/// 1. Checks pointer alignment (must be 8-byte aligned on 64-bit)
/// 2. Reads the isa pointer from the potential object
/// 3. Validates the isa points to a registered ObjC class
/// 4. Optionally validates the class hierarchy matches the expected type
///
/// **Note**: While this is much safer than blind pointer casting, it cannot guarantee
/// 100% safety. If memory has been reused by a different valid ObjC object, this will
/// succeed but return the wrong object. For maximum safety in UI contexts, prefer
/// validating addresses against a known collection of live objects.
public enum SafeAddressLookup {
	// MARK: - Public API

	/// Attempt to retrieve an NSObject at the given memory address.
	/// Returns nil if the address is invalid or doesn't point to a valid NSObject.
	///
	/// - Parameter address: The memory address as a UInt (e.g., parsed from "0x12345678")
	/// - Returns: The object if valid, nil otherwise
	public static func object(at address: UInt) -> NSObject? {
		return self.object(at: address, as: NSObject.self)
	}

	/// Attempt to retrieve an object of a specific type at the given memory address.
	/// Returns nil if the address is invalid or the object isn't of the expected type.
	///
	/// - Parameters:
	///   - address: The memory address as a UInt
	///   - type: The expected type (must be a class type)
	/// - Returns: The object cast to the expected type if valid, nil otherwise
	public static func object<T: AnyObject>(at address: UInt, as type: T.Type) -> T? {
		// Step 1: Basic validation
		guard address != 0 else { return nil }

		// Step 2: Check pointer alignment (8-byte on 64-bit systems)
		guard address % 8 == 0 else { return nil }

		// Step 3: Create pointer
		guard let pointer = UnsafeRawPointer(bitPattern: address) else { return nil }

		// Step 4: Validate using ObjC runtime
		guard self.isValidObjCObject(at: pointer) else { return nil }

		// Step 5: Get the object's class and validate type hierarchy
		let unmanaged = Unmanaged<AnyObject>.fromOpaque(pointer)
		let object = unmanaged.takeUnretainedValue()

		// Step 6: Verify the class matches the expected type
		guard object is T else { return nil }

		return object as? T
	}

	/// Parse a hex address string (with or without "0x" prefix) to UInt.
	///
	/// - Parameter string: Address string like "0x12345678" or "12345678"
	/// - Returns: The parsed address, or nil if invalid
	public static func parseAddress(_ string: String) -> UInt? {
		var hex = string
		if hex.hasPrefix("0x") || hex.hasPrefix("0X") {
			hex = String(hex.dropFirst(2))
		}
		return UInt(hex, radix: 16)
	}

	#if canImport(UIKit)
		/// Convenience method to look up a UIResponder at an address.
		/// This is a common use case for debugging UI hierarchies.
		///
		/// - Parameter address: The memory address
		/// - Returns: The UIResponder if valid, nil otherwise
		public static func responder(at address: UInt) -> UIResponder? {
			return self.object(at: address, as: UIResponder.self)
		}

		/// Convenience method to look up a UIView at an address.
		///
		/// - Parameter address: The memory address
		/// - Returns: The UIView if valid, nil otherwise
		public static func view(at address: UInt) -> UIView? {
			return self.object(at: address, as: UIView.self)
		}

		/// Convenience method to look up a UIViewController at an address.
		///
		/// - Parameter address: The memory address
		/// - Returns: The UIViewController if valid, nil otherwise
		public static func viewController(at address: UInt) -> UIViewController? {
			return self.object(at: address, as: UIViewController.self)
		}
	#endif

	// MARK: - Private Implementation

	/// Validates that a pointer points to a valid Objective-C object.
	///
	/// This performs the following checks:
	/// 1. Reads the isa pointer (first 8 bytes of an ObjC object)
	/// 2. Masks off tagged pointer bits to get the actual class pointer
	/// 3. Verifies the class is registered with the ObjC runtime
	private static func isValidObjCObject(at pointer: UnsafeRawPointer) -> Bool {
		// Read the potential isa pointer (first word of an ObjC object)
		// On 64-bit systems, the isa may be a tagged pointer or non-pointer isa
		let isaValue = pointer.load(as: UInt.self)

		// Handle non-pointer isa (used by modern ObjC runtime for optimization)
		// The actual class pointer is obtained by masking with ISA_MASK
		// ISA_MASK for arm64: 0x0000000ffffffff8
		// ISA_MASK for x86_64: 0x00007ffffffffff8
		#if arch(arm64)
			let isaMask: UInt = 0x0000000FFFFFFFF8
		#else
			let isaMask: UInt = 0x00007FFFFFFFFFF8
		#endif

		let classPointer = isaValue & isaMask

		// If the masked value is 0, this isn't a valid object
		guard classPointer != 0 else { return false }

		// Convert to AnyClass and validate
		guard let pointer = UnsafeRawPointer(bitPattern: classPointer) else { return false }

		let potentialClass: AnyClass? = unsafeBitCast(pointer, to: AnyClass?.self)

		guard let cls = potentialClass else { return false }

		// Verify this class is registered with the ObjC runtime
		let className = NSStringFromClass(cls)

		// objc_lookUpClass returns the class if registered, nil otherwise
		guard objc_lookUpClass(className) != nil else { return false }

		return true
	}
}

// MARK: - Convenience Extensions

public extension SafeAddressLookup {
	/// Format an object's address as a hex string (matching the format used in debug output)
	///
	/// - Parameter object: Any object
	/// - Returns: Hex string like "0x12345678"
	static func addressString(of object: AnyObject) -> String {
		let address = UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque())
		return String(format: "0x%lx", address)
	}

	/// Get the raw address of an object as a UInt
	///
	/// - Parameter object: Any object
	/// - Returns: The memory address as UInt
	static func address(of object: AnyObject) -> UInt {
		return UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque())
	}
}
