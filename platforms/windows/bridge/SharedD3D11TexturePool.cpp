#include "SharedD3D11TexturePool.h"

#include <limits>

namespace displaymesh::bridge {

SharedD3D11TexturePool::
SharedD3D11TexturePool(
    Microsoft::WRL::ComPtr<
        ID3D11Device> device) noexcept
    : device_(std::move(device)) {}

HRESULT SharedD3D11TexturePool::Recreate(
    std::uint32_t width,
    std::uint32_t height,
    DXGI_FORMAT format) noexcept {
    if (device_ == nullptr ||
        width == 0 ||
        height == 0 ||
        width >
            D3D11_REQ_TEXTURE2D_U_OR_V_DIMENSION ||
        height >
            D3D11_REQ_TEXTURE2D_U_OR_V_DIMENSION ||
        format == DXGI_FORMAT_UNKNOWN) {
        return E_INVALIDARG;
    }

    if (generation_ ==
        std::numeric_limits<
            std::uint64_t>::max()) {
        return HRESULT_FROM_WIN32(
            ERROR_ARITHMETIC_OVERFLOW);
    }

    const auto nextGeneration =
        generation_ + 1;

    std::array<
        SharedD3D11TextureSlot,
        kFrameMailboxSlotCount>
        candidate{};
    SharedGpuSlotContract
        candidateContract;

    for (std::uint32_t index = 0;
         index < kFrameMailboxSlotCount;
         ++index) {
        const HRESULT result =
            CreateSlot(
                index,
                nextGeneration,
                width,
                height,
                format,
                candidate[index]);

        if (FAILED(result)) {
            return result;
        }

        if (!candidateContract.Register(
                candidate[index].Descriptor())) {
            return E_FAIL;
        }
    }

    slots_ = std::move(candidate);
    contract_ = std::move(
        candidateContract);
    generation_ = nextGeneration;
    return S_OK;
}

void SharedD3D11TexturePool::Reset() noexcept {
    slots_ = {};
    contract_.Reset();
    generation_ = 0;
}

const SharedD3D11TextureSlot*
SharedD3D11TexturePool::Slot(
    std::uint32_t index) const noexcept {
    if (index >= kFrameMailboxSlotCount) {
        return nullptr;
    }

    const auto& slot = slots_[index];
    return slot.IsValid()
        ? &slot
        : nullptr;
}

HRESULT SharedD3D11TexturePool::CreateSlot(
    std::uint32_t slotIndex,
    std::uint64_t generation,
    std::uint32_t width,
    std::uint32_t height,
    DXGI_FORMAT format,
    SharedD3D11TextureSlot&
        output) noexcept {
    D3D11_TEXTURE2D_DESC description{};
    description.Width = width;
    description.Height = height;
    description.MipLevels = 1;
    description.ArraySize = 1;
    description.Format = format;
    description.SampleDesc.Count = 1;
    description.Usage = D3D11_USAGE_DEFAULT;
    description.BindFlags =
        D3D11_BIND_SHADER_RESOURCE |
        D3D11_BIND_RENDER_TARGET;
    description.MiscFlags =
        D3D11_RESOURCE_MISC_SHARED_NTHANDLE |
        D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX;

    Microsoft::WRL::ComPtr<
        ID3D11Texture2D> texture;
    HRESULT result =
        device_->CreateTexture2D(
            &description,
            nullptr,
            &texture);
    if (FAILED(result)) {
        return result;
    }

    Microsoft::WRL::ComPtr<
        IDXGIResource1> resource;
    result = texture.As(&resource);
    if (FAILED(result)) {
        return result;
    }

    HANDLE sharedHandle = nullptr;
    result = resource->CreateSharedHandle(
        nullptr,
        DXGI_SHARED_RESOURCE_READ |
            DXGI_SHARED_RESOURCE_WRITE,
        nullptr,
        &sharedHandle);

    if (FAILED(result)) {
        return result;
    }

    if (sharedHandle == nullptr ||
        sharedHandle ==
            INVALID_HANDLE_VALUE) {
        if (sharedHandle != nullptr &&
            sharedHandle !=
                INVALID_HANDLE_VALUE) {
            CloseHandle(sharedHandle);
        }
        return E_HANDLE;
    }

    output.descriptor_ =
        SharedGpuSurfaceDescriptor{
            slotIndex,
            generation,
            width,
            height,
            static_cast<std::uint32_t>(
                format),
        };
    output.texture_ =
        std::move(texture);
    output.sharedHandle_.Reset(
        sharedHandle);

    return output.IsValid()
        ? S_OK
        : E_FAIL;
}

}  // namespace displaymesh::bridge
