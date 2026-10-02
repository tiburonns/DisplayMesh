#include "../DmpHostReconnectPolicy.h"

#include <cassert>
#include <string>

using namespace displaymesh;

namespace {

void AdvanceToStreaming(
    DmpHostSessionGate& gate) {
    std::string error;
    assert(gate.AcceptHello(error));
    assert(gate.PairingRequestSent(error));
    assert(gate.AcceptPairingResponse(
        true,
        error));
    assert(gate.AcceptCapabilities(error));
    assert(gate.AcceptPanelDescriptor(error));
    assert(gate.CanSendVideo());
    assert(gate.CanRouteInput());
}

void TestBackoffIsBounded() {
    assert(
        DmpHostReconnectPolicy::
            DelayMilliseconds(0) == 0);
    assert(
        DmpHostReconnectPolicy::
            DelayMilliseconds(1) == 500);
    assert(
        DmpHostReconnectPolicy::
            DelayMilliseconds(2) == 1000);
    assert(
        DmpHostReconnectPolicy::
            DelayMilliseconds(3) == 2000);
    assert(
        DmpHostReconnectPolicy::
            DelayMilliseconds(4) == 4000);
    assert(
        DmpHostReconnectPolicy::
            DelayMilliseconds(20) == 4000);
}

void TestOnlyTransientFailuresRetry() {
    for (const auto reason : {
             DmpReconnectReason::TransportClosed,
             DmpReconnectReason::ConnectTimeout,
             DmpReconnectReason::HelloTimeout,
             DmpReconnectReason::CapabilitiesTimeout,
             DmpReconnectReason::PanelTimeout}) {
        assert(
            DmpHostReconnectPolicy::
                IsRetryable(reason));
    }

    for (const auto reason : {
             DmpReconnectReason::PairingTimeout,
             DmpReconnectReason::PairingRejected,
             DmpReconnectReason::ProtocolViolation,
             DmpReconnectReason::IdentityChanged,
             DmpReconnectReason::IncompatibleCapabilities,
             DmpReconnectReason::UnexpectedSequence}) {
        assert(
            !DmpHostReconnectPolicy::
                IsRetryable(reason));
    }
}

void TestRetryBudget() {
    auto first =
        DmpHostReconnectPolicy::Evaluate(
            DmpReconnectReason::
                TransportClosed,
            0,
            3);
    assert(first.retry);
    assert(
        first.delayMilliseconds == 500);

    auto last =
        DmpHostReconnectPolicy::Evaluate(
            DmpReconnectReason::
                TransportClosed,
            2,
            3);
    assert(last.retry);
    assert(
        last.delayMilliseconds == 2000);

    assert(
        !DmpHostReconnectPolicy::Evaluate(
             DmpReconnectReason::
                 TransportClosed,
             3,
             3)
             .retry);

    assert(
        !DmpHostReconnectPolicy::Evaluate(
             DmpReconnectReason::
                 TransportClosed,
             0,
             0)
             .retry);

    assert(
        !DmpHostReconnectPolicy::Evaluate(
             DmpReconnectReason::
                 TransportClosed,
             0,
             11)
             .retry);

    assert(
        !DmpHostReconnectPolicy::Evaluate(
             DmpReconnectReason::
                 PairingRejected,
             0,
             3)
             .retry);
}

void TestReconnectResetIsFailClosed() {
    DmpHostSessionGate gate;
    AdvanceToStreaming(gate);

    DmpHostReconnectPolicy::
        ResetSessionForReconnect(gate);

    assert(
        gate.Phase() ==
        DmpHostPhase::AwaitingHello);
    assert(!gate.CanSendVideo());
    assert(!gate.CanRouteInput());
    assert(
        gate.PermitsIncoming(
            DmpMessageType::Hello));
    assert(
        !gate.PermitsIncoming(
            DmpMessageType::Input));
}

}  // namespace

int main() {
    TestBackoffIsBounded();
    TestOnlyTransientFailuresRetry();
    TestRetryBudget();
    TestReconnectResetIsFailClosed();
    return 0;
}
