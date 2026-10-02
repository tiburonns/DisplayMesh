#include "DmpHostSessionGate.h"

namespace displaymesh {

const char* HostPhaseName(
    DmpHostPhase phase) noexcept {
    switch (phase) {
    case DmpHostPhase::AwaitingHello:
        return "awaiting-hello";
    case DmpHostPhase::ReadyToPair:
        return "ready-to-pair";
    case DmpHostPhase::AwaitingPairingResponse:
        return "awaiting-pairing-response";
    case DmpHostPhase::AwaitingCapabilities:
        return "awaiting-capabilities";
    case DmpHostPhase::AwaitingPanel:
        return "awaiting-panel";
    case DmpHostPhase::Streaming:
        return "streaming";
    }

    return "unknown";
}

DmpHostPhase
DmpHostSessionGate::Phase() const noexcept {
    return phase_;
}

void DmpHostSessionGate::Reset() noexcept {
    phase_ = DmpHostPhase::AwaitingHello;
}

bool DmpHostSessionGate::PermitsIncoming(
    DmpMessageType type) const noexcept {
    if (type == DmpMessageType::Error) {
        return true;
    }

    switch (phase_) {
    case DmpHostPhase::AwaitingHello:
    case DmpHostPhase::ReadyToPair:
        return type == DmpMessageType::Hello;

    case DmpHostPhase::AwaitingPairingResponse:
        return type == DmpMessageType::Pairing;

    case DmpHostPhase::AwaitingCapabilities:
        return type ==
            DmpMessageType::Capabilities;

    case DmpHostPhase::AwaitingPanel:
        return type ==
                DmpMessageType::PanelDescriptor ||
            type ==
                DmpMessageType::Capabilities;

    case DmpHostPhase::Streaming:
        switch (type) {
        case DmpMessageType::PanelDescriptor:
        case DmpMessageType::Capabilities:
        case DmpMessageType::KeyframeRequest:
        case DmpMessageType::Input:
        case DmpMessageType::Telemetry:
        case DmpMessageType::Pong:
            return true;

        case DmpMessageType::Ping:
        case DmpMessageType::Hello:
        case DmpMessageType::Pairing:
        case DmpMessageType::Video:
        case DmpMessageType::Error:
            return false;
        }
    }

    return false;
}

bool DmpHostSessionGate::
CanSendPairingRequest() const noexcept {
    return phase_ ==
        DmpHostPhase::ReadyToPair;
}

bool DmpHostSessionGate::
CanSendVideo() const noexcept {
    return phase_ ==
        DmpHostPhase::Streaming;
}

bool DmpHostSessionGate::
CanRouteInput() const noexcept {
    return phase_ ==
        DmpHostPhase::Streaming;
}

bool DmpHostSessionGate::AcceptHello(
    std::string& error) noexcept {
    if (phase_ ==
        DmpHostPhase::ReadyToPair) {
        error.clear();
        return true;
    }

    if (!Require(
            DmpHostPhase::AwaitingHello,
            "accept receiver hello",
            error)) {
        return false;
    }

    phase_ = DmpHostPhase::ReadyToPair;
    error.clear();
    return true;
}

bool DmpHostSessionGate::PairingRequestSent(
    std::string& error) noexcept {
    if (!Require(
            DmpHostPhase::ReadyToPair,
            "send pairing request",
            error)) {
        return false;
    }

    phase_ =
        DmpHostPhase::AwaitingPairingResponse;
    error.clear();
    return true;
}

bool DmpHostSessionGate::AcceptPairingResponse(
    bool accepted,
    std::string& error) noexcept {
    if (!Require(
            DmpHostPhase::AwaitingPairingResponse,
            "accept pairing response",
            error)) {
        return false;
    }

    phase_ = accepted
        ? DmpHostPhase::AwaitingCapabilities
        : DmpHostPhase::ReadyToPair;

    error.clear();
    return true;
}

bool DmpHostSessionGate::AcceptCapabilities(
    std::string& error) noexcept {
    if (phase_ ==
        DmpHostPhase::AwaitingPanel) {
        error.clear();
        return true;
    }

    if (phase_ ==
        DmpHostPhase::Streaming) {
        error.clear();
        return true;
    }

    if (!Require(
            DmpHostPhase::AwaitingCapabilities,
            "accept receiver capabilities",
            error)) {
        return false;
    }

    phase_ =
        DmpHostPhase::AwaitingPanel;
    error.clear();
    return true;
}

bool DmpHostSessionGate::AcceptPanelDescriptor(
    std::string& error) noexcept {
    if (phase_ ==
        DmpHostPhase::Streaming) {
        error.clear();
        return true;
    }

    if (!Require(
            DmpHostPhase::AwaitingPanel,
            "accept panel descriptor",
            error)) {
        return false;
    }

    phase_ =
        DmpHostPhase::Streaming;
    error.clear();
    return true;
}

bool DmpHostSessionGate::Require(
    DmpHostPhase expected,
    const char* operation,
    std::string& error) const noexcept {
    if (phase_ == expected) {
        return true;
    }

    error =
        std::string(operation) +
        " is not valid while host phase is " +
        HostPhaseName(phase_);
    return false;
}

}  // namespace displaymesh
