import CoreGraphics
import XCTest
@testable import DisplayMeshMacMediaHarness

final class ManagedVirtualDisplayProcessTests: XCTestCase {
    func testReceiverNativeSpecificationAcceptsPhoneAndTabletGeometry() {
        XCTAssertTrue(
            ManagedVirtualDisplaySpecification(
                width: 1179,
                height: 2556,
                refreshRate: 60,
                hiDPI: true
            ).isValid
        )
        XCTAssertTrue(
            ManagedVirtualDisplaySpecification(
                width: 2732,
                height: 2048,
                refreshRate: 120,
                hiDPI: true
            ).isValid
        )
    }

    func testSpecificationRejectsUnsafeGeometryAndRefresh() {
        XCTAssertFalse(
            ManagedVirtualDisplaySpecification(
                width: 320,
                height: 240,
                refreshRate: 60,
                hiDPI: false
            ).isValid
        )
        XCTAssertFalse(
            ManagedVirtualDisplaySpecification(
                width: 1920,
                height: 1080,
                refreshRate: 0,
                hiDPI: false
            ).isValid
        )
    }

    func testReadyFileParserAcceptsOnlyNonzeroDisplayIDs() {
        XCTAssertEqual(
            VirtualDisplayReadyFile.parse(Data("42\n".utf8)),
            CGDirectDisplayID(42)
        )
        XCTAssertNil(
            VirtualDisplayReadyFile.parse(Data("0\n".utf8))
        )
        XCTAssertNil(
            VirtualDisplayReadyFile.parse(Data("not-a-display\n".utf8))
        )
    }
}
