#include "H264AnnexBPacketizer.h"

#include <cassert>
#include <cstdint>
#include <string>
#include <vector>

using displaymesh::media::
    H264AnnexBPacketizer;
using displaymesh::media::
    H264PacketizeReport;

namespace {

std::vector<std::uint8_t> Payload(
    std::initializer_list<std::uint8_t> bytes) {
    return std::vector<std::uint8_t>(
        bytes);
}

void TestGoldenNonKeyframePacket() {
    H264AnnexBPacketizer packetizer;
    H264PacketizeReport report;
    std::vector<std::uint8_t> output;
    std::string error;

    const auto accessUnit = Payload({
        0x00, 0x00, 0x01,
        0x41, 0xAA, 0xBB,
    });

    assert(packetizer.Packetize(
        accessUnit,
        42,
        16'667,
        output,
        report,
        error));

    const auto expected = Payload({
        0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x2A,
        0x00, 0x00, 0x41, 0x1B,
        0x00, 0x00, 0x00, 0x01,
        0x41, 0xAA, 0xBB,
    });

    assert(output == expected);
    assert(!report.keyframe);
    assert(!report.insertedSps);
    assert(!report.insertedPps);
    assert(report.nalUnitCount == 1);
}

void TestCachedParameterSetsRepairIdr() {
    H264AnnexBPacketizer packetizer;
    H264PacketizeReport report;
    std::vector<std::uint8_t> output;
    std::string error;

    const auto parameterSets = Payload({
        0x00, 0x00, 0x00, 0x01,
        0x67, 0x64, 0x00, 0x1F,
        0x00, 0x00, 0x01,
        0x68, 0xEE, 0x3C, 0x80,
    });

    assert(packetizer.Packetize(
        parameterSets,
        1,
        16'667,
        output,
        report,
        error));
    assert(!report.keyframe);

    const auto idr = Payload({
        0x00, 0x00, 0x01,
        0x65, 0x88, 0x84,
    });

    assert(packetizer.Packetize(
        idr,
        2,
        16'667,
        output,
        report,
        error));

    assert(report.keyframe);
    assert(report.insertedSps);
    assert(report.insertedPps);

    const std::vector<std::uint8_t>
        expectedBitstream{
            0x00, 0x00, 0x00, 0x01,
            0x67, 0x64, 0x00, 0x1F,
            0x00, 0x00, 0x00, 0x01,
            0x68, 0xEE, 0x3C, 0x80,
            0x00, 0x00, 0x00, 0x01,
            0x65, 0x88, 0x84,
        };

    assert(output.size() ==
        16 + expectedBitstream.size());
    assert(output[0] == 0x01);
    assert(output[1] == 0x01);

    assert(std::vector<std::uint8_t>(
        output.begin() + 16,
        output.end()) ==
        expectedBitstream);
}

void TestCurrentParameterSetsAreOrderedBeforeIdr() {
    H264AnnexBPacketizer packetizer;
    H264PacketizeReport report;
    std::vector<std::uint8_t> output;
    std::string error;

    const auto accessUnit = Payload({
        0x00, 0x00, 0x01,
        0x68, 0x01,
        0x00, 0x00, 0x00, 0x01,
        0x65, 0x02,
        0x00, 0x00, 0x01,
        0x67, 0x03,
    });

    assert(packetizer.Packetize(
        accessUnit,
        3,
        8'333,
        output,
        report,
        error));

    assert(report.keyframe);
    assert(!report.insertedSps);
    assert(!report.insertedPps);

    const auto expectedBitstream = Payload({
        0x00, 0x00, 0x00, 0x01,
        0x67, 0x03,
        0x00, 0x00, 0x00, 0x01,
        0x68, 0x01,
        0x00, 0x00, 0x00, 0x01,
        0x65, 0x02,
    });

    assert(std::vector<std::uint8_t>(
        output.begin() + 16,
        output.end()) ==
        expectedBitstream);
}

void TestIdrWithoutRecoveryStateFails() {
    H264AnnexBPacketizer packetizer;
    H264PacketizeReport report;
    std::vector<std::uint8_t> output;
    std::string error;

    const auto idr = Payload({
        0x00, 0x00, 0x01,
        0x65, 0x10,
    });

    assert(!packetizer.Packetize(
        idr,
        0,
        16'667,
        output,
        report,
        error));

    assert(output.empty());
    assert(!error.empty());
}

void TestMalformedPrefixIsRejected() {
    H264AnnexBPacketizer packetizer;
    H264PacketizeReport report;
    std::vector<std::uint8_t> output;
    std::string error;

    const auto malformed = Payload({
        0x12,
        0x00, 0x00, 0x01,
        0x41, 0x01,
    });

    assert(!packetizer.Packetize(
        malformed,
        0,
        16'667,
        output,
        report,
        error));

    assert(output.empty());
}

void TestResetDropsParameterSetCache() {
    H264AnnexBPacketizer packetizer;
    H264PacketizeReport report;
    std::vector<std::uint8_t> output;
    std::string error;

    const auto config = Payload({
        0x00, 0x00, 0x01,
        0x67, 0x01,
        0x00, 0x00, 0x01,
        0x68, 0x02,
    });

    assert(packetizer.Packetize(
        config,
        0,
        16'667,
        output,
        report,
        error));

    packetizer.Reset();

    const auto idr = Payload({
        0x00, 0x00, 0x01,
        0x65, 0x03,
    });

    assert(!packetizer.Packetize(
        idr,
        1,
        16'667,
        output,
        report,
        error));
}

}  // namespace

int main() {
    TestGoldenNonKeyframePacket();
    TestCachedParameterSetsRepairIdr();
    TestCurrentParameterSetsAreOrderedBeforeIdr();
    TestIdrWithoutRecoveryStateFails();
    TestMalformedPrefixIsRejected();
    TestResetDropsParameterSetCache();
    return 0;
}
