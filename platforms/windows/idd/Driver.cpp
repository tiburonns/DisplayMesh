#include "Driver.h"
#include <algorithm>
#include <array>

using Microsoft::WRL::ComPtr;

namespace displaymesh::idd {

const std::array<ModeSpec, 5> kDisplayModes{{
    {1920, 1080, 60}, {1920, 1080, 120}, {2560, 1440, 60},
    {2560, 1440, 120}, {3840, 2160, 60},
}};

static const GUID kMonitorContainerId{
    0x6bb60ccf, 0x9fb5, 0x4301,
    {0xa8,0xdc,0x2e,0x65,0x5c,0x9d,0x75,0x44}
};

static void FillSignalInfo(DISPLAYCONFIG_VIDEO_SIGNAL_INFO& info,
    DWORD width, DWORD height, DWORD refreshHz, bool monitorMode) noexcept {
    info.totalSize.cx = info.activeSize.cx = width;
    info.totalSize.cy = info.activeSize.cy = height;
    info.vSyncFreq.Numerator = refreshHz;
    info.vSyncFreq.Denominator = 1;
    info.hSyncFreq.Numerator = refreshHz * height;
    info.hSyncFreq.Denominator = 1;
    info.pixelRate = static_cast<UINT64>(width) * height * refreshHz;
    info.scanLineOrdering = DISPLAYCONFIG_SCANLINE_ORDERING_PROGRESSIVE;
    info.AdditionalSignalInfo.vSyncFreqDivider = monitorMode ? 0 : 1;
    info.AdditionalSignalInfo.videoStandard = 255;
}

static IDDCX_MONITOR_MODE MakeMonitorMode(const ModeSpec& spec) noexcept {
    IDDCX_MONITOR_MODE mode{};
    mode.Size = sizeof(mode);
    mode.Origin = IDDCX_MONITOR_MODE_ORIGIN_DRIVER;
    FillSignalInfo(mode.MonitorVideoSignalInfo,
        spec.width, spec.height, spec.refreshHz, true);
    return mode;
}

static IDDCX_TARGET_MODE MakeTargetMode(const ModeSpec& spec) noexcept {
    IDDCX_TARGET_MODE mode{};
    mode.Size = sizeof(mode);
    FillSignalInfo(mode.TargetVideoSignalInfo.targetVideoSignalInfo,
        spec.width, spec.height, spec.refreshHz, false);
    return mode;
}

static void CleanupDeviceContext(WDFOBJECT object) noexcept {
    auto* wrapper = GetDisplayMeshDeviceContext(object);
    delete wrapper->ptr;
    wrapper->ptr = nullptr;
}

static void CleanupMonitorContext(WDFOBJECT object) noexcept {
    auto* wrapper = GetDisplayMeshMonitorContext(object);
    delete wrapper->ptr;
    wrapper->ptr = nullptr;
}

RenderDevice::RenderDevice(LUID value) noexcept : adapterLuid(value) {}

HRESULT RenderDevice::Initialize() noexcept {
    HRESULT hr = CreateDXGIFactory2(0, IID_PPV_ARGS(&factory));
    if (FAILED(hr)) return hr;
    hr = factory->EnumAdapterByLuid(adapterLuid, IID_PPV_ARGS(&adapter));
    if (FAILED(hr)) return hr;
    return D3D11CreateDevice(adapter.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
        &device, nullptr, &context);
}

SwapChainProcessor::SwapChainProcessor(IDDCX_SWAPCHAIN swapChain,
    std::shared_ptr<RenderDevice> renderDevice, HANDLE nextSurfaceAvailable)
    : swapChain_(swapChain), renderDevice_(std::move(renderDevice)),
      nextSurfaceAvailable_(nextSurfaceAvailable) {
    stopEvent_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    thread_ = CreateThread(nullptr, 0, ThreadEntry, this, 0, nullptr);
}

SwapChainProcessor::~SwapChainProcessor() {
    if (stopEvent_) SetEvent(stopEvent_);
    if (thread_) { WaitForSingleObject(thread_, INFINITE); CloseHandle(thread_); }
    if (stopEvent_) CloseHandle(stopEvent_);
}

DWORD WINAPI SwapChainProcessor::ThreadEntry(void* context) noexcept {
    static_cast<SwapChainProcessor*>(context)->Run();
    return 0;
}

void SwapChainProcessor::Run() noexcept {
    ComPtr<IDXGIDevice> dxgiDevice;
    if (FAILED(renderDevice_->device.As(&dxgiDevice))) {
        WdfObjectDelete(reinterpret_cast<WDFOBJECT>(swapChain_));
        swapChain_ = nullptr;
        return;
    }

    IDARG_IN_SWAPCHAINSETDEVICE setDevice{};
    setDevice.pDevice = dxgiDevice.Get();
    if (FAILED(IddCxSwapChainSetDevice(swapChain_, &setDevice))) {
        WdfObjectDelete(reinterpret_cast<WDFOBJECT>(swapChain_));
        swapChain_ = nullptr;
        return;
    }

    HANDLE waits[] = {nextSurfaceAvailable_, stopEvent_};

    for (;;) {
        IDARG_OUT_RELEASEANDACQUIREBUFFER buffer{};
        HRESULT hr = IddCxSwapChainReleaseAndAcquireBuffer(swapChain_, &buffer);
        if (hr == E_PENDING) {
            DWORD wait = WaitForMultipleObjects(ARRAYSIZE(waits), waits, FALSE, 16);
            if (wait == WAIT_OBJECT_0 || wait == WAIT_TIMEOUT) continue;
            break;
        }
        if (FAILED(hr)) break;

        ComPtr<IDXGIResource> surface;
        surface.Attach(buffer.MetaData.pSurface);
        ComPtr<ID3D11Texture2D> texture;
        surface.As(&texture);

        // M2: pass this GPU texture to the Media Foundation encoder.
        // The production path must not map normal frames back to CPU memory.
        texture.Reset();
        surface.Reset();

        if (FAILED(IddCxSwapChainFinishedProcessingFrame(swapChain_))) break;
    }

    if (swapChain_) {
        WdfObjectDelete(reinterpret_cast<WDFOBJECT>(swapChain_));
        swapChain_ = nullptr;
    }
}

MonitorContext::MonitorContext(IDDCX_MONITOR monitor) noexcept : monitor_(monitor) {}
MonitorContext::~MonitorContext() { processor_.reset(); }

void MonitorContext::AssignSwapChain(IDDCX_SWAPCHAIN swapChain,
    LUID renderAdapter, HANDLE nextSurfaceAvailable) noexcept {
    processor_.reset();
    auto device = std::make_shared<RenderDevice>(renderAdapter);
    if (FAILED(device->Initialize())) {
        WdfObjectDelete(reinterpret_cast<WDFOBJECT>(swapChain));
        return;
    }
    processor_ = std::make_unique<SwapChainProcessor>(
        swapChain, std::move(device), nextSurfaceAvailable);
}

void MonitorContext::UnassignSwapChain() noexcept { processor_.reset(); }

DeviceContext::DeviceContext(WDFDEVICE device) noexcept : device_(device) {}
DeviceContext::~DeviceContext() { DisconnectMonitor(); }

NTSTATUS DeviceContext::InitializeAdapter() noexcept {
    IDDCX_ADAPTER_CAPS caps{};
    caps.Size = sizeof(caps);
    caps.MaxMonitorsSupported = 1;
    caps.EndPointDiagnostics.Size = sizeof(caps.EndPointDiagnostics);
    caps.EndPointDiagnostics.GammaSupport = IDDCX_FEATURE_IMPLEMENTATION_NONE;
    caps.EndPointDiagnostics.TransmissionType = IDDCX_TRANSMISSION_TYPE_WIRED_OTHER;
    caps.EndPointDiagnostics.pEndPointFriendlyName = L"DisplayMesh Virtual Display";
    caps.EndPointDiagnostics.pEndPointManufacturerName = L"DisplayMesh";
    caps.EndPointDiagnostics.pEndPointModelName = L"DisplayMesh Receiver";

    IDDCX_ENDPOINT_VERSION version{};
    version.Size = sizeof(version);
    version.MajorVer = 0;
    version.MinorVer = 2;
    caps.EndPointDiagnostics.pFirmwareVersion = &version;
    caps.EndPointDiagnostics.pHardwareVersion = &version;

    WDF_OBJECT_ATTRIBUTES attrs;
    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&attrs, DeviceContextRef);

