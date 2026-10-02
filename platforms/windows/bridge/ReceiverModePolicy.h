#pragma once

#include "DisplayMeshBridgeProtocol.h"

#include <cstdint>
#include <optional>

namespace displaymesh::bridge {

inline constexpr std::uint32_t kMinimumReceiverWidth = 640;
inline constexpr std::uint32_t kMinimumReceiverHeight = 480;
inline constexpr std::uint32_t kMaximumReceiverDimension = 8192;
inline constexpr std::uint32_t kMinimumReceiverRefreshHz = 30;
inline constexpr std::uint32_t kMaximumReceiverRefreshHz = 240;

inline std::optional<ReceiverModeRequest>
NormalizeReceiverMode(
    const ReceiverModeRequest& request) noexcept {
    if (request.protocolVersion != kProtocolVersion ||
        request.width < kMinimumReceiverWidth ||
        request.height < kMinimumReceiverHeight ||
        request.width > kMaximumReceiverDimension ||
        request.height > kMaximumReceiverDimension ||
        request.refreshHz < kMinimumReceiverRefreshHz ||
        request.refreshHz > kMaximumReceiverRefreshHz) {
        return std::nullopt;
    }

    ReceiverModeRequest normalized = request;

    // The Windows GPU encode baseline is NV12/H.264, which requires
    // chroma-compatible even dimensions. Preserve the negotiated panel
    // geometry as closely as possible instead of rejecting an otherwise
    // valid mobile panel because one axis is odd.
    normalized.width &= ~1U;
    normalized.height &= ~1U;

    if (normalized.width < kMinimumReceiverWidth ||
        normalized.height < kMinimumReceiverHeight) {
        return std::nullopt;
    }

    return normalized;
}

inline bool SameReceiverMode(
    const ReceiverModeRequest& lhs,
    const ReceiverModeRequest& rhs) noexcept {
    return lhs.protocolVersion == rhs.protocolVersion &&
        lhs.width == rhs.width &&
        lhs.height == rhs.height &&
        lhs.refreshHz == rhs.refreshHz;
}

}  // namespace displaymesh::bridge
