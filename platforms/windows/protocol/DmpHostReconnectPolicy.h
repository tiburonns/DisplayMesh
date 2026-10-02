#pragma once

#include "DmpHostSessionGate.h"

#include <cstdint>

namespace displaymesh {

enum class DmpReconnectReason {
    TransportClosed,
    ConnectTimeout,
    HelloTimeout,
    CapabilitiesTimeout,
    PanelTimeout,
    PairingTimeout,
    PairingRejected,
    ProtocolViolation,
    IdentityChanged,
    IncompatibleCapabilities,
    UnexpectedSequence,
};

struct DmpReconnectDecision {
    bool retry{};
    std::uint32_t delayMilliseconds{};
};

class DmpHostReconnectPolicy {
public:
    static constexpr std::uint32_t
        kDefaultMaximumRetries = 3;
    static constexpr std::uint32_t
        kMaximumSupportedRetries = 10;
    static constexpr std::uint32_t
        kBaseDelayMilliseconds = 500;
    static constexpr std::uint32_t
        kMaximumDelayMilliseconds = 4000;

    static bool IsRetryable(
        DmpReconnectReason reason) noexcept;

    static std::uint32_t DelayMilliseconds(
        std::uint32_t retryNumber) noexcept;

    static DmpReconnectDecision Evaluate(
        DmpReconnectReason reason,
        std::uint32_t completedRetries,
        std::uint32_t maximumRetries =
            kDefaultMaximumRetries) noexcept;

    static void ResetSessionForReconnect(
        DmpHostSessionGate& gate) noexcept;
};

}  // namespace displaymesh