    IDARG_IN_ADAPTER_INIT input{};
    input.WdfDevice = device_;
    input.pCaps = &caps;
    input.ObjectAttributes = &attrs;
    IDARG_OUT_ADAPTER_INIT output{};

    NTSTATUS status = IddCxAdapterInitAsync(&input, &output);
    if (NT_SUCCESS(status)) {
        adapter_ = output.AdapterObject;
        GetDisplayMeshDeviceContext(adapter_)->ptr = this;
    }
    return status;
}

NTSTATUS DeviceContext::ConnectMonitor() noexcept {
    if (!adapter_) return STATUS_INVALID_DEVICE_STATE;
    if (monitor_) return STATUS_SUCCESS;

    IDDCX_MONITOR_INFO info{};
    info.Size = sizeof(info);
    info.MonitorType = DISPLAYCONFIG_OUTPUT_TECHNOLOGY_OTHER;
    info.ConnectorIndex = 0;
    info.MonitorContainerId = kMonitorContainerId;
    info.MonitorDescription.Size = sizeof(info.MonitorDescription);
    info.MonitorDescription.Type = IDDCX_MONITOR_DESCRIPTION_TYPE_EDID;

    WDF_OBJECT_ATTRIBUTES attrs;
    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&attrs, MonitorContextRef);
    attrs.EvtCleanupCallback = CleanupMonitorContext;

    IDARG_IN_MONITORCREATE input{};
    input.ObjectAttributes = &attrs;
    input.pMonitorInfo = &info;
    IDARG_OUT_MONITORCREATE output{};

    NTSTATUS status = IddCxMonitorCreate(adapter_, &input, &output);
    if (!NT_SUCCESS(status)) return status;

    monitor_ = output.MonitorObject;
    GetDisplayMeshMonitorContext(monitor_)->ptr = new MonitorContext(monitor_);

    IDARG_OUT_MONITORARRIVAL arrival{};
    status = IddCxMonitorArrival(monitor_, &arrival);
    if (!NT_SUCCESS(status)) {
        WdfObjectDelete(reinterpret_cast<WDFOBJECT>(monitor_));
        monitor_ = nullptr;
    }
    return status;
}

