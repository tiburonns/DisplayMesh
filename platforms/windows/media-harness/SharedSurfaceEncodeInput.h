#pragma once

#define NOMINMAX
#include <Windows.h>
#include <mfidl.h>
#include <wrl/client.h>

#include "BoundedEncodeWorker.h"
#include "MftDxgiInputSampleFactory.h"
#include "SharedD3D11TexturePool.h"

namespace displaymesh::media {

class SharedSurfaceEncodeInput {
public:
    SharedSurfaceEncodeInput(
        bridge::SharedD3D11TexturePool& pool,
        MftDxgiInputSampleFactory& factory) noexcept
        : pool_(pool),
          factory_(factory) {}

    HRESULT CreateSample(
        const EncodeWorkItem& item,
        Microsoft::WRL::ComPtr<IMFSample>&
            sample) noexcept;

private:
    bridge::SharedD3D11TexturePool& pool_;
    MftDxgiInputSampleFactory& factory_;
};

}  // namespace displaymesh::media
