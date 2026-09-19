import XCTest
@testable import DisplayMeshReceiver

final class DMPVideoPacketTests: XCTestCase {
    func testVideoPacketRoundTrip() throws {
        let packet = DMPVideoPacket(
            codec: .h264,
            flags: [.keyframe],
            presentationTimeMicroseconds: 1_234_567,
            durationMicroseconds: 16_667,
            bitstream: Data([0, 0, 0, 1, 0x65, 1, 2, 3])
        )

        XCTAssertEqual(
            try DMPVideoPacket.decode(packet.encoded()),
            packet
        )
    }

    func testRejectsUnknownCodec() {
        var payload = Data(repeating: 0, count: DMPVideoPacket.headerSize + 1)
        payload[0] = 0xff
        payload[DMPVideoPacket.headerSize] = 1

        XCTAssertThrowsError(try DMPVideoPacket.decode(payload)) { error in
            XCTAssertEqual(
                error as? DMPVideoPacketError,
                .unsupportedCodec(0xff)
            )
        }
    }

    func testRejectsEmptyBitstream() {
        var payload = Data(repeating: 0, count: DMPVideoPacket.headerSize)
        payload[0] = DMPVideoCodec.h264.rawValue

        XCTAssertThrowsError(try DMPVideoPacket.decode(payload)) { error in
            XCTAssertEqual(
                error as? DMPVideoPacketError,
                .emptyBitstream
            )
        }
    }
}