void DeviceContext::DisconnectMonitor() noexcept {
    if (!monitor_) return;
    IddCxMonitorDeparture(monitor_);
    monitor_ = nullptr;
}

}  // namespace displaymesh::idd

extern "C" DRIVER_INITIALIZE DriverEntry;
EVT_WDF_DRIVER_DEVICE_ADD DisplayMeshDeviceAdd;
EVT_WDF_DEVICE_D0_ENTRY DisplayMeshDeviceD0Entry;
EVT_IDD_CX_ADAPTER_INIT_FINISHED DisplayMeshAdapterInitFinished;
EVT_IDD_CX_ADAPTER_COMMIT_MODES DisplayMeshAdapterCommitModes;
EVT_IDD_CX_PARSE_MONITOR_DESCRIPTION DisplayMeshParseMonitorDescription;
EVT_IDD_CX_MONITOR_GET_DEFAULT_DESCRIPTION_MODES DisplayMeshGetDefaultMonitorModes;
EVT_IDD_CX_MONITOR_QUERY_TARGET_MODES DisplayMeshQueryTargetModes;
EVT_IDD_CX_MONITOR_ASSIGN_SWAPCHAIN DisplayMeshAssignSwapChain;
EVT_IDD_CX_MONITOR_UNASSIGN_SWAPCHAIN DisplayMeshUnassignSwapChain;

