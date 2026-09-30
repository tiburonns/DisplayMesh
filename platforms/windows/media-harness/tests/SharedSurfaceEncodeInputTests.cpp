#define NOMINMAX

#include <Windows.h>
#include <d3d11_1.h>
#include <mfapi.h>
#include <objbase.h>
#include <wrl/client.h>

#include <cassert>

#include "SharedSurfaceEncodeInput.h"

using Microsoft::WRL::ComPtr;
using displaymesh::bridge::
    SharedD3D11TexturePool;
using displaymesh::media::
    EncodeWorkItem;
using displaymesh::media::
    MftDxgiInputSampleFactory;
using displaymesh::media::
    SharedSurfaceEncodeInput;

namespace {

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

    assert(SUCCEEDED(
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
            &context)));

    return device;
}

EncodeWorkItem WorkForSlot(
    const SharedD3D11TexturePool& pool,
    std::uint32_t slotIndex,
    std::uint64_t sequence) {
    const auto* slot = pool.Slot(slotIndex);
    assert(slot != nullptr);

    bridge::FrameAnnouncement frame{};
    frame.sequence = sequence;
    frame.timestampMicros =
        sequence * 1'000;
    frame.surfaceGeneration =
        slot->Descriptor().generation;
    frame.slotIndex = slotIndex;
    frame.width =
        slot->Descriptor().width;
    frame.height =
        slot->Descriptor().height;

    return EncodeWorkItem::FromFrame(
        frame,
        16'667);
}

}  // namespace

int main() {
    ComGuard com;
    assert(SUCCEEDED(com.Result()));

    MfGuard mf;
    assert(SUCCEEDED(mf.Result()));

    auto device = CreateWarpDevice();
    assert(device != nullptr);

    SharedD3D11TexturePool pool(device);
    assert(SUCCEEDED(
        pool.Recreate(1920, 1080)));

    MftDxgiInputSampleFactory
        factory(device.Get());
    assert(factory.IsReady());

    SharedSurfaceEncodeInput bridge(
        pool,
        factory);

    const auto current =
        WorkForSlot(pool, 1, 10);

    ComPtr<IMFSample> sample;
    assert(SUCCEEDED(
        bridge.CreateSample(
            current,
            sample)));
    assert(sample != nullptr);

    LONGLONG time = 0;
    LONGLONG duration = 0;
    assert(SUCCEEDED(
        sample->GetSampleTime(&time)));
    assert(SUCCEEDED(
        sample->GetSampleDuration(
            &duration)));
    assert(time == 100'000);
    assert(duration == 166'670);

    const auto stale = current;

    assert(SUCCEEDED(
        pool.Recreate(2560, 1440)));

    sample.Reset();
    assert(FAILED(
        bridge.CreateSample(
            stale,
            sample)));
    assert(sample == nullptr);

    const auto resized =
        WorkForSlot(pool, 1, 11);

    assert(SUCCEEDED(
        bridge.CreateSample(
            resized,
            sample)));
    assert(sample != nullptr);

    auto wrongSlot = resized;
    wrongSlot.slotIndex = 2;
    sample.Reset();
    assert(FAILED(
        bridge.CreateSample(
            wrongSlot,
            sample)));
    assert(sample == nullptr);

    auto wrongGeometry = resized;
    wrongGeometry.width = 1920;
    assert(FAILED(
        bridge.CreateSample(
            wrongGeometry,
            sample)));

    auto noDuration = resized;
    noDuration.durationMicros = 0;
    assert(FAILED(
        bridge.CreateSample(
            noDuration,
            sample)));

    return 0;
}
