#pragma once

#define NOMINMAX
#include <Windows.h>
#include <d3d11_2.h>
#include <mfidl.h>
#include <wrl.h>

#include <cstdint>
#include <string>

namespace displaymesh::media {

struct ProbeConfig {
    std::uint32_t width{1920};
    std::uint32_t height{1080};
    std::uint32_t framesPerSecond{60};
    std::uint32_t bitrateBitsPerSecond{24'000'000};
};

struct ProbeReport {
    std::wstring encoderName;
    bool hardwareEncoderFound{};
    bool asynchronous{};
    bool d3d11Aware{};
    bool lowLatencyAccepted{};
    bool gpuBgraToNv12Ready{};
    bool dxgiSampleReady{};
};

class WindowsMediaProbe {
public:
    HRESULT Run(
        const ProbeConfig& config,
        ProbeReport& report) noexcept;

private:
    HRESULT CreateDevice() noexcept;
    HRESULT CreateGpuConversionSurfaces(
        const ProbeConfig& config,
        Microsoft::WRL::ComPtr<ID3D11Texture2D>& bgra,
        Microsoft::WRL::ComPtr<ID3D11Texture2D>& nv12) noexcept;
    HRESULT ConvertBgraToNv12(
        const ProbeConfig& config,
        ID3D11Texture2D* bgra,
        ID3D11Texture2D* nv12) noexcept;
    HRESULT CreateDeviceManager() noexcept;
    HRESULT ActivateHardwareH264Encoder(
        const ProbeConfig& config,
        ProbeReport& report) noexcept;
    HRESULT CreateDxgiSample(
        ID3D11Texture2D* nv12,
        const ProbeConfig& config) noexcept;

    Microsoft::WRL::ComPtr<ID3D11Device> device_;
    Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
    Microsoft::WRL::ComPtr<IMFDXGIDeviceManager> deviceManager_;
    Microsoft::WRL::ComPtr<IMFTransform> encoder_;
    UINT deviceManagerResetToken_{};
};

}  // namespace displaymesh::media
