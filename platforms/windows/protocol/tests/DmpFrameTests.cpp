#include "DmpFrame.h"

#include <cassert>
#include <cstdint>
#include <string>
#include <vector>

using namespace displaymesh;

int main() {
    std::string error;

    DmpFrame source{
        DmpMessageType::Telemetry,
        0x0102,
        42,
        {'h', 'e', 'l', 'l', 'o'},
    };

    std::vector<std::uint8_t> encoded;
    assert(EncodeDmpFrame(source, encoded, error));
    const std::vector<std::uint8_t> expected{
        0x44, 0x4D, 0x50, 0x31,
        0x01, 0x30, 0x01, 0x02,
        0x00, 0x00, 0x00, 0x2A,
        0x00, 0x00, 0x00, 0x05,
        0x68, 0x65, 0x6C, 0x6C, 0x6F,
    };
    assert(encoded == expected);

    DmpFrame decoded{};
    std::size_t consumed = 0;
    assert(
        DecodeDmpFrame(
            encoded,
            decoded,
            consumed,
            error) == DmpDecodeStatus::Complete);
    assert(consumed == encoded.size());
    assert(decoded.type == source.type);
    assert(decoded.flags == source.flags);
    assert(decoded.sequence == source.sequence);
    assert(decoded.payload == source.payload);

    assert(
        DecodeDmpFrame(
            std::span<const std::uint8_t>(encoded.data(), 8),
            decoded,
            consumed,
            error) == DmpDecodeStatus::NeedMoreData);

    std::vector<std::uint8_t> oversizedHeader{
        'D','M','P','1',
        kDmpVersion,
        static_cast<std::uint8_t>(DmpMessageType::Pairing),
        0,0,
        0,0,0,1,
        0,0,0x80,0,
    };
    assert(
        DecodeDmpFrame(
            oversizedHeader,
            decoded,
            consumed,
            error) == DmpDecodeStatus::Error);

    DmpFrame invalidInput{
        DmpMessageType::Input,
        0,
        1,
        std::vector<std::uint8_t>(39, 0),
    };
    assert(!EncodeDmpFrame(invalidInput, encoded, error));

    DmpFrame invalidKeyframe{
        DmpMessageType::KeyframeRequest,
        0,
        1,
        {1},
    };
    assert(!EncodeDmpFrame(invalidKeyframe, encoded, error));

    for (const auto type : {
             DmpMessageType::Ping,
             DmpMessageType::Pong}) {
        DmpFrame validProbe{
            type,
            0,
            1,
            std::vector<std::uint8_t>(8, 0),
        };
        assert(EncodeDmpFrame(validProbe, encoded, error));

        DmpFrame invalidProbe{
            type,
            0,
            1,
            std::vector<std::uint8_t>(7, 0),
        };
        assert(!EncodeDmpFrame(invalidProbe, encoded, error));
    }

    DmpFrame encryptedInput{
        DmpMessageType::Input,
        kDmpEncryptedPayloadFlag,
        1,
        std::vector<std::uint8_t>(
            40U + kDmpAuthenticatedEncryptionOverhead,
            0),
    };
    assert(EncodeDmpFrame(encryptedInput, encoded, error));
    assert(
        DecodeDmpFrame(
            encoded,
            decoded,
            consumed,
            error) == DmpDecodeStatus::Complete);
    assert(decoded.flags == kDmpEncryptedPayloadFlag);
    assert(decoded.payload.size() == 68U);

    DmpFrame encryptedKeyframe{
        DmpMessageType::KeyframeRequest,
        kDmpEncryptedPayloadFlag,
        1,
        std::vector<std::uint8_t>(
            kDmpAuthenticatedEncryptionOverhead,
            0),
    };
    assert(EncodeDmpFrame(encryptedKeyframe, encoded, error));

    DmpFrame encryptedPing{
        DmpMessageType::Ping,
        kDmpEncryptedPayloadFlag,
        1,
        std::vector<std::uint8_t>(
            8U + kDmpAuthenticatedEncryptionOverhead,
            0),
    };
    assert(EncodeDmpFrame(encryptedPing, encoded, error));

    DmpFrame wronglySizedEncryptedInput{
        DmpMessageType::Input,
        kDmpEncryptedPayloadFlag,
        1,
        std::vector<std::uint8_t>(40, 0),
    };
    assert(!EncodeDmpFrame(
        wronglySizedEncryptedInput,
        encoded,
        error));

    DmpSequenceTracker tracker;
    assert(tracker.Accept(1, error));
    assert(tracker.Accept(2, error));
    assert(!tracker.Accept(2, error));
    tracker.Reset();
    assert(tracker.Expected() == 1);
    assert(tracker.Accept(1, error));
    assert(!tracker.Accept(3, error));

    return 0;
}
