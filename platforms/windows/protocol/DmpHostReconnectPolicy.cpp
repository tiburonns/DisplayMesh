#include "DmpHostReconnectPolicy.h"

#include <algorithm>
#include <limits>

namespace displaymesh {

bool DmpHostReconnectPolicy::IsRetryable(
    DmpReconnectReason reason) noexcept {
    switch (reason) {
    case DmpReconnectReason::TransportClosed:
    case DmpReconnectReason::ConnectTimeout:
    case DmpReconnectReason::HelloTimeout:
    case DmpReconnectReason::CapabilitiesTimeout:
    case DmpReconnectReason::PanelTimeout:
        return true;

    case DmpReconnectReason::PairingTimeout:
    case DmpReconnectReason::PairingRejected:
    case DmpReconnectReason::ProtocolViolation:
    case DmpReconnectReason::IdentityChanged:
    case DmpReconnectReason::IncompatibleCapabilities:
    case DmpReconnectReason::UnexpectedSequence:
        return false;
    }

    return false;
}

std::uint32_t
DmpHostReconnectPolicy::DelayMilliseconds(
    std::uint32_t retryNumber) noexcept {
    if (retryNumber == 0) {
        return 0;
    }

    const auto exponent =
        std::min<std::uint32_t>(
            retryNumber - 1,
            16);

    std::uint64_t delay =
        static_cast<std::uint64_t>(
            kBaseDelayMilliseconds) <<
        exponent;

    delay =
        std::min<std::uint64_t>(
            delay,
            kMaximumDelayMilliseconds);

    return static_cast<std::uint32_t>(
        delay);
}

DmpReconnectDecision
DmpHostReconnectPolicy::Evaluate(
    DmpReconnectReason reason,
    std::uint32_t completedRetries,
    std::uint32_t maximumRetries) noexcept {
    if (maximumRetries == 0 ||
        maximumRetries >
            kMaximumSupportedRetries ||
        completedRetries >= maximumRetries ||
        !IsRetryable(reason)) {
        return {};
    }

    return DmpReconnectDecision{
        true,
        DelayMilliseconds(
            completedRetries + 1),
    };
}

void DmpHostReconnectPolicy::
ResetSessionForReconnect(
    DmpHostSessionGate& gate) noexcept {
    gate.Reset();
}

}  // namespace displaymesh
