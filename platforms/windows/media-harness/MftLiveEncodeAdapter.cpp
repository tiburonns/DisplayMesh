#include "MftLiveEncodeAdapter.h"

#include <mfapi.h>
#include <mferror.h>

#include <cstdio>
#include <utility>

namespace displaymesh::media {
namespace {

std::string HrMessage(
    const char* operation,
    HRESULT hr) {
    char buffer[128]{};
    sprintf_s(
        buffer,
        "%s failed: 0x%08lX",
        operation,
        static_cast<unsigned long>(hr));
    return buffer;
}

class MediaEventReleaser {
public:
    explicit MediaEventReleaser(
        IUnknown* events) noexcept
        : events_(events) {}

    ~MediaEventReleaser() {
        if (events_ != nullptr) {
            events_->Release();
        }
    }

private:
    IUnknown* events_{};
};

}  // namespace

MftLiveEncodeAdapter::
MftLiveEncodeAdapter(
    IMFTransform* encoder,
    InputSampleFactory inputFactory,
    PacketHandler packetHandler) noexcept
    : encoder_(encoder),
      inputFactory_(std::move(inputFactory)),
      packetHandler_(std::move(packetHandler)) {}

MftLiveEncodeAdapter::
MftLiveEncodeAdapter(
    IMFTransform* encoder,
    SharedSurfaceEncodeInput& input,
    PacketHandler packetHandler) noexcept
    : MftLiveEncodeAdapter(
          encoder,
          [&input](
              const EncodeWorkItem& item,
              Microsoft::WRL::ComPtr<IMFSample>&
                  sample) {
              return input.CreateSample(
                  item,
                  sample);
          },
          std::move(packetHandler)) {}

bool MftLiveEncodeAdapter::IsReady()
    const noexcept {
    return encoder_ != nullptr &&
        static_cast<bool>(inputFactory_) &&
        static_cast<bool>(packetHandler_);
}

bool MftLiveEncodeAdapter::ProcessInput(
    const EncodeWorkItem& item,
    std::string& error) noexcept {
    error.clear();

    if (!IsReady() || !item.IsValid()) {
        ++stats_.inputFailures;
        error =
            "MFT live adapter is not ready or frame is invalid";
        return false;
    }

    Microsoft::WRL::ComPtr<IMFSample>
        sample;
    HRESULT hr =
        inputFactory_(
            item,
            sample);
    if (FAILED(hr) || sample == nullptr) {
        ++stats_.inputFailures;
        error = HrMessage(
            "Create input sample",
            FAILED(hr) ? hr : E_FAIL);
        return false;
    }

    hr = encoder_->ProcessInput(
        0,
        sample.Get(),
        0);
    if (FAILED(hr)) {
        ++stats_.inputFailures;
        error = HrMessage(
            "IMFTransform::ProcessInput",
            hr);
        return false;
    }

    ++stats_.inputSamplesSubmitted;
    return true;
}

bool MftLiveEncodeAdapter::ProcessOutput(
    std::string& error) noexcept {
    error.clear();

    if (!IsReady()) {
        ++stats_.outputFailures;
        error =
            "MFT live adapter is not ready";
        return false;
    }

    MFT_OUTPUT_STREAM_INFO streamInfo{};
    HRESULT hr =
        encoder_->GetOutputStreamInfo(
            0,
            &streamInfo);
    if (FAILED(hr)) {
        ++stats_.outputFailures;
        error = HrMessage(
            "IMFTransform::GetOutputStreamInfo",
            hr);
        return false;
    }

    Microsoft::WRL::ComPtr<IMFSample>
        ownedSample;
    bool transformProvidesSample = false;
    hr = CreateOutputSample(
        streamInfo,
        ownedSample,
        transformProvidesSample);
    if (FAILED(hr)) {
        ++stats_.outputFailures;
        error = HrMessage(
            "Create MFT output sample",
            hr);
        return false;
    }

    MFT_OUTPUT_DATA_BUFFER output{};
    output.dwStreamID = 0;
    output.pSample =
        transformProvidesSample
            ? nullptr
            : ownedSample.Get();

    DWORD status = 0;
    hr = encoder_->ProcessOutput(
        0,
        1,
        &output,
        &status);

    MediaEventReleaser events(
        output.pEvents);

    if (hr == MF_E_TRANSFORM_NEED_MORE_INPUT) {
        ++stats_.outputFailures;
        error =
            "MFT signaled HaveOutput but ProcessOutput needs more input";
        return false;
    }

    if (FAILED(hr)) {
        ++stats_.outputFailures;
        error = HrMessage(
            "IMFTransform::ProcessOutput",
            hr);
        return false;
    }

    Microsoft::WRL::ComPtr<IMFSample>
        produced;
    if (transformProvidesSample) {
        if (output.pSample == nullptr) {
            ++stats_.outputFailures;
            error =
                "MFT produced no output sample";
            return false;
        }
        produced.Attach(
            output.pSample);
        output.pSample = nullptr;
    } else {
        produced = ownedSample;
    }

    H264NormalizeReport normalizeReport;
    H264PacketizeReport packetizeReport;
    std::vector<std::uint8_t>
        dmpPayload;

    hr = sampleProcessor_.Process(
        produced.Get(),
        dmpPayload,
        normalizeReport,
        packetizeReport,
        error);
    if (FAILED(hr)) {
        ++stats_.outputFailures;
        if (error.empty()) {
            error = HrMessage(
                "Process encoded H.264 sample",
                hr);
        }
        return false;
    }

    std::string handlerError;
    if (!packetHandler_(
            std::span<const std::uint8_t>(
                dmpPayload.data(),
                dmpPayload.size()),
            normalizeReport,
            packetizeReport,
            handlerError)) {
        ++stats_.outputFailures;
        error = handlerError.empty()
            ? "DMP video packet handler rejected encoded output"
            : handlerError;
        return false;
    }

    ++stats_.outputSamplesProduced;
    if (packetizeReport.keyframe) {
        ++stats_.keyframesProduced;
    }
    return true;
}

void MftLiveEncodeAdapter::Reset()
    noexcept {
    sampleProcessor_.Reset();
    stats_ = {};
}

MftLiveAdapterStats
MftLiveEncodeAdapter::Stats()
    const noexcept {
    return stats_;
}

HRESULT
MftLiveEncodeAdapter::
CreateOutputSample(
    MFT_OUTPUT_STREAM_INFO& streamInfo,
    Microsoft::WRL::ComPtr<IMFSample>&
        sample,
    bool& transformProvidesSample) noexcept {
    sample.Reset();
    transformProvidesSample =
        (streamInfo.dwFlags &
            MFT_OUTPUT_STREAM_PROVIDES_SAMPLES) != 0;

    if (transformProvidesSample) {
        return S_OK;
    }

    HRESULT hr =
        MFCreateSample(&sample);
    if (FAILED(hr)) {
        return hr;
    }

    if (streamInfo.cbSize == 0) {
        return E_INVALIDARG;
    }

    Microsoft::WRL::ComPtr<
        IMFMediaBuffer> buffer;
    hr = MFCreateMemoryBuffer(
        streamInfo.cbSize,
        &buffer);
    if (FAILED(hr)) {
        return hr;
    }

    return sample->AddBuffer(
        buffer.Get());
}

}  // namespace displaymesh::media
