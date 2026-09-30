#define NOMINMAX
#include <Windows.h>
#include <d3d11_1.h>
#include <wrl/client.h>

#include <cstdint>
#include <cstdlib>
#include <iostream>

#include "../bridge/SharedD3D11TexturePool.h"

using Microsoft::WRL::ComPtr;
using namespace displaymesh::bridge;

namespace {

void Require(bool condition) {
    if (!condition) {
        std::cerr << "DisplayMesh shared D3D11 pool requirement failed\n";
        std::exit(EXIT_FAILURE);
    }
}

ComPtr<ID3D11Device> CreateWarpDevice() {
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;

    const HRESULT result =
        D3D11CreateDevice(
            nullptr,
            D3D_DRIVER_TYPE_WARP,
            nullptr,
            D3D11_CREATE_DEVICE_BGRA_SUPPORT,
            nullptr,
            0,
            D3D11_SDK_VERSION,
            &device,
            nullptr,
            &context);

    Require(SUCCEEDED(result));
    Require(device != nullptr);
    return device;
}

void ValidateSlot(
    ID3D11Device1* device,
    const SharedD3D11TexturePool& pool,
    std::uint32_t index,
    std::uint64_t generation,
    std::uint32_t width,
    std::uint32_t height) {
    const auto* slot = pool.Slot(index);
    Require(slot != nullptr);
    Require(slot->IsValid());
    Require(
        slot->Descriptor().slotIndex ==
        index);
    Require(
        slot->Descriptor().generation ==
        generation);
    Require(
        slot->Descriptor().width ==
        width);
    Require(
        slot->Descriptor().height ==
        height);
    Require(
        slot->Descriptor().dxgiFormat ==
        static_cast<std::uint32_t>(
            DXGI_FORMAT_B8G8R8A8_UNORM));

    ComPtr<ID3D11Texture2D> reopened;
    const HRESULT result =
        device->OpenSharedResource1(
            slot->SharedHandle(),
            IID_PPV_ARGS(&reopened));
    Require(SUCCEEDED(result));
    Require(reopened != nullptr);

    D3D11_TEXTURE2D_DESC description{};
    reopened->GetDesc(&description);
    Require(description.Width == width);
    Require(description.Height == height);
    Require(
        description.Format ==
        DXGI_FORMAT_B8G8R8A8_UNORM);
    Require(
        (description.MiscFlags &
         D3D11_RESOURCE_MISC_SHARED_NTHANDLE)
        != 0);
    Require(
        (description.MiscFlags &
         D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX)
        != 0);

    ComPtr<IDXGIKeyedMutex> keyedMutex;
    Require(SUCCEEDED(
        reopened.As(&keyedMutex)));
}

}  // namespace

int main() {
    auto device = CreateWarpDevice();

    ComPtr<ID3D11Device1> device1;
    Require(SUCCEEDED(device.As(&device1)));
    Require(device1 != nullptr);

    SharedD3D11TexturePool pool(device);
    Require(pool.Generation() == 0);
    Require(pool.Slot(0) == nullptr);

    Require(SUCCEEDED(
        pool.Recreate(1920, 1080)));
    Require(pool.Generation() == 1);

    std::array<HANDLE, kFrameMailboxSlotCount>
        firstHandles{};

    for (std::uint32_t index = 0;
         index < kFrameMailboxSlotCount;
         ++index) {
        ValidateSlot(
            device1.Get(),
            pool,
            index,
            1,
            1920,
            1080);

        const auto* slot = pool.Slot(index);
        Require(slot != nullptr);
        firstHandles[index] =
            slot->SharedHandle();
    }

    for (std::uint32_t lhs = 0;
         lhs < kFrameMailboxSlotCount;
         ++lhs) {
        for (std::uint32_t rhs = lhs + 1;
             rhs < kFrameMailboxSlotCount;
             ++rhs) {
            Require(
                firstHandles[lhs] !=
                firstHandles[rhs]);
        }
    }

    Require(
        pool.Slot(
            kFrameMailboxSlotCount) ==
        nullptr);

    FrameAnnouncement first{};
    first.sequence = 1;
    first.timestampMicros = 1'000;
    first.surfaceGeneration = 1;
    first.slotIndex = 1;
    first.width = 1920;
    first.height = 1080;
    Require(pool.Matches(first));

    Require(SUCCEEDED(
        pool.Recreate(2560, 1440)));
    Require(pool.Generation() == 2);

    Require(!pool.Matches(first));

    for (std::uint32_t index = 0;
         index < kFrameMailboxSlotCount;
         ++index) {
        ValidateSlot(
            device1.Get(),
            pool,
            index,
            2,
            2560,
            1440);
    }

    FrameAnnouncement resized = first;
    resized.surfaceGeneration = 2;
    resized.width = 2560;
    resized.height = 1440;
    Require(pool.Matches(resized));

    std::array<HANDLE, kFrameMailboxSlotCount>
        secondHandles{};
    for (std::uint32_t index = 0;
         index < kFrameMailboxSlotCount;
         ++index) {
        const auto* slot = pool.Slot(index);
        Require(slot != nullptr);
        secondHandles[index] =
            slot->SharedHandle();
    }

    Require(FAILED(
        pool.Recreate(0, 1440)));
    Require(pool.Generation() == 2);
    Require(pool.Matches(resized));

    for (std::uint32_t index = 0;
         index < kFrameMailboxSlotCount;
         ++index) {
        const auto* slot = pool.Slot(index);
        Require(slot != nullptr);
        Require(
            slot->SharedHandle() ==
            secondHandles[index]);

        ValidateSlot(
            device1.Get(),
            pool,
            index,
            2,
            2560,
            1440);
    }

    pool.Reset();
    Require(pool.Generation() == 0);
    Require(pool.Slot(0) == nullptr);
    Require(!pool.Matches(resized));

    return 0;
}
