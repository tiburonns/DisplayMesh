#include "H264AnnexBPacketizer.h"

#include "../protocol/DmpFrame.h"

#include <algorithm>
#include <cstddef>
#include <iterator>
#include <limits>
#include <utility>

namespace displaymesh::media {
namespace {

constexpr std::size_t kVideoHeaderSize = 16;
constexpr std::uint8_t kCodecH264 = 0x01;
constexpr std::uint8_t kKeyframeFlag = 0x01;
constexpr std::uint8_t kNalIdr = 5;
constexpr std::uint8_t kNalSps = 7;
constexpr std::uint8_t kNalPps = 8;
constexpr std::uint8_t kStartCode[4] = {
    0x00, 0x00, 0x00, 0x01,
};

struct NalView {
    std::size_t offset{};
    std::size_t size{};
    std::uint8_t type{};
};

bool FindStartCode(
    std::span<const std::uint8_t> data,
    std::size_t from,
    std::size_t& offset,
    std::size_t& length) noexcept {
    if (data.size() < 3 ||
        from >= data.size()) {
        return false;
    }

    for (std::size_t index = from;
         index + 2 < data.size();
         ++index) {
        if (data[index] != 0 ||
            data[index + 1] != 0) {
            continue;
        }

        if (index + 3 < data.size() &&
            data[index + 2] == 0 &&
            data[index + 3] == 1) {
            offset = index;
            length = 4;
            return true;
        }

        if (data[index + 2] == 1) {
            offset = index;
            length = 3;
            return true;
        }
    }

    return false;
}

bool ParseAnnexB(
    std::span<const std::uint8_t> data,
    std::vector<NalView>& nals,
    std::string& error) {
    nals.clear();

    if (data.empty()) {
        error = "H.264 Annex-B access unit is empty";
        return false;
    }

    std::size_t startOffset = 0;
    std::size_t startLength = 0;

    if (!FindStartCode(
            data,
            0,
            startOffset,
            startLength)) {
        error =
            "H.264 access unit has no Annex-B start code";
        return false;
    }

    if (std::any_of(
            data.begin(),
            data.begin() +
                static_cast<std::ptrdiff_t>(
                    startOffset),
            [](std::uint8_t byte) {
                return byte != 0;
            })) {
        error =
            "H.264 access unit has data before its first start code";
        return false;
    }

    for (;;) {
        const std::size_t payloadOffset =
            startOffset + startLength;

        std::size_t nextOffset = 0;
        std::size_t nextLength = 0;
        const bool hasNext =
            FindStartCode(
                data,
                payloadOffset,
                nextOffset,
                nextLength);

        std::size_t payloadEnd =
            hasNext
                ? nextOffset
                : data.size();

        while (payloadEnd > payloadOffset &&
               data[payloadEnd - 1] == 0) {
            --payloadEnd;
        }

        if (payloadEnd <= payloadOffset) {
            error =
                "H.264 Annex-B access unit contains an empty NAL unit";
            return false;
        }

        const std::uint8_t nalType =
            static_cast<std::uint8_t>(
                data[payloadOffset] & 0x1fU);

        if (nalType == 0) {
            error =
                "H.264 Annex-B access unit contains NAL type 0";
            return false;
        }

        nals.push_back(
            NalView{
                payloadOffset,
                payloadEnd - payloadOffset,
                nalType,
            });

        if (!hasNext) {
            break;
        }

        startOffset = nextOffset;
        startLength = nextLength;
    }

    return !nals.empty();
}

void AppendNal(
    std::vector<std::uint8_t>& output,
    std::span<const std::uint8_t> payload) {
    output.insert(
        output.end(),
        std::begin(kStartCode),
        std::end(kStartCode));
    output.insert(
        output.end(),
        payload.begin(),
        payload.end());
}

std::vector<std::uint8_t> CopyNal(
    std::span<const std::uint8_t> source,
    const NalView& nal) {
    return std::vector<std::uint8_t>(
        source.begin() +
            static_cast<std::ptrdiff_t>(
                nal.offset),
        source.begin() +
            static_cast<std::ptrdiff_t>(
                nal.offset + nal.size));
}

void AppendBigEndian(
    std::vector<std::uint8_t>& output,
    std::uint64_t value) {
    for (int shift = 56;
         shift >= 0;
         shift -= 8) {
        output.push_back(
            static_cast<std::uint8_t>(
                value >>
                static_cast<unsigned>(
                    shift)));
    }
}

void AppendBigEndian(
    std::vector<std::uint8_t>& output,
    std::uint32_t value) {
    for (int shift = 24;
         shift >= 0;
         shift -= 8) {
        output.push_back(
            static_cast<std::uint8_t>(
                value >>
                static_cast<unsigned>(
                    shift)));
    }
}

}  // namespace

bool H264AnnexBPacketizer::Packetize(
    std::span<const std::uint8_t> annexB,
    std::uint64_t presentationTimeMicros,
    std::uint32_t durationMicros,
    std::vector<std::uint8_t>& dmpVideoPayload,
    H264PacketizeReport& report,
    std::string& error) {
    dmpVideoPayload.clear();
    report = {};
    error.clear();

    std::vector<NalView> nals;
    if (!ParseAnnexB(
            annexB,
            nals,
            error)) {
        return false;
    }

    report.nalUnitCount =
        static_cast<std::uint32_t>(
            nals.size());

    const NalView* currentSps = nullptr;
    const NalView* currentPps = nullptr;

    for (const auto& nal : nals) {
        if (nal.type == kNalIdr) {
            report.keyframe = true;
        } else if (nal.type == kNalSps) {
            currentSps = &nal;
        } else if (nal.type == kNalPps) {
            currentPps = &nal;
        }
    }

    std::vector<std::uint8_t> nextSps;
    std::vector<std::uint8_t> nextPps;

    if (currentSps != nullptr) {
        nextSps = CopyNal(
            annexB,
            *currentSps);
    }

    if (currentPps != nullptr) {
        nextPps = CopyNal(
            annexB,
            *currentPps);
    }

    std::vector<std::uint8_t> normalized;
    normalized.reserve(
        annexB.size() +
        sps_.size() +
        pps_.size() +
        16);

    if (report.keyframe) {
        const auto& effectiveSps =
            !nextSps.empty()
                ? nextSps
                : sps_;
        const auto& effectivePps =
            !nextPps.empty()
                ? nextPps
                : pps_;

        if (effectiveSps.empty() ||
            effectivePps.empty()) {
            error =
                "H.264 IDR access unit has no recoverable SPS/PPS";
            return false;
        }

        report.insertedSps =
            nextSps.empty();
        report.insertedPps =
            nextPps.empty();

        AppendNal(
            normalized,
            effectiveSps);
        AppendNal(
            normalized,
            effectivePps);

        for (const auto& nal : nals) {
            if (nal.type == kNalSps ||
                nal.type == kNalPps) {
                continue;
            }

            AppendNal(
                normalized,
                annexB.subspan(
                    nal.offset,
                    nal.size));
        }
    } else {
        for (const auto& nal : nals) {
            AppendNal(
                normalized,
                annexB.subspan(
                    nal.offset,
                    nal.size));
        }
    }

    if (normalized.empty()) {
        error =
            "H.264 packetizer produced an empty Annex-B payload";
        return false;
    }

    if (normalized.size() >
        displaymesh::kDmpMaximumPayloadSize -
            kVideoHeaderSize) {
        error =
            "H.264 DMP video payload exceeds the DMP frame budget";
        return false;
    }

    dmpVideoPayload.reserve(
        kVideoHeaderSize +
        normalized.size());

    dmpVideoPayload.push_back(
        kCodecH264);
    dmpVideoPayload.push_back(
        report.keyframe
            ? kKeyframeFlag
            : 0);
    dmpVideoPayload.push_back(0);
    dmpVideoPayload.push_back(0);
    AppendBigEndian(
        dmpVideoPayload,
        presentationTimeMicros);
    AppendBigEndian(
        dmpVideoPayload,
        durationMicros);
    dmpVideoPayload.insert(
        dmpVideoPayload.end(),
        normalized.begin(),
        normalized.end());

    if (!nextSps.empty()) {
        sps_ = std::move(nextSps);
    }

    if (!nextPps.empty()) {
        pps_ = std::move(nextPps);
    }

    return true;
}

void H264AnnexBPacketizer::Reset() noexcept {
    sps_.clear();
    pps_.clear();
}

}  // namespace displaymesh::media
