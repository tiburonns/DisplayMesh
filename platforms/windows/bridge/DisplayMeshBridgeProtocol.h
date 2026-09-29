#pragma once

#define NOMINMAX
#include <Windows.h>
#include <winioctl.h>

#include <cstdint>

namespace displaymesh::bridge {

inline constexpr std::uint32_t kProtocolVersion = 1;

inline constexpr GUID kDeviceInterfaceGuid{
    0xbeb3db53,
    0x1256,
    0x4df0,
    {0x9a, 0x73, 0x93, 0x31, 0x9b, 0x31, 0x78, 0x6c}
};

inline constexpr ULONG kIoctlQueryStatus =
    CTL_CODE(
        FILE_DEVICE_UNKNOWN,
        0x800,
        METHOD_BUFFERED,
        FILE_READ_DATA);

inline constexpr ULONG kIoctlSetReceiverMode =
    CTL_CODE(
        FILE_DEVICE_UNKNOWN,
        0x801,
        METHOD_BUFFERED,
        FILE_WRITE_DATA);

struct ReceiverModeRequest {
    std::uint32_t protocolVersion{kProtocolVersion};
    std::uint32_t width{};
    std::uint32_t height{};
    std::uint32_t refreshHz{};
};

struct DriverStatus {
    std::uint32_t protocolVersion{kProtocolVersion};
    std::uint32_t adapterReady{};
    std::uint32_t monitorConnected{};
    std::uint32_t requestedWidth{};
    std::uint32_t requestedHeight{};
    std::uint32_t requestedRefreshHz{};
};

static_assert(sizeof(ReceiverModeRequest) == 16);
static_assert(sizeof(DriverStatus) == 24);

}  // namespace displaymesh::bridge
