import XCTest
@testable import DisplayMeshReceiver

final class DMPFrameTests: XCTestCase {
    func testFrameRoundTrip() throws {
        let frame = DMPFrame(
            type: .telemetry,
            flags: 0x1020,
            sequence: 42,
            payload: Data("hello".utf8)
        )

        var decoder = DMPFrameDecoder()
        decoder.append(try frame.encoded())

        XCTAssertEqual(try decoder.nextFrame(), frame)
        XCTAssertNil(try decoder.nextFrame())
    }

    func testDecoderWaitsForFragmentedPayload() throws {
        let frame = DMPFrame(
            type: .hello,
            flags: 0,
            sequence: 1,
            payload: Data([1, 2, 3, 4, 5])
        )
        let encoded = try frame.encoded()

        var decoder = DMPFrameDecoder()
        decoder.append(encoded.prefix(10))
        XCTAssertNil(try decoder.nextFrame())

        decoder.append(encoded.dropFirst(10))
        XCTAssertEqual(try decoder.nextFrame(), frame)
    }

    func testPairingRequiresSixDigitsAndMatchingProtocol() {
        XCTAssertTrue(
            PairingRequest(
                peerName: "Mac",
                verificationCode: "123456",
                protocolVersion: Int(DMPFrame.version)
            ).isValid
        )

        XCTAssertFalse(
            PairingRequest(
                peerName: "Mac",
                verificationCode: "12345",
                protocolVersion: Int(DMPFrame.version)
            ).isValid
        )
    }
}
