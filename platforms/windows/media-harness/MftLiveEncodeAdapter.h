#pragma once

#define NOMINMAX
#include <Windows.h>
#include <mftransform.h>
#include <wrl/client.h>

#include <cstdint>
#include <functional>
#include <span>
#include <string>
#include <vector>

#include "MftEncodedSampleProcessor.h"
#include "SharedSurfaceEncodeInput.h"

namespace displaymesh::media {

struct MftLiveAdapterStats {
    std::uint64_t inputSamplesSubmitted{};
    std::uint64_t outputSamplesProduced{};
    std::uint64_t keyframesProduced{};
    std::uint64_t inputFailures{};
    std::uint64_t outputFailures{};
};

class MftLiveEncodeAdapter {
public:
    using PacketHandler =
        std::function<bool(
            std::span<const std::uint8_t>,
            const H264NormalizeReport&,
            const H264PacketizeReport&,
            std::string&)>;

    MftLiveEncodeAdapter(
        IMFTransform* encoder,
        SharedSurfaceEncodeInput& input,
        PacketHandler packetHandler) noexcept;

    bool IsReady() const noexcept;

    bool ProcessInput(
        const EncodeWorkItem& item,
        std::string& error) noexcept;

    bool ProcessOutput(
        std::string& error) noexcept;

    void Reset() noexcept;

    MftLiveAdapterStats
    Stats() const noexcept;

private:
    HRESULT CreateOutputSample(
        MFT_OUTPUT_STREAM_INFO& streamInfo,
        Microsoft::WRL::ComPtr<IMFSample>&
            sample,
        bool& transformProvidesSample) noexcept;

    Microsoft::WRL::ComPtr<IMFTransform>
        encoder_;
    SharedSurfaceEncodeInput& input_;
    PacketHandler packetHandler_;
    MftEncodedSampleProcessor
        sampleProcessor_;
    MftLiveAdapterStats stats_{};
};

}  // namespace displaymesh::media
