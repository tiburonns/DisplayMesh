#define NOMINMAX
#include <Windows.h>
#include <SetupAPI.h>

#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "../bridge/DisplayMeshBridgeProtocol.h"

namespace {

class DeviceHandle {
public:
    ~DeviceHandle() {
        if (handle_ != INVALID_HANDLE_VALUE) {
            CloseHandle(handle_);
        }
    }

    HANDLE* Out() noexcept { return &handle_; }
    HANDLE Get() const noexcept { return handle_; }

private:
    HANDLE handle_{INVALID_HANDLE_VALUE};
};

std::wstring FindDisplayMeshDevicePath() {
    HDEVINFO info =
        SetupDiGetClassDevsW(
            &displaymesh::bridge::
                kDeviceInterfaceGuid,
            nullptr,
            nullptr,
            DIGCF_PRESENT |
                DIGCF_DEVICEINTERFACE);

    if (info == INVALID_HANDLE_VALUE) {
        return {};
    }

    SP_DEVICE_INTERFACE_DATA interfaceData{};
    interfaceData.cbSize =
        sizeof(interfaceData);

    if (!SetupDiEnumDeviceInterfaces(
            info,
            nullptr,
            &displaymesh::bridge::
                kDeviceInterfaceGuid,
            0,
            &interfaceData)) {
        SetupDiDestroyDeviceInfoList(info);
        return {};
    }

    DWORD required = 0;
    SetupDiGetDeviceInterfaceDetailW(
        info,
        &interfaceData,
        nullptr,
        0,
        &required,
        nullptr);

    if (required == 0) {
        SetupDiDestroyDeviceInfoList(info);
        return {};
    }

    std::vector<std::byte> storage(required);
    auto* detail =
        reinterpret_cast<
            SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(
                storage.data());
    detail->cbSize =
        sizeof(
            SP_DEVICE_INTERFACE_DETAIL_DATA_W);

    if (!SetupDiGetDeviceInterfaceDetailW(
            info,
            &interfaceData,
            detail,
            required,
            nullptr,
            nullptr)) {
        SetupDiDestroyDeviceInfoList(info);
        return {};
    }

    std::wstring path =
        detail->DevicePath;

    SetupDiDestroyDeviceInfoList(info);
    return path;
}

HANDLE OpenDisplayMeshDevice(
    const std::wstring& path) {
    return CreateFileW(
        path.c_str(),
        GENERIC_READ | GENERIC_WRITE,
        FILE_SHARE_READ |
            FILE_SHARE_WRITE,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        nullptr);
}

bool QueryStatus(
    HANDLE device,
    displaymesh::bridge::DriverStatus&
        status) {
    DWORD bytesReturned = 0;

    return DeviceIoControl(
        device,
        displaymesh::bridge::
            kIoctlQueryStatus,
        nullptr,
        0,
        &status,
        sizeof(status),
        &bytesReturned,
        nullptr) &&
        bytesReturned == sizeof(status);
}

bool SetMode(
    HANDLE device,
    std::uint32_t width,
    std::uint32_t height,
    std::uint32_t refreshHz) {
    displaymesh::bridge::
        ReceiverModeRequest request{};
    request.width = width;
    request.height = height;
    request.refreshHz = refreshHz;

    DWORD bytesReturned = 0;

    return DeviceIoControl(
        device,
        displaymesh::bridge::
            kIoctlSetReceiverMode,
        &request,
        sizeof(request),
        nullptr,
        0,
        &bytesReturned,
        nullptr);
}

void PrintStatus(
    const displaymesh::bridge::
        DriverStatus& status) {
    std::wcout
        << L"Protocol: "
        << status.protocolVersion
        << L"\nAdapter ready: "
        << (status.adapterReady
                ? L"yes"
                : L"no")
        << L"\nMonitor connected: "
        << (status.monitorConnected
                ? L"yes"
                : L"no")
        << L"\nRequested mode: "
        << status.requestedWidth
        << L"x"
        << status.requestedHeight
        << L" @ "
        << status.requestedRefreshHz
        << L" Hz\n";
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    const std::wstring path =
        FindDisplayMeshDevicePath();

    if (path.empty()) {
        std::wcerr
            << L"DisplayMesh driver interface "
               L"was not found.\n";
        return 1;
    }

    const HANDLE device =
        OpenDisplayMeshDevice(path);

    if (device == INVALID_HANDLE_VALUE) {
        std::wcerr
            << L"Could not open DisplayMesh "
               L"driver interface. Win32 error "
            << GetLastError()
            << L"\n";
        return 2;
    }

    if (argc == 5 &&
        std::wstring(argv[1]) ==
            L"--mode") {
        try {
            const auto width =
                static_cast<std::uint32_t>(
                    std::stoul(argv[2]));
            const auto height =
                static_cast<std::uint32_t>(
                    std::stoul(argv[3]));
            const auto refresh =
                static_cast<std::uint32_t>(
                    std::stoul(argv[4]));

            if (!SetMode(
                    device,
                    width,
                    height,
                    refresh)) {
                std::wcerr
                    << L"Set mode failed. "
                       L"Win32 error "
                    << GetLastError()
                    << L"\n";
                CloseHandle(device);
                return 3;
            }
        } catch (...) {
            CloseHandle(device);
            return 4;
        }
    } else if (argc != 1) {
        std::wcerr
            << L"Usage: displaymesh-bridge-probe "
               L"[--mode width height refresh]\n";
        CloseHandle(device);
        return 5;
    }

    displaymesh::bridge::DriverStatus status{};
    if (!QueryStatus(
            device,
            status)) {
        std::wcerr
            << L"Status query failed. "
               L"Win32 error "
            << GetLastError()
            << L"\n";
        CloseHandle(device);
        return 6;
    }

    PrintStatus(status);
    CloseHandle(device);
    return 0;
}
