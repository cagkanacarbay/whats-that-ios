import XCTest
@testable import WhatsThatDomain

final class VersionComparisonTests: XCTestCase {

    // MARK: - isVersionLessThan Tests

    // MARK: Basic Comparisons

    func testMajorVersionLessThan() {
        XCTAssertTrue("1.0.0".isVersionLessThan("2.0.0"))
    }

    func testMajorVersionGreaterThanReturnsFalse() {
        XCTAssertFalse("2.0.0".isVersionLessThan("1.0.0"))
    }

    func testMinorVersionLessThan() {
        XCTAssertTrue("1.1.0".isVersionLessThan("1.2.0"))
    }

    func testMinorVersionGreaterThanReturnsFalse() {
        XCTAssertFalse("1.2.0".isVersionLessThan("1.1.0"))
    }

    func testPatchVersionLessThan() {
        XCTAssertTrue("1.0.1".isVersionLessThan("1.0.2"))
    }

    func testPatchVersionGreaterThanReturnsFalse() {
        XCTAssertFalse("1.0.2".isVersionLessThan("1.0.1"))
    }

    func testEqualVersionsReturnsFalse() {
        XCTAssertFalse("1.2.3".isVersionLessThan("1.2.3"))
    }

    // MARK: Multi-digit Version Numbers (Semantic vs String Comparison)

    func testMultiDigitMinorVersionCorrectComparison() {
        // This is the critical test: 1.10.0 > 1.9.0 semantically
        XCTAssertTrue("1.2.0".isVersionLessThan("1.10.0"))
        XCTAssertTrue("1.9.0".isVersionLessThan("1.10.0"))
    }

    func testMultiDigitMajorVersionComparison() {
        XCTAssertTrue("9.0.0".isVersionLessThan("10.0.0"))
        XCTAssertTrue("1.0.0".isVersionLessThan("100.0.0"))
    }

    func testMultiDigitPatchVersionComparison() {
        XCTAssertTrue("1.0.9".isVersionLessThan("1.0.10"))
        XCTAssertTrue("1.0.99".isVersionLessThan("1.0.100"))
    }

    // MARK: Different Lengths (Padding with Zeros)

    func testTwoPartVersionEqualToThreePartWithZeroPatch() {
        XCTAssertFalse("1.0".isVersionLessThan("1.0.0"))
        XCTAssertFalse("1.0.0".isVersionLessThan("1.0"))
    }

    func testOnePartVersionComparison() {
        XCTAssertTrue("1".isVersionLessThan("2"))
        XCTAssertFalse("2".isVersionLessThan("1"))
    }

    func testMixedLengthVersions() {
        XCTAssertTrue("1.0".isVersionLessThan("1.0.1"))
        XCTAssertTrue("1".isVersionLessThan("1.0.1"))
        XCTAssertFalse("1.0.1".isVersionLessThan("1.0"))
    }

    // MARK: Empty Strings

    func testEmptyVersionLessThanNonEmpty() {
        XCTAssertTrue("".isVersionLessThan("1.0.0"))
    }

    func testNonEmptyGreaterThanEmpty() {
        XCTAssertFalse("1.0.0".isVersionLessThan(""))
    }

    func testBothEmptyReturnsFalse() {
        XCTAssertFalse("".isVersionLessThan(""))
    }

    // MARK: Malformed Input (Non-numeric Parts)

    func testMalformedVersionWithNonNumericPartsIgnored() {
        // "1.a.2" becomes [1, 2] after compactMap filtering
        // Comparing to "1.0.3" which is [1, 0, 3]
        // [1, 2, 0] vs [1, 0, 3] → 2 > 0 at index 1, so not less than
        XCTAssertFalse("1.a.2".isVersionLessThan("1.0.3"))
    }

    func testVersionWithAllNonNumericBehavesAsEmpty() {
        // "a.b.c" becomes [] after compactMap
        XCTAssertTrue("a.b.c".isVersionLessThan("1.0.0"))
    }

    // MARK: Edge Cases

    func testLeadingZerosInVersionNumbers() {
        // "01" parses as Int 1, "02" as Int 2
        XCTAssertTrue("01.02.03".isVersionLessThan("1.2.4"))
        XCTAssertFalse("01.02.03".isVersionLessThan("1.2.3")) // Equal
    }

    func testVeryLargeVersionNumbers() {
        XCTAssertTrue("999999.0.0".isVersionLessThan("1000000.0.0"))
        XCTAssertTrue("1.0.999999".isVersionLessThan("1.0.1000000"))
    }

    // MARK: - isVersionGreaterThan Tests

    func testIsVersionGreaterThanBasic() {
        XCTAssertTrue("2.0.0".isVersionGreaterThan("1.0.0"))
        XCTAssertFalse("1.0.0".isVersionGreaterThan("2.0.0"))
    }

    func testIsVersionGreaterThanEqual() {
        XCTAssertFalse("1.0.0".isVersionGreaterThan("1.0.0"))
    }

    func testIsVersionGreaterThanMultiDigit() {
        XCTAssertTrue("1.10.0".isVersionGreaterThan("1.9.0"))
        XCTAssertTrue("1.10.0".isVersionGreaterThan("1.2.0"))
    }

    // MARK: - isVersionEqualTo Tests

    func testIsVersionEqualToBasic() {
        XCTAssertTrue("1.0.0".isVersionEqualTo("1.0.0"))
        XCTAssertTrue("1.2.3".isVersionEqualTo("1.2.3"))
    }

    func testIsVersionEqualToWithPadding() {
        XCTAssertTrue("1.0".isVersionEqualTo("1.0.0"))
        XCTAssertTrue("1".isVersionEqualTo("1.0.0"))
    }

    func testIsVersionEqualToReturnsFalseWhenDifferent() {
        XCTAssertFalse("1.0.0".isVersionEqualTo("1.0.1"))
        XCTAssertFalse("1.0.0".isVersionEqualTo("2.0.0"))
    }

    func testEmptyVersionsAreEqual() {
        XCTAssertTrue("".isVersionEqualTo(""))
    }
}
