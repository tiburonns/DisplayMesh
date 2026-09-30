#include "H264AnnexBPacketizer.h"
#include "DmpFrame.h"

#include <cassert>
#include <cstdint>
#include <string>
#include <vector>

using displaymesh::DmpDecodeStatus;
using displaymesh::DmpFrame;
using displaymesh::DmpMessageType;
using displaymesh::DmpSequenceTracker;
using displaymesh::DecodeDmpFrame;
using displaymesh::EncodeDmpFrame;
using displaymesh::media::H264AnnexBPacketizer;
using displaymesh::media::H264PacketizeReport;

int main() {
    H264AnnexBPacketizer packetizer;
    H264PacketizeReport report;
    std::vector<std::uint8_t> videoPayload;
    std::string error;

    const std::vector<std::uint8_t> parameterSets{
        0x00, 0x00, 0x00, 0x01,
        0x67, 0x64, 0x00, 0x1F,
        0x00, 0x00, 0x01,
        0x68, 0xEE, 0x3C, 0x80,
    };

    assert(packetizer.Packetize(
        parameterSets,
        1,
        16'667,
        videoPayload,
        report,
        error));

    const std::vector<std::uint8_t> idr{
        0x00, 0x00, 0x01,
        0x65, 0x88, 0x84,
    };

    assert(packetizer.Packetize(
        idr,
        2,
        16'667,
        videoPayload,
        report,
        error));

    assert(report.keyframe);
    assert(videoPayload.size() > 16);
    assert(videoPayload[0] == 0x01);
    assert(videoPayload[1] == 0x01);
    assert(videoPayload[2] == 0x00);
    assert(videoPayload[3] == 0x00);

    DmpFrame source{
        DmpMessageType::Video,
        0,
        1,
        videoPayload,
    };

    std::vector<std::uint8_t> encoded;
    assert(EncodeDmpFrame(
        source,
        encoded,
        error));

    assert(encoded.size() ==
        displaymesh::kDmpHeaderSize +
            videoPayload.size());

    assert(encoded[0] == 0x44);
    assert(encoded[1] == 0x4D);
    assert(encoded[2] == 0x50);
    assert(encoded[3] == 0x31);
    assert(encoded[4] ==
        displaymesh::kDmpVersion);
    assert(encoded[5] ==
        static_cast<std::uint8_t>(
            DmpMessageType::Video));
    assert(encoded[6] == 0);
    assert(encoded[7] == 0);
    assert(encoded[8] == 0);
    assert(encoded[9] == 0);
    assert(encoded[10] == 0);
    assert(encoded[11] == 1);

    const auto payloadLength =
        static_cast<std::uint32_t>(
            videoPayload.size());

    assert(encoded[12] ==
        static_cast<std::uint8_t>(
            payloadLength >> 24));
    assert(encoded[13] ==
        static_cast<std::uint8_t>(
            payloadLength >> 16));
    assert(encoded[14] ==
        static_cast<std::uint8_t>(
            payloadLength >> 8));
    assert(encoded[15] ==
        static_cast<std::uint8_t>(
            payloadLength));

    DmpFrame decoded{};
    std::size_t consumed = 0;

    assert(
        DecodeDmpFrame(
            encoded,
            decoded,
            consumed,
            error) ==
        DmpDecodeStatus::Complete);

    assert(consumed == encoded.size());
    assert(decoded.type ==
        DmpMessageType::Video);
    assert(decoded.sequence == 1);
    assert(decoded.payload ==
        videoPayload);

    DmpSequenceTracker tracker;
    assert(tracker.Accept(1, error));
    assert(!tracker.Accept(1, error));

    return 0;
}
