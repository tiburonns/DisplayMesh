#pragma once
#define NOMINMAX

#include <Windows.h>
#include <d3d11_1.h>
#include <mfidl.h>
#include <wrl/client.h>

#include <cstdint>

#include "SharedGpuSlotContract.h"

namespace displaymesh::media {

class MftDxgiInputSampleFactory {
public:
    explicit MftDxgiInputSampleFactory(
        ID3D11Device* device) noexcept;

    bool IsReady() const noexcept {
        return device_ != nullptr;
    }

    HRESULT CreateFromSharedHandle(
        HANDLE sharedHandle,
        const bridge::SharedGpuSurfaceDescriptor&
            descriptor,
        std::uint64_t presentationTimeMicros,
        std::uint32_t durationMicros,
        Microsoft::WRL::ComPtr<IMFSample>&
            sample) noexcept;

private:
    Microsoft::WRL::ComPtr<
        ID3D11Device1> device_;
};

}  // namespace displaymesh::media
