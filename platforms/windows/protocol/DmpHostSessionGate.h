#pragma once

#include "DmpFrame.h"

#include <string>

namespace displaymesh {

enum class DmpHostPhase {
    AwaitingHello,
    ReadyToPair,
    AwaitingPairingResponse,
    AwaitingCapabilities,
    AwaitingPanel,
    Streaming,
};

const char* HostPhaseName(
    DmpHostPhase phase) noexcept;

class DmpHostSessionGate {
public:
    DmpHostPhase Phase() const noexcept;
    void Reset() noexcept;

    bool PermitsIncoming(
        DmpMessageType type) const noexcept;

    bool CanSendPairingRequest() const noexcept;
    bool CanSendVideo() const noexcept;
    bool CanRouteInput() const noexcept;

    bool AcceptHello(
        std::string& error) noexcept;

    bool PairingRequestSent(
        std::string& error) noexcept;

    bool AcceptPairingResponse(
        bool accepted,
        std::string& error) noexcept;

    bool AcceptCapabilities(
        std::string& error) noexcept;

    bool AcceptPanelDescriptor(
        std::string& error) noexcept;

private:
    bool Require(
        DmpHostPhase expected,
        const char* operation,
        std::string& error) const noexcept;

    DmpHostPhase phase_{
        DmpHostPhase::AwaitingHello};
};

}  // namespace displaymesh
