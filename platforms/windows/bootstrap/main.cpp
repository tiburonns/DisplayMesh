#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <swdevice.h>

#include <atomic>
#include <iostream>
#include <string>

namespace
{
std::atomic<HRESULT> gCreateResult{E_PENDING};
std::wstring gInstanceId;

void CALLBACK CreationCallback(
    HSWDEVICE,
    HRESULT createResult,
    PVOID context,
    PCWSTR deviceInstanceId)
{
    gCreateResult.store(createResult);

    if (deviceInstanceId != nullptr)
    {
        gInstanceId = deviceInstanceId;
    }

    if (context != nullptr)
    {
        SetEvent(static_cast<HANDLE>(context));
    }
}
} // namespace

int wmain()
{
    HANDLE createdEvent = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (createdEvent == nullptr)
    {
        std::wcerr << L"CreateEventW failed: " << GetLastError() << L"\n";
        return 1;
    }

    SW_DEVICE_CREATE_INFO createInfo{};
    createInfo.cbSize = sizeof(createInfo);
    createInfo.pszInstanceId = L"DisplayMeshIdd";
    createInfo.pszzHardwareIds = L"DisplayMeshIdd\0";
    createInfo.pszzCompatibleIds = L"DisplayMeshIdd\0";
    createInfo.pszDeviceDescription = L"DisplayMesh Virtual Display Adapter";
    createInfo.CapabilityFlags =
        SWDeviceCapabilitiesRemovable |
        SWDeviceCapabilitiesSilentInstall |
        SWDeviceCapabilitiesDriverRequired;

    HSWDEVICE softwareDevice = nullptr;

    const HRESULT hr = SwDeviceCreate(
        L"DisplayMesh",
        L"HTREE\\ROOT\\0",
        &createInfo,
        0,
        nullptr,
        CreationCallback,
        createdEvent,
        &softwareDevice);

    if (FAILED(hr))
    {
        std::wcerr << L"SwDeviceCreate failed: 0x"
                   << std::hex << static_cast<unsigned long>(hr) << L"\n";
        CloseHandle(createdEvent);
        return 2;
    }

    const DWORD waitResult = WaitForSingleObject(createdEvent, 15000);
    CloseHandle(createdEvent);

    if (waitResult != WAIT_OBJECT_0)
    {
        std::wcerr << L"Timed out while Windows enumerated the software device.\n";
        SwDeviceClose(softwareDevice);
        return 3;
    }

    const HRESULT enumerationResult = gCreateResult.load();
    if (FAILED(enumerationResult))
    {
        std::wcerr << L"PnP enumeration failed: 0x"
                   << std::hex
                   << static_cast<unsigned long>(enumerationResult)
                   << L"\n";
        SwDeviceClose(softwareDevice);
        return 4;
    }

    std::wcout << L"DisplayMesh software device created.\n";
    if (!gInstanceId.empty())
    {
        std::wcout << L"Instance: " << gInstanceId << L"\n";
    }

    std::wcout
        << L"The DisplayMesh IddCx driver package must already be installed "
           L"for this software device to become a virtual display adapter.\n"
        << L"Press Enter to remove the software device.\n";

    std::wstring line;
    std::getline(std::wcin, line);

    SwDeviceClose(softwareDevice);
    std::wcout << L"DisplayMesh software device removed.\n";
    return 0;
}