extern "C" BOOL WINAPI DllMain(HINSTANCE, DWORD, LPVOID) { return TRUE; }

extern "C" NTSTATUS DriverEntry(PDRIVER_OBJECT object, PUNICODE_STRING path) {
    WDF_OBJECT_ATTRIBUTES attrs; WDF_OBJECT_ATTRIBUTES_INIT(&attrs);
    WDF_DRIVER_CONFIG config; WDF_DRIVER_CONFIG_INIT(&config, DisplayMeshDeviceAdd);
    return WdfDriverCreate(object, path, &attrs, &config, WDF_NO_HANDLE);
}

NTSTATUS DisplayMeshDeviceAdd(WDFDRIVER driver, PWDFDEVICE_INIT init) {
    UNREFERENCED_PARAMETER(driver);
    WDF_PNPPOWER_EVENT_CALLBACKS power; WDF_PNPPOWER_EVENT_CALLBACKS_INIT(&power);
    power.EvtDeviceD0Entry = DisplayMeshDeviceD0Entry;
    WdfDeviceInitSetPnpPowerEventCallbacks(init, &power);

    IDD_CX_CLIENT_CONFIG config; IDD_CX_CLIENT_CONFIG_INIT(&config);
    config.EvtIddCxAdapterInitFinished = DisplayMeshAdapterInitFinished;
    config.EvtIddCxParseMonitorDescription = DisplayMeshParseMonitorDescription;
    config.EvtIddCxMonitorGetDefaultDescriptionModes = DisplayMeshGetDefaultMonitorModes;
    config.EvtIddCxMonitorQueryTargetModes = DisplayMeshQueryTargetModes;
    config.EvtIddCxAdapterCommitModes = DisplayMeshAdapterCommitModes;
    config.EvtIddCxMonitorAssignSwapChain = DisplayMeshAssignSwapChain;
    config.EvtIddCxMonitorUnassignSwapChain = DisplayMeshUnassignSwapChain;

    NTSTATUS status = IddCxDeviceInitConfig(init, &config);
    if (!NT_SUCCESS(status)) return status;

    WDF_OBJECT_ATTRIBUTES attrs;
    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&attrs, displaymesh::idd::DeviceContextRef);
    attrs.EvtCleanupCallback = [](WDFOBJECT object) {
        auto* wrapper = displaymesh::idd::GetDisplayMeshDeviceContext(object);
        delete wrapper->ptr;
        wrapper->ptr = nullptr;
    };

    WDFDEVICE device{};
    status = WdfDeviceCreate(&init, &attrs, &device);
    if (!NT_SUCCESS(status)) return status;
    status = IddCxDeviceInitialize(device);
    if (!NT_SUCCESS(status)) return status;

    displaymesh::idd::GetDisplayMeshDeviceContext(device)->ptr =
        new displaymesh::idd::DeviceContext(device);
    return STATUS_SUCCESS;
}

NTSTATUS DisplayMeshDeviceD0Entry(WDFDEVICE device, WDF_POWER_DEVICE_STATE previous) {
    UNREFERENCED_PARAMETER(previous);
    auto* wrapper = displaymesh::idd::GetDisplayMeshDeviceContext(device);
    return wrapper && wrapper->ptr ? wrapper->ptr->InitializeAdapter()
        : STATUS_INVALID_DEVICE_STATE;
}

