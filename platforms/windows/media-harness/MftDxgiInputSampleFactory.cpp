#include "MftDxgiInputSampleFactory.h"

#include <mfapi.h>

#include <limits>

namespace displaymesh::media {

MftDxgiInputSampleFactory::
MftDxgiInputSampleFactory(
    ID3D11Device* device) noexcept {
    if (device != nullptr) {
        device->QueryInterface(
            IID_PPV_ARGS(&device_));
    }
}

HRESULT
MftDxgiInputSampleFactory::
CreateFromSharedHandle(
    HANDLE sharedHandle,
    const bridge::SharedGpuSurfaceDescriptor&
        descriptor,
    std::uint64_t presentationTimeMicros,
    std::uint32_t durationMicros,
    Microsoft::WRL::ComPtr<IMFSample>&
        sample) noexcept {
    sample.Reset();

    if (device_ == nullptr ||
        sharedHandle == nullptr ||
        sharedHandle ==
            INVALID_HANDLE_VALUE ||
        !descriptor.IsValid() ||
        durationMicros == 0) {
        return E_INVALIDARG;
    }

    constexpr std::uint64_t
        kHundredNanosecondsPerMicrosecond =
            10;

    if (presentationTimeMicros >
            static_cast<std::uint64_t>(
                std::numeric_limits<
                    LONGLONG>::max()) /
                kHundredNanosecondsPerMicrosecond ||
        static_cast<std::uint64_t>(
            durationMicros) >
            static_cast<std::uint64_t>(
                std::numeric_limits<
                    LONGLONG>::max()) /
                kHundredNanosecondsPerMicrosecond) {
        return HRESULT_FROM_WIN32(
            ERROR_ARITHMETIC_OVERFLOW);
    }

    Microsoft::WRL::ComPtr<
        ID3D11Texture2D> texture;
    HRESULT result =
        device_->OpenSharedResource1(
            sharedHandle,
            IID_PPV_ARGS(&texture));
    if (FAILED(result)) {
        return result;
    }

    D3D11_TEXTURE2D_DESC actual{};
    texture->GetDesc(&actual);

    if (actual.Width != descriptor.width ||
        actual.Height != descriptor.height ||
        static_cast<std::uint32_t>(
            actual.Format) !=
            descriptor.dxgiFormat ||
        (actual.MiscFlags &
            D3D11_RESOURCE_MISC_SHARED_NTHANDLE)
            == 0) {
        return E_INVALIDARG;
    }

    Microsoft::WRL::ComPtr<
        IDXGIKeyedMutex> keyedMutex;
    result = texture.As(&keyedMutex);
    if (FAILED(result)) {
        return result;
    }

    Microsoft::WRL::ComPtr<
        IMFMediaBuffer> buffer;
    result = MFCreateDXGISurfaceBuffer(
        __uuidof(ID3D11Texture2D),
        texture.Get(),
        0,
        FALSE,
        &buffer);
    if (FAILED(result)) {
        return result;
    }

    Microsoft::WRL::ComPtr<
        IMFSample> created;
    result = MFCreateSample(&created);
    if (FAILED(result)) {
        return result;
    }

    result = created->AddBuffer(
        buffer.Get());
    if (FAILED(result)) {
        return result;
    }

    const auto sampleTime =
        static_cast<LONGLONG>(
            presentationTimeMicros *
            kHundredNanosecondsPerMicrosecond);
    const auto sampleDuration =
        static_cast<LONGLONG>(
            static_cast<std::uint64_t>(
                durationMicros) *
            kHundredNanosecondsPerMicrosecond);

    result = created->SetSampleTime(
        sampleTime);
    if (FAILED(result)) {
        return result;
    }

    result = created->SetSampleDuration(
        sampleDuration);
    if (FAILED(result)) {
        return result;
    }

    sample = std::move(created);
    return S_OK;
}

}  // namespace displaymesh::media
