#include "MftEncodedSampleProcessor.h"

#include <mfapi.h>
#include <wrl.h>

#include <algorithm>
#include <cstdint>
#include <limits>
#include <new>
#include <span>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace displaymesh::media {
namespace {

class LockedMediaBuffer {
public:
    explicit LockedMediaBuffer(
        IMFMediaBuffer* buffer) noexcept
        : buffer_(buffer) {}

    HRESULT Lock() noexcept {
        if (buffer_ == nullptr) {
            return E_POINTER;
        }

        return buffer_->Lock(
            &data_,
            &maximumLength_,
            &currentLength_);
    }

    ~LockedMediaBuffer() {
        if (buffer_ != nullptr &&
            data_ != nullptr) {
            buffer_->Unlock();
        }
    }

    BYTE* Data() const noexcept {
        return data_;
    }

    DWORD CurrentLength() const noexcept {
        return currentLength_;
    }

private:
    IMFMediaBuffer* buffer_{};
    BYTE* data_{};
    DWORD maximumLength_{};
    DWORD currentLength_{};
};

bool ConvertTiming(
    IMFSample* sample,
    std::uint64_t& presentationTimeMicros,
    std::uint32_t& durationMicros,
    std::string& error) noexcept {
    LONGLONG sampleTime = 0;
    HRESULT hr =
        sample->GetSampleTime(&sampleTime);
    if (FAILED(hr) || sampleTime < 0) {
        error =
            "Media Foundation H.264 sample has no valid presentation timestamp";
        return false;
    }

    LONGLONG duration = 0;
    hr = sample->GetSampleDuration(&duration);
    if (FAILED(hr) || duration <= 0) {
        error =
            "Media Foundation H.264 sample has no valid duration";
        return false;
    }

    constexpr LONGLONG kHundredNanosecondsPerMicrosecond =
        10;

    const auto timestampMicros =
        static_cast<unsigned long long>(
            sampleTime /
            kHundredNanosecondsPerMicrosecond);
    const auto durationValueMicros =
        static_cast<unsigned long long>(
            duration /
            kHundredNanosecondsPerMicrosecond);

    if (durationValueMicros == 0 ||
        durationValueMicros >
            std::numeric_limits<
                std::uint32_t>::max()) {
        error =
            "Media Foundation H.264 sample duration is outside the DMP range";
        return false;
    }

    presentationTimeMicros =
        static_cast<std::uint64_t>(
            timestampMicros);
    durationMicros =
        static_cast<std::uint32_t>(
            durationValueMicros);
    return true;
}

}  // namespace

HRESULT MftEncodedSampleProcessor::Process(
    IMFSample* sample,
    std::vector<std::uint8_t>& dmpVideoPayload,
    H264NormalizeReport& normalizeReport,
    H264PacketizeReport& packetizeReport,
    std::string& error) noexcept {
    dmpVideoPayload.clear();
    normalizeReport = {};
    packetizeReport = {};
    error.clear();

    if (sample == nullptr) {
        error =
            "Media Foundation output sample is null";
        return E_POINTER;
    }

    try {
        ComPtr<IMFMediaBuffer> buffer;
        HRESULT hr =
            sample->ConvertToContiguousBuffer(
                &buffer);
        if (FAILED(hr)) {
            error =
                "Could not make Media Foundation H.264 output contiguous";
            return hr;
        }

        LockedMediaBuffer locked(
            buffer.Get());
        hr = locked.Lock();
        if (FAILED(hr)) {
            error =
                "Could not lock Media Foundation H.264 output buffer";
            return hr;
        }

        if (locked.CurrentLength() == 0 ||
            locked.Data() == nullptr) {
            error =
                "Media Foundation H.264 output sample is empty";
            return E_INVALIDARG;
        }

        std::vector<std::uint8_t> encoded(
            locked.Data(),
            locked.Data() +
                locked.CurrentLength());

        std::uint64_t presentationTimeMicros = 0;
        std::uint32_t durationMicros = 0;
        if (!ConvertTiming(
                sample,
                presentationTimeMicros,
                durationMicros,
                error)) {
            return E_INVALIDARG;
        }

        std::vector<std::uint8_t> annexB;
        if (!normalizer_.Normalize(
                encoded,
                annexB,
                normalizeReport,
                error)) {
            return E_INVALIDARG;
        }

        if (!packetizer_.Packetize(
                annexB,
                presentationTimeMicros,
                durationMicros,
                dmpVideoPayload,
                packetizeReport,
                error)) {
            return E_FAIL;
        }

        return S_OK;
    } catch (const std::bad_alloc&) {
        dmpVideoPayload.clear();
        error =
            "Out of memory while processing Media Foundation H.264 output";
        return E_OUTOFMEMORY;
    } catch (...) {
        dmpVideoPayload.clear();
        error =
            "Unexpected failure while processing Media Foundation H.264 output";
        return E_FAIL;
    }
}

void MftEncodedSampleProcessor::Reset() noexcept {
    packetizer_.Reset();
}

}  // namespace displaymesh::media