NTSTATUS DisplayMeshAdapterInitFinished(IDDCX_ADAPTER adapter,
    const IDARG_IN_ADAPTER_INIT_FINISHED* input) {
    if (!NT_SUCCESS(input->AdapterInitStatus)) return STATUS_SUCCESS;
    auto* wrapper = displaymesh::idd::GetDisplayMeshDeviceContext(adapter);
    return wrapper && wrapper->ptr ? wrapper->ptr->ConnectMonitor()
        : STATUS_INVALID_DEVICE_STATE;
}

NTSTATUS DisplayMeshAdapterCommitModes(IDDCX_ADAPTER adapter,
    const IDARG_IN_COMMITMODES* input) {
    UNREFERENCED_PARAMETER(adapter); UNREFERENCED_PARAMETER(input);
    return STATUS_SUCCESS;
}

NTSTATUS DisplayMeshParseMonitorDescription(
    const IDARG_IN_PARSEMONITORDESCRIPTION* input,
    IDARG_OUT_PARSEMONITORDESCRIPTION* output) {
    UNREFERENCED_PARAMETER(input);
    output->MonitorModeBufferOutputCount = 0;
    output->PreferredMonitorModeIdx = 0;
    return STATUS_NOT_SUPPORTED;
}

NTSTATUS DisplayMeshGetDefaultMonitorModes(IDDCX_MONITOR monitor,
    const IDARG_IN_GETDEFAULTDESCRIPTIONMODES* input,
    IDARG_OUT_GETDEFAULTDESCRIPTIONMODES* output) {
    UNREFERENCED_PARAMETER(monitor);
    output->DefaultMonitorModeBufferOutputCount =
        static_cast<UINT>(displaymesh::idd::kDisplayModes.size());
    output->PreferredMonitorModeIdx = 2;
    if (input->DefaultMonitorModeBufferInputCount == 0) return STATUS_SUCCESS;
    if (input->DefaultMonitorModeBufferInputCount <
        displaymesh::idd::kDisplayModes.size()) return STATUS_BUFFER_TOO_SMALL;
    std::transform(displaymesh::idd::kDisplayModes.begin(),
        displaymesh::idd::kDisplayModes.end(), input->pDefaultMonitorModes,
        [](const auto& spec) { return displaymesh::idd::MakeMonitorMode(spec); });
    return STATUS_SUCCESS;
}

NTSTATUS DisplayMeshQueryTargetModes(IDDCX_MONITOR monitor,
    const IDARG_IN_QUERYTARGETMODES* input, IDARG_OUT_QUERYTARGETMODES* output) {
    UNREFERENCED_PARAMETER(monitor);
    output->TargetModeBufferOutputCount =
        static_cast<UINT>(displaymesh::idd::kDisplayModes.size());
    if (input->TargetModeBufferInputCount == 0) return STATUS_SUCCESS;
    if (input->TargetModeBufferInputCount <
        displaymesh::idd::kDisplayModes.size()) return STATUS_BUFFER_TOO_SMALL;
    std::transform(displaymesh::idd::kDisplayModes.begin(),
        displaymesh::idd::kDisplayModes.end(), input->pTargetModes,
        [](const auto& spec) { return displaymesh::idd::MakeTargetMode(spec); });
    return STATUS_SUCCESS;
}

NTSTATUS DisplayMeshAssignSwapChain(IDDCX_MONITOR monitor,
    const IDARG_IN_SETSWAPCHAIN* input) {
    auto* wrapper = displaymesh::idd::GetDisplayMeshMonitorContext(monitor);
    if (!wrapper || !wrapper->ptr) return STATUS_INVALID_DEVICE_STATE;
    wrapper->ptr->AssignSwapChain(input->hSwapChain,
        input->RenderAdapterLuid, input->hNextSurfaceAvailable);
    return STATUS_SUCCESS;
}

NTSTATUS DisplayMeshUnassignSwapChain(IDDCX_MONITOR monitor) {
    auto* wrapper = displaymesh::idd::GetDisplayMeshMonitorContext(monitor);
    if (wrapper && wrapper->ptr) wrapper->ptr->UnassignSwapChain();
    return STATUS_SUCCESS;
}
