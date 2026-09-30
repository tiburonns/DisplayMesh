#include "H264AccessUnitNormalizer.h"

#include <algorithm>
#include <cstddef>
#include <iterator>
#include <limits>

namespace displaymesh::media {
namespace {

constexpr std::uint8_t kStartCode[4] = {
    0x00, 0x00, 0x00, 0x01,
};

bool HasAnnexBStartCode(
    std::span<const std::uint8_t> input) noexcept {
    if (input.size() < 3) {
        return false;
    }

    std::size_t offset = 0;
    while (offset < input.size() &&
           input[offset] == 0) {
        ++offset;
    }

    if (offset < 2 ||
        offset >= input.size() ||
        input[offset] != 1) {
        return false;
    }

    return offset == 2 || offset == 3;
}

bool ValidateAnnexB(
    std::span<const std::uint8_t> input,
    std::uint32_t& nalCount,
    std::string& error) {
    nalCount = 0;

    std::size_t index = 0;
    while (index < input.size()) {
        std::size_t start = std::string::npos;
        std::size_t startLength = 0;

        for (std::size_t cursor = index;
             cursor + 2 < input.size();
             ++cursor) {
            if (input[cursor] != 0 ||
                input[cursor + 1] != 0) {
                continue;
            }

            if (cursor + 3 < input.size() &&
                input[cursor + 2] == 0 &&
                input[cursor + 3] == 1) {
                start = cursor;
                startLength = 4;
                break;
            }

            if (input[cursor + 2] == 1) {
                start = cursor;
                startLength = 3;
                break;
            }
        }

        if (start == std::string::npos) {
            break;
        }

        if (nalCount == 0 &&
            std::any_of(
                input.begin(),
                input.begin() +
                    static_cast<std::ptrdiff_t>(start),
                [](std::uint8_t byte) {
                    return byte != 0;
                })) {
            error =
                "H.264 Annex-B data precedes the first start code";
            return false;
        }

        const std::size_t payload =
            start + startLength;

        std::size_t next = input.size();
        for (std::size_t cursor = payload;
             cursor + 2 < input.size();
             ++cursor) {
            if (input[cursor] != 0 ||
                input[cursor + 1] != 0) {
                continue;
            }

            if ((cursor + 3 < input.size() &&
                 input[cursor + 2] == 0 &&
                 input[cursor + 3] == 1) ||
                input[cursor + 2] == 1) {
                next = cursor;
                break;
            }
        }

        std::size_t end = next;
        while (end > payload &&
               input[end - 1] == 0) {
            --end;
        }

        if (end <= payload ||
            (input[payload] & 0x1fU) == 0) {
            error =
                "H.264 Annex-B access unit contains an empty or invalid NAL unit";
            return false;
        }

        if (nalCount ==
            std::numeric_limits<std::uint32_t>::max()) {
            error =
                "H.264 access unit contains too many NAL units";
            return false;
        }

        ++nalCount;
        if (next == input.size()) {
            index = input.size();
        } else {
            index = next;
        }
    }

    if (nalCount == 0) {
        error =
            "H.264 Annex-B access unit contains no NAL units";
        return false;
    }

    error.clear();
    return true;
}

std::uint32_t ReadBigEndianU32(
    const std::uint8_t* bytes) noexcept {
    return
        (static_cast<std::uint32_t>(
            bytes[0]) << 24) |
        (static_cast<std::uint32_t>(
            bytes[1]) << 16) |
        (static_cast<std::uint32_t>(
            bytes[2]) << 8) |
        static_cast<std::uint32_t>(
            bytes[3]);
}

}  // namespace

bool H264AccessUnitNormalizer::Normalize(
    std::span<const std::uint8_t> input,
    std::vector<std::uint8_t>& annexB,
    H264NormalizeReport& report,
    std::string& error) const {
    annexB.clear();
    report = {};
    error.clear();

    if (input.empty()) {
        error = "H.264 access unit is empty";
        return false;
    }

    if (HasAnnexBStartCode(input)) {
        std::uint32_t count = 0;
        if (!ValidateAnnexB(
                input,
                count,
                error)) {
            return false;
        }

        annexB.assign(
            input.begin(),
            input.end());
        report.inputFormat =
            H264AccessUnitFormat::AnnexB;
        report.nalUnitCount = count;
        return true;
    }

    // Media Foundation hardware encoders may expose AVC-style samples
    // with a 4-byte big-endian length before each NAL. Normalize that
    // representation explicitly rather than assuming a GPU/vendor format.
    std::size_t offset = 0;
    std::uint32_t count = 0;

    while (offset < input.size()) {
        if (input.size() - offset < 4) {
            error =
                "H.264 length-prefixed access unit has a truncated NAL length";
            annexB.clear();
            return false;
        }

        const std::uint32_t length =
            ReadBigEndianU32(
                input.data() + offset);
        offset += 4;

        if (length == 0) {
            error =
                "H.264 length-prefixed access unit contains an empty NAL unit";
            annexB.clear();
            return false;
        }

        if (static_cast<std::size_t>(length) >
            input.size() - offset) {
            error =
                "H.264 length-prefixed NAL exceeds the access-unit boundary";
            annexB.clear();
            return false;
        }

        if ((input[offset] & 0x1fU) == 0) {
            error =
                "H.264 length-prefixed access unit contains NAL type 0";
            annexB.clear();
            return false;
        }

        annexB.insert(
            annexB.end(),
            std::begin(kStartCode),
            std::end(kStartCode));
        annexB.insert(
            annexB.end(),
            input.begin() +
                static_cast<std::ptrdiff_t>(offset),
            input.begin() +
                static_cast<std::ptrdiff_t>(
                    offset + length));

        offset += length;

        if (count ==
            std::numeric_limits<std::uint32_t>::max()) {
            error =
                "H.264 access unit contains too many NAL units";
            annexB.clear();
            return false;
        }

        ++count;
    }

    if (count == 0 || annexB.empty()) {
        error =
            "H.264 length-prefixed access unit contains no NAL units";
        annexB.clear();
        return false;
    }

    report.inputFormat =
        H264AccessUnitFormat::AvccLengthPrefixed;
    report.nalUnitCount = count;
    error.clear();
    return true;
}

}  // namespace displaymesh::media
