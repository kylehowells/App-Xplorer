import Foundation
import Testing
@testable import AppXplorerServer

// MARK: - SafeAddressLookup Tests

// MARK: - Address Parsing Tests

@Test func testParseAddressWithPrefix() async throws {
	let address = SafeAddressLookup.parseAddress("0x12345678")
	#expect(address == 0x12345678)
}

@Test func testParseAddressWithUppercasePrefix() async throws {
	let address = SafeAddressLookup.parseAddress("0X12345678")
	#expect(address == 0x12345678)
}

@Test func testParseAddressWithoutPrefix() async throws {
	let address = SafeAddressLookup.parseAddress("12345678")
	#expect(address == 0x12345678)
}

@Test func testParseAddressWithLargeValue() async throws {
	let address = SafeAddressLookup.parseAddress("0xFFFFFFFFFFFFFFFF")
	#expect(address == UInt.max)
}

@Test func testParseAddressZero() async throws {
	let address = SafeAddressLookup.parseAddress("0x0")
	#expect(address == 0)
}

@Test func testParseAddressInvalidHex() async throws {
	let address = SafeAddressLookup.parseAddress("0xGHIJKL")
	#expect(address == nil)
}

@Test func testParseAddressEmptyString() async throws {
	let address = SafeAddressLookup.parseAddress("")
	#expect(address == nil)
}

@Test func testParseAddressJustPrefix() async throws {
	let address = SafeAddressLookup.parseAddress("0x")
	#expect(address == nil)
}

@Test func testParseAddressMixedCase() async throws {
	let address = SafeAddressLookup.parseAddress("0xAbCdEf12")
	#expect(address == 0xABCDEF12)
}

// MARK: - Address Formatting Tests

@Test func testAddressOfObject() async throws {
	let object = NSObject()
	let address = SafeAddressLookup.address(of: object)
	#expect(address != 0)
	#expect(address % 8 == 0) // Should be 8-byte aligned
}

@Test func testAddressStringOfObject() async throws {
	let object = NSObject()
	let addressString = SafeAddressLookup.addressString(of: object)
	#expect(addressString.hasPrefix("0x"))
	#expect(addressString.count > 2) // More than just "0x"
}

@Test func testAddressRoundTrip() async throws {
	let object = NSObject()
	let address = SafeAddressLookup.address(of: object)
	let addressString = SafeAddressLookup.addressString(of: object)
	let parsedAddress = SafeAddressLookup.parseAddress(addressString)

	#expect(parsedAddress == address)
}

@Test func testAddressStringFormat() async throws {
	let object = NSObject()
	let addressString = SafeAddressLookup.addressString(of: object)

	// Should start with 0x
	#expect(addressString.hasPrefix("0x"))

	// Should be parseable back
	let parsed = SafeAddressLookup.parseAddress(addressString)
	#expect(parsed != nil)
}

// MARK: - Object Lookup Tests

@Test func testLookupValidNSObject() async throws {
	let original = NSObject()
	let address = SafeAddressLookup.address(of: original)

	let retrieved = SafeAddressLookup.object(at: address)
	#expect(retrieved != nil)
	#expect(retrieved === original)
}

@Test func testLookupWithTypeChecking() async throws {
	let original = NSObject()
	let address = SafeAddressLookup.address(of: original)

	// Should succeed with correct type
	let asNSObject: NSObject? = SafeAddressLookup.object(at: address, as: NSObject.self)
	#expect(asNSObject != nil)
	#expect(asNSObject === original)
}

@Test func testLookupWithWrongType() async throws {
	let original = NSObject()
	let address = SafeAddressLookup.address(of: original)

	// NSObject is not an NSString, so this should fail
	let asString: NSString? = SafeAddressLookup.object(at: address, as: NSString.self)
	#expect(asString == nil)
}

@Test func testLookupNSMutableString() async throws {
	let original = NSMutableString(string: "Hello, World!")
	let address = SafeAddressLookup.address(of: original)

	let retrieved: NSMutableString? = SafeAddressLookup.object(at: address, as: NSMutableString.self)
	#expect(retrieved != nil)
	#expect(retrieved === original)
}

@Test func testLookupNSMutableArray() async throws {
	let original = NSMutableArray(array: [1, 2, 3])
	let address = SafeAddressLookup.address(of: original)

	let retrieved: NSMutableArray? = SafeAddressLookup.object(at: address, as: NSMutableArray.self)
	#expect(retrieved != nil)
	#expect(retrieved === original)
}

