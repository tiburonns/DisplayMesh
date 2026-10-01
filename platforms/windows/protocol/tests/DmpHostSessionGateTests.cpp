#include "DmpHostSessionGate.h"

#include <cassert>
#include <string>

using namespace displaymesh;

namespace {

void TestIncomingAdmissionByPhase() {
    DmpHostSessionGate gate;

    assert(
        gate.Phase() ==
        DmpHostPhase::AwaitingHello);

    assert(gate.PermitsIncoming(
        DmpMessageType::Hello));
    assert(gate.PermitsIncoming(
        DmpMessageType::Error));

    assert(!gate.PermitsIncoming(
        DmpMessageType::Pairing));
    assert(!gate.PermitsIncoming(
        DmpMessageType::Input));
    assert(!gate.PermitsIncoming(
        DmpMessageType::Video));

    std::string error;
    assert(gate.AcceptHello(error));
    assert(gate.CanSendPairingRequest());
    assert(!gate.CanSendVideo());
    assert(!gate.CanRouteInput());

    assert(gate.PairingRequestSent(error));
    assert(gate.PermitsIncoming(
        DmpMessageType::Pairing));
    assert(!gate.PermitsIncoming(
        DmpMessageType::Input));

    assert(gate.AcceptPairingResponse(
        true,
        error));
    assert(gate.PermitsIncoming(
        DmpMessageType::Capabilities));
    assert(!gate.PermitsIncoming(
        DmpMessageType::PanelDescriptor));
    assert(!gate.PermitsIncoming(
        DmpMessageType::Input));

    assert(gate.AcceptCapabilities(error));
    assert(gate.PermitsIncoming(
        DmpMessageType::Capabilities));
    assert(gate.PermitsIncoming(
        DmpMessageType::PanelDescriptor));
    assert(!gate.PermitsIncoming(
        DmpMessageType::Input));

    assert(gate.AcceptPanelDescriptor(
        error));

    assert(gate.CanSendVideo());
    assert(gate.CanRouteInput());

    assert(gate.PermitsIncoming(
        DmpMessageType::Input));
    assert(gate.PermitsIncoming(
        DmpMessageType::Telemetry));
    assert(gate.PermitsIncoming(
        DmpMessageType::Pong));
    assert(!gate.PermitsIncoming(
        DmpMessageType::Ping));
    assert(gate.PermitsIncoming(
        DmpMessageType::KeyframeRequest));
    assert(gate.PermitsIncoming(
        DmpMessageType::PanelDescriptor));
    assert(gate.PermitsIncoming(
        DmpMessageType::Capabilities));

    assert(!gate.PermitsIncoming(
        DmpMessageType::Hello));
    assert(!gate.PermitsIncoming(
        DmpMessageType::Pairing));
    assert(!gate.PermitsIncoming(
        DmpMessageType::Video));
}

void TestRejectedPairingReturnsToReady() {
    DmpHostSessionGate gate;
    std::string error;

    assert(gate.AcceptHello(error));
    assert(gate.PairingRequestSent(error));
    assert(gate.AcceptPairingResponse(
        false,
        error));

    assert(
        gate.Phase() ==
        DmpHostPhase::ReadyToPair);
    assert(gate.CanSendPairingRequest());
    assert(!gate.CanRouteInput());
    assert(!gate.CanSendVideo());
}

void TestInvalidTransitionsFailClosed() {
    DmpHostSessionGate gate;
    std::string error;

    assert(!gate.PairingRequestSent(error));
    assert(!error.empty());

    error.clear();
    assert(!gate.AcceptCapabilities(error));
    assert(!error.empty());

    error.clear();
    assert(!gate.AcceptPanelDescriptor(error));
    assert(!error.empty());

    assert(!gate.CanRouteInput());
    assert(!gate.CanSendVideo());
}

void TestCapabilitiesAndPanelRefreshes() {
    DmpHostSessionGate gate;
    std::string error;

    assert(gate.AcceptHello(error));
    assert(gate.PairingRequestSent(error));
    assert(gate.AcceptPairingResponse(
        true,
        error));
    assert(gate.AcceptCapabilities(error));

    // A receiver may refresh capabilities while
    // the host is waiting for the panel.
    assert(gate.AcceptCapabilities(error));

    assert(gate.AcceptPanelDescriptor(
        error));

    // During streaming, validated capability/panel
    // refreshes do not demote the session.
    assert(gate.AcceptCapabilities(error));
    assert(gate.AcceptPanelDescriptor(
        error));
    assert(
        gate.Phase() ==
        DmpHostPhase::Streaming);
}

void TestResetClosesInputGate() {
    DmpHostSessionGate gate;
    std::string error;

    assert(gate.AcceptHello(error));
    assert(gate.PairingRequestSent(error));
    assert(gate.AcceptPairingResponse(
        true,
        error));
    assert(gate.AcceptCapabilities(error));
    assert(gate.AcceptPanelDescriptor(
        error));
    assert(gate.CanRouteInput());

    gate.Reset();

    assert(
        gate.Phase() ==
        DmpHostPhase::AwaitingHello);
    assert(!gate.CanRouteInput());
    assert(!gate.CanSendVideo());
    assert(gate.PermitsIncoming(
        DmpMessageType::Hello));
}

}  // namespace

int main() {
    TestIncomingAdmissionByPhase();
    TestRejectedPairingReturnsToReady();
    TestInvalidTransitionsFailClosed();
    TestCapabilitiesAndPanelRefreshes();
    TestResetClosesInputGate();
    return 0;
}
