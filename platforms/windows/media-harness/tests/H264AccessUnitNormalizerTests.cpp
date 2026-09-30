#include "H264AccessUnitNormalizer.h"

#include <cassert>
#include <cstdint>
#include <string>
#include <vector>

using namespace displaymesh::media;

namespace {

void TestAnnexBPassesThrough() {
    const std::vector<std::uint8_t> input{
        0x00, 0x00, 0x00, 0x01,
        0x67, 0x64, 0x00, 0x1f,
        0x00, 0x00, 0x01,
        0x68, 0xee, 0x3c, 0x80,
    };

    H264AccessUnitNormalizer normalizer;
    H264NormalizeReport report;
    std::vector<std::uint8_t> output;
    std::string error;

    assert(normalizer.Normalize(
        input,
        output,
        report,
        error));
    assert(output == input);
    assert(report.inputFormat ==
        H264AccessUnitFormat::AnnexB);
    assert(report.nalUnitCount == 2);
}

void TestLengthPrefixedConvertsToAnnexB() {
    const std::vector<std::uint8_t> input{
        0x00, 0x00, 0x00, 0x04,
        0x67, 0x64, 0x00, 0x1f,
        0x00, 0x00, 0x00, 0x03,
        0x65, 0x88, 0x84,
    };

    const std::vector<std::uint8_t> expected{
        0x00, 0x00, 0x00, 0x01,
        0x67, 0x64, 0x00, 0x1f,
        0x00, 0x00, 0x00, 0x01,
        0x65, 0x88, 0x84,
    };

    H264AccessUnitNormalizer normalizer;
    H264NormalizeReport report;
    std::vector<std::uint8_t> output;
    std::string error;

    assert(normalizer.Normalize(
        input,
        output,
        report,
        error));
    assert(output == expected);
    assert(report.inputFormat ==
        H264AccessUnitFormat::AvccLengthPrefixed);
    assert(report.nalUnitCount == 2);
}

void TestTruncatedLengthIsRejected() {
    const std::vector<std::uint8_t> input{
        0x00, 0x00, 0x00,
    };

    H264AccessUnitNormalizer normalizer;
    H264NormalizeReport report;
    std::vector<std::uint8_t> output{1, 2, 3};
    std::string error;

    assert(!normalizer.Normalize(
        input,
        output,
        report,
        error));
    assert(output.empty());
    assert(!error.empty());
}

void TestOversizedNalIsRejected() {
    const std::vector<std::uint8_t> input{
        0x00, 0x00, 0x00, 0x08,
        0x65, 0x88,
    };

    H264AccessUnitNormalizer normalizer;
    H264NormalizeReport report;
    std::vector<std::uint8_t> output;
    std::string error;

    assert(!normalizer.Normalize(
        input,
        output,
        report,
        error));
    assert(!error.empty());
}

void TestZeroLengthNalIsRejected() {
    const std::vector<std::uint8_t> input{
        0x00, 0x00, 0x00, 0x00,
    };

    H264AccessUnitNormalizer normalizer;
    H264NormalizeReport report;
    std::vector<std::uint8_t> output;
    std::string error;

    assert(!normalizer.Normalize(
        input,
        output,
        report,
        error));
}

void TestMalformedAnnexBIsRejected() {
    const std::vector<std::uint8_t> input{
        0x00, 0x00, 0x00, 0x01,
        0x00,
    };

    H264AccessUnitNormalizer normalizer;
    H264NormalizeReport report;
    std::vector<std::uint8_t> output;
    std::string error;

    assert(!normalizer.Normalize(
        input,
        output,
        report,
        error));
    assert(!error.empty());
}

}  // namespace

int main() {
    TestAnnexBPassesThrough();
    TestLengthPrefixedConvertsToAnnexB();
    TestTruncatedLengthIsRejected();
    TestOversizedNalIsRejected();
    TestZeroLengthNalIsRejected();
    TestMalformedAnnexBIsRejected();
    return 0;
}