@Test func testLookupNSMutableDictionary() async throws {
	let original = NSMutableDictionary(dictionary: ["key": "value"])
	let address = SafeAddressLookup.address(of: original)

	let retrieved: NSMutableDictionary? = SafeAddressLookup.object(at: address, as: NSMutableDictionary.self)
	#expect(retrieved != nil)
	#expect(retrieved === original)
}

// MARK: - Safe Invalid Address Tests

// Note: We only test addresses that are guaranteed safe to check
// (null, unaligned) because checking arbitrary addresses like
// 0xDEADBEEF could crash even with validation due to memory access

@Test func testLookupNullAddress() async throws {
	let retrieved = SafeAddressLookup.object(at: 0)
	#expect(retrieved == nil)
}

@Test func testLookupUnalignedAddresses() async throws {
	// Unaligned addresses (not 8-byte aligned) should fail without memory access
	#expect(SafeAddressLookup.object(at: 0x1) == nil)
	#expect(SafeAddressLookup.object(at: 0x3) == nil)
	#expect(SafeAddressLookup.object(at: 0x5) == nil)
	#expect(SafeAddressLookup.object(at: 0x7) == nil)
}

// MARK: - Subclass Type Checking Tests

@Test func testLookupMutableStringAsBaseClass() async throws {
	// NSMutableString is a subclass of NSString
	let original = NSMutableString(string: "Mutable")
	let address = SafeAddressLookup.address(of: original)

	// Should succeed when asking for base class NSString
	let asNSString: NSString? = SafeAddressLookup.object(at: address, as: NSString.self)
	#expect(asNSString != nil)
	#expect(asNSString === original)
}

@Test func testLookupMutableStringAsExactClass() async throws {
	let original = NSMutableString(string: "Mutable")
	let address = SafeAddressLookup.address(of: original)

	// Should succeed when asking for exact class
	let asMutableString: NSMutableString? = SafeAddressLookup.object(at: address, as: NSMutableString.self)
	#expect(asMutableString != nil)
	#expect(asMutableString === original)
}

@Test func testLookupMutableArrayAsBaseClass() async throws {
	// NSMutableArray is a subclass of NSArray
	let original = NSMutableArray(array: [1, 2, 3])
	let address = SafeAddressLookup.address(of: original)

	// Should succeed when asking for base class NSArray
	let asNSArray: NSArray? = SafeAddressLookup.object(at: address, as: NSArray.self)
	#expect(asNSArray != nil)
	#expect(asNSArray === original)
}

// MARK: - Multiple Object Tests

@Test func testMultipleObjectsHaveDifferentAddresses() async throws {
	let obj1 = NSObject()
	let obj2 = NSObject()
	let obj3 = NSObject()

	let addr1 = SafeAddressLookup.address(of: obj1)
	let addr2 = SafeAddressLookup.address(of: obj2)
	let addr3 = SafeAddressLookup.address(of: obj3)

	#expect(addr1 != addr2)
	#expect(addr2 != addr3)
	#expect(addr1 != addr3)
}

@Test func testSameObjectHasSameAddress() async throws {
	let obj = NSObject()

	let addr1 = SafeAddressLookup.address(of: obj)
	let addr2 = SafeAddressLookup.address(of: obj)

	#expect(addr1 == addr2)
}

// MARK: - TestClass

private class TestClass: NSObject {
	var value: Int = 42
}

@Test func testLookupCustomClass() async throws {
	let original = TestClass()
	original.value = 123
	let address = SafeAddressLookup.address(of: original)

	let retrieved: TestClass? = SafeAddressLookup.object(at: address, as: TestClass.self)
	#expect(retrieved != nil)
	#expect(retrieved === original)
	#expect(retrieved?.value == 123)
}

@Test func testLookupCustomClassAsNSObject() async throws {
	let original = TestClass()
	let address = SafeAddressLookup.address(of: original)

	// Should succeed when asking for base class NSObject
	let asNSObject: NSObject? = SafeAddressLookup.object(at: address, as: NSObject.self)
	#expect(asNSObject != nil)
	#expect(asNSObject === original)
}

@Test func testLookupNSObjectAsCustomClass() async throws {
	let original = NSObject()
	let address = SafeAddressLookup.address(of: original)

	// Should fail - NSObject is not a TestClass
	let asTestClass: TestClass? = SafeAddressLookup.object(at: address, as: TestClass.self)
	#expect(asTestClass == nil)
}
