#define NOMINMAX

#include <Windows.h>
#include <d3d11_1.h>
#include <mfapi.h>
#include <mfidl.h>
#include <objbase.h>
#include <wrl/client.h>

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <limits>

#include "MftDxgiInputSampleFactory.h"
#include "SharedD3D11TexturePool.h"

using Microsoft::WRL::ComPtr;
using displaymesh::bridge::
    SharedD3D11TexturePool;
using displaymesh::media::
    MftDxgiInputSampleFactory;

namespace {

void Require(bool condition) {
    if (!condition) {
        std::cerr << "DisplayMesh DXGI input sample requirement failed\n";
        std::exit(EXIT_FAILURE);
    }
}

class ComGuard {
public:
    ComGuard() noexcept
        : result_(CoInitializeEx(
              nullptr,
              COINIT_MULTITHREADED)) {}

    ~ComGuard() {
        if (SUCCEEDED(result_)) {
            CoUninitialize();
        }
    }

    HRESULT Result() const noexcept {
        return result_;
    }

private:
    HRESULT result_{};
};

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

    Require(SUCCEEDED(result));
    Require(device != nullptr);
    return device;
}

void ValidateDxgiBuffer(
    IMFSample* sample,
    std::uint32_t width,
    std::uint32_t height) {
    Require(sample != nullptr);

    DWORD count = 0;
    Require(SUCCEEDED(
        sample->GetBufferCount(&count)));
    Require(count == 1);

    ComPtr<IMFMediaBuffer> buffer;
    Require(SUCCEEDED(
        sample->GetBufferByIndex(
            0,
            &buffer)));

    ComPtr<IMFDXGIBuffer> dxgiBuffer;
    Require(SUCCEEDED(
        buffer.As(&dxgiBuffer)));

    ComPtr<ID3D11Texture2D> texture;
    Require(SUCCEEDED(
        dxgiBuffer->GetResource(
            IID_PPV_ARGS(&texture))));
    Require(texture != nullptr);

    D3D11_TEXTURE2D_DESC desc{};
    texture->GetDesc(&desc);
    Require(desc.Width == width);
    Require(desc.Height == height);
    Require(
        desc.Format ==
        DXGI_FORMAT_B8G8R8A8_UNORM);
}

}  // namespace

int main() {
    ComGuard com;
    Require(SUCCEEDED(com.Result()));

    MfGuard mf;
    Require(SUCCEEDED(mf.Result()));

    auto device = CreateWarpDevice();

    SharedD3D11TexturePool pool(device);
    Require(SUCCEEDED(
        pool.Recreate(1280, 720)));

    const auto* slot = pool.Slot(0);
    Require(slot != nullptr);

    MftDxgiInputSampleFactory missingDevice(
        nullptr);
    Require(!missingDevice.IsReady());

    MftDxgiInputSampleFactory factory(
        device.Get());
    Require(factory.IsReady());

    ComPtr<IMFSample> sample;
    Require(SUCCEEDED(
        factory.CreateFromSharedHandle(
            slot->SharedHandle(),
            slot->Descriptor(),
            123'456,
            16'667,
            sample)));
    Require(sample != nullptr);

    LONGLONG time = 0;
    LONGLONG duration = 0;
    Require(SUCCEEDED(
        sample->GetSampleTime(&time)));
    Require(SUCCEEDED(
        sample->GetSampleDuration(
            &duration)));
    Require(time == 1'234'560);
    Require(duration == 166'670);

    ValidateDxgiBuffer(
        sample.Get(),
        1280,
        720);

    auto mismatched =
        slot->Descriptor();
    mismatched.width = 1920;

    ComPtr<IMFSample> invalid;
    Require(FAILED(
        factory.CreateFromSharedHandle(
            slot->SharedHandle(),
            mismatched,
            0,
            16'667,
            invalid)));
    Require(invalid == nullptr);

    Require(FAILED(
        factory.CreateFromSharedHandle(
            nullptr,
            slot->Descriptor(),
            0,
            16'667,
            invalid)));

    Require(FAILED(
        factory.CreateFromSharedHandle(
            slot->SharedHandle(),
            slot->Descriptor(),
            0,
            0,
            invalid)));

    Require(FAILED(
        missingDevice.CreateFromSharedHandle(
            slot->SharedHandle(),
            slot->Descriptor(),
            0,
            16'667,
            invalid)));

    const auto overflowingTimestamp =
        static_cast<std::uint64_t>(
            std::numeric_limits<LONGLONG>::max()) /
            10 + 1;
    Require(FAILED(
        factory.CreateFromSharedHandle(
            slot->SharedHandle(),
            slot->Descriptor(),
            overflowingTimestamp,
            16'667,
            invalid)));

    SharedD3D11TexturePool
        recreated(device);
    Require(SUCCEEDED(
        recreated.Recreate(1920, 1080)));

    const auto* newSlot =
        recreated.Slot(0);
    Require(newSlot != nullptr);

    Require(SUCCEEDED(
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
