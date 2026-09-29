#pragma once
#define NOMINMAX
#include <Windows.h>
#include <wudfwdm.h>
#include <wdf.h>
#include <iddcx.h>
#include <d3d11_2.h>
#include <dxgi1_5.h>
#include <wrl.h>
#include <array>
#include <memory>

namespace displaymesh::idd {

struct ModeSpec { DWORD width; DWORD height; DWORD refreshHz; };
extern const std::array<ModeSpec, 5> kDisplayModes;

struct RenderDevice {
    explicit RenderDevice(LUID adapterLuid) noexcept;
    HRESULT Initialize() noexcept;
    LUID adapterLuid{};
    Microsoft::WRL::ComPtr<IDXGIFactory5> factory;
    Microsoft::WRL::ComPtr<IDXGIAdapter1> adapter;
    Microsoft::WRL::ComPtr<ID3D11Device> device;
    Microsoft::WRL::ComPtr<ID3D11DeviceContext> context;
};

class SwapChainProcessor {
public:
    SwapChainProcessor(IDDCX_SWAPCHAIN swapChain,
        std::shared_ptr<RenderDevice> renderDevice,
        HANDLE nextSurfaceAvailable);
    ~SwapChainProcessor();
    SwapChainProcessor(const SwapChainProcessor&) = delete;
    SwapChainProcessor& operator=(const SwapChainProcessor&) = delete;
private:
    static DWORD WINAPI ThreadEntry(void* context) noexcept;
    void Run() noexcept;
    IDDCX_SWAPCHAIN swapChain_{};
    std::shared_ptr<RenderDevice> renderDevice_;
    HANDLE nextSurfaceAvailable_{};
    HANDLE stopEvent_{};
    HANDLE thread_{};
};

class MonitorContext {
public:
    explicit MonitorContext(IDDCX_MONITOR monitor) noexcept;
    ~MonitorContext();
    void AssignSwapChain(IDDCX_SWAPCHAIN swapChain, LUID renderAdapter,
        HANDLE nextSurfaceAvailable) noexcept;
    void UnassignSwapChain() noexcept;
private:
    IDDCX_MONITOR monitor_{};
    std::unique_ptr<SwapChainProcessor> processor_;
};

class DeviceContext {
public:
    explicit DeviceContext(WDFDEVICE device) noexcept;
    ~DeviceContext();
    NTSTATUS InitializeAdapter() noexcept;
    NTSTATUS ConnectMonitor() noexcept;
    void DisconnectMonitor() noexcept;
private:
    WDFDEVICE device_{};
    IDDCX_ADAPTER adapter_{};
    IDDCX_MONITOR monitor_{};
};

struct DeviceContextRef { DeviceContext* ptr{}; };
struct MonitorContextRef { MonitorContext* ptr{}; };

WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DeviceContextRef, GetDisplayMeshDeviceContext);
WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(MonitorContextRef, GetDisplayMeshMonitorContext);


}  // namespace displaymesh::idd
