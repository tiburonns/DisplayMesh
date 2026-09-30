#define NOMINMAX

#include <Windows.h>
#include <d3d11_1.h>
#include <mfapi.h>
#include <mfidl.h>
#include <wrl/client.h>

#include <cassert>
#include <cstdint>

#include "MftDxgiInputSampleFactory.h"
#include "SharedD3D11TexturePool.h"

using Microsoft::WRL::ComPtr;
using displaymesh::bridge::
    SharedD3D11TexturePool;
using displaymesh::media::
    MftDxgiInputSampleFactory;

namespace {

class MfGuard {
public:
    MfGuard() noexcept
        : result_(MFStartup(
              MF_VERSION,
              MFSTARTUP_FULL)) {}

    ~MfGuard() {
        if (SUCCEEDED(result_)) {
            MFShutdown();
        }
    }

    HRESULT Result() const noexcept {
        return result_;
    }

private:
    HRESULT result_{};
};

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

    assert(SUCCEEDED(result));
    assert(device != nullptr);
    return device;
}

void ValidateDxgiBuffer(
    IMFSample* sample,
    std::uint32_t width,
    std::uint32_t height) {
    assert(sample != nullptr);

    DWORD count = 0;
    assert(SUCCEEDED(
        sample->GetBufferCount(&count)));
    assert(count == 1);

    ComPtr<IMFMediaBuffer> buffer;
    assert(SUCCEEDED(
        sample->GetBufferByIndex(
            0,
            &buffer)));

    ComPtr<IMFDXGIBuffer> dxgiBuffer;
    assert(SUCCEEDED(
        buffer.As(&dxgiBuffer)));

    ComPtr<ID3D11Texture2D> texture;
    assert(SUCCEEDED(
        dxgiBuffer->GetResource(
            IID_PPV_ARGS(&texture))));
    assert(texture != nullptr);

    D3D11_TEXTURE2D_DESC desc{};
    texture->GetDesc(&desc);
    assert(desc.Width == width);
    assert(desc.Height == height);
    assert(
        desc.Format ==
        DXGI_FORMAT_B8G8R8A8_UNORM);
}

}  // namespace

int main() {
    MfGuard mf;
    assert(SUCCEEDED(mf.Result()));

    auto device = CreateWarpDevice();

    SharedD3D11TexturePool pool(device);
    assert(SUCCEEDED(
        pool.Recreate(1280, 720)));

    const auto* slot = pool.Slot(0);
    assert(slot != nullptr);

    MftDxgiInputSampleFactory factory(
        device.Get());
    assert(factory.IsReady());

    ComPtr<IMFSample> sample;
    assert(SUCCEEDED(
        factory.CreateFromSharedHandle(
            slot->SharedHandle(),
            slot->Descriptor(),
            123'456,
            16'667,
            sample)));
    assert(sample != nullptr);

    LONGLONG time = 0;
    LONGLONG duration = 0;
    assert(SUCCEEDED(
        sample->GetSampleTime(&time)));
    assert(SUCCEEDED(
        sample->GetSampleDuration(
            &duration)));
    assert(time == 1'234'560);
    assert(duration == 166'670);

    ValidateDxgiBuffer(
        sample.Get(),
        1280,
        720);

    auto mismatched =
        slot->Descriptor();
    mismatched.width = 1920;

    ComPtr<IMFSample> invalid;
    assert(FAILED(
        factory.CreateFromSharedHandle(
            slot->SharedHandle(),
            mismatched,
            0,
            16'667,
            invalid)));
    assert(invalid == nullptr);

    assert(FAILED(
        factory.CreateFromSharedHandle(
            nullptr,
            slot->Descriptor(),
            0,
            16'667,
            invalid)));

    assert(FAILED(
        factory.CreateFromSharedHandle(
            slot->SharedHandle(),
            slot->Descriptor(),
            0,
            0,
            invalid)));

    SharedD3D11TexturePool
        recreated(device);
    assert(SUCCEEDED(
        recreated.Recreate(1920, 1080)));

    const auto* newSlot =
        recreated.Slot(0);
    assert(newSlot != nullptr);

    assert(SUCCEEDED(
        factory.CreateFromSharedHandle(
            newSlot->SharedHandle(),
            newSlot->Descriptor(),
            999,
            33'333,
            sample)));

    ValidateDxgiBuffer(
        sample.Get(),
        1920,
        1080);

    return 0;
}
