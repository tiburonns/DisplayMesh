#include "../DmpHostConnectionCoordinator.h"
#include "../DmpProtectedFrameCodec.h"
#include "../DmpSecureSession.h"

#include <array>
#include <cassert>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

using namespace displaymesh;

namespace {

std::array<std::uint8_t, 32> Bytes(
    std::uint8_t start) {
    std::array<std::uint8_t, 32> value{};
    for (std::size_t index = 0;
         index < value.size();
         ++index) {
        value[index] =
            static_cast<std::uint8_t>(
                start + index);
    }
    return value;
}

void DerivePair(
    DmpSecureSession& host,
    DmpSecureSession& receiver) {
    const auto secret = Bytes(1);
    const auto receiverChallenge = Bytes(40);
    const auto hostChallenge = Bytes(90);
    std::string error;

    assert(
        DmpSecureSession::DeriveFromSharedSecret(
            DmpSecureRole::Host,
            secret,
            receiverChallenge,
            hostChallenge,
            host,
            error));
    assert(
        DmpSecureSession::DeriveFromSharedSecret(
            DmpSecureRole::Receiver,
            secret,
            receiverChallenge,
            hostChallenge,
            receiver,
            error));
}

void AdvanceThroughPairing(
    DmpHostConnectionCoordinator& host,
    DmpSecureSession hostSession,
    DmpSecureSession receiverSession,
    DmpProtectedFrameCodec& receiverCodec) {
    std::string error;
    DmpFrame plain;

    DmpFrame hello{
        DmpMessageType::Hello,
        0,
        1,
        {'{', '}'},
    };
    assert(
        host.AcceptIncomingWireFrame(
            hello,
            plain,
            error));
    assert(
        host.MarkHelloAccepted(
            error));
    assert(
        host.Phase() ==
        DmpHostPhase::ReadyToPair);

    DmpFrame pairingRequest;
    assert(
        host.MakePairingRequest(
            std::array<std::uint8_t, 2>{
                0x01,
                0x02,
            },
            pairingRequest,
            error));
    assert(
        pairingRequest.type ==
        DmpMessageType::Pairing);
    assert(pairingRequest.flags == 0);
    assert(pairingRequest.sequence == 1);
    assert(
        host.Phase() ==
        DmpHostPhase::
            AwaitingPairingResponse);

    DmpFrame pairingResponse{
        DmpMessageType::Pairing,
        0,
        2,
        {0x01},
    };
    assert(
        host.AcceptIncomingWireFrame(
            pairingResponse,
            plain,
            error));

    assert(
        host.AcceptPairingResult(
            true,
            std::move(hostSession),
            error));
    assert(host.IsSecure());
    assert(
        host.Phase() ==
        DmpHostPhase::
            AwaitingCapabilities);

    receiverCodec.Install(
        std::move(receiverSession));
}

void TestSecurePhaseProgression() {
    DmpSecureSession hostSession;
    DmpSecureSession receiverSession;
    DerivePair(
        hostSession,
        receiverSession);

    DmpHostConnectionCoordinator host;
    DmpProtectedFrameCodec receiverCodec;
    AdvanceThroughPairing(
        host,
        std::move(hostSession),
        std::move(receiverSession),
        receiverCodec);

    std::string error;
    DmpFrame plain;

    DmpFrame plaintextCapabilities{
        DmpMessageType::Capabilities,
        0,
        3,
        {0x01},
    };
    assert(
        !host.AcceptIncomingWireFrame(
            plaintextCapabilities,
            plain,
            error));

    // Crypto failure is terminal for the connection in production. Reset
    // here so the following assertions exercise a fresh transport sequence.
    host.Reset();

    DmpSecureSession freshHost;
    DmpSecureSession freshReceiver;
    DerivePair(
        freshHost,
        freshReceiver);
    DmpProtectedFrameCodec freshReceiverCodec;
    AdvanceThroughPairing(
        host,
        std::move(freshHost),
        std::move(freshReceiver),
        freshReceiverCodec);

    DmpFrame capabilities;
    assert(
        freshReceiverCodec.OutboundFrame(
            DmpMessageType::Capabilities,
            std::array<std::uint8_t, 3>{
                0x01,
                0x02,
                0x03,
            },
            3,
            capabilities,
            error));
    assert(
        host.AcceptIncomingWireFrame(
            capabilities,
            plain,
            error));
    assert(
        plain.type ==
        DmpMessageType::Capabilities);
    assert(
        host.MarkCapabilitiesAccepted(
            error));

    DmpFrame panel;
    assert(
        freshReceiverCodec.OutboundFrame(
            DmpMessageType::PanelDescriptor,
            std::array<std::uint8_t, 2>{
                0x10,
                0x20,
            },
            4,
            panel,
            error));
    assert(
        host.AcceptIncomingWireFrame(
            panel,
            plain,
            error));
    assert(
        host.MarkPanelAccepted(
            error));

    assert(
        host.Phase() ==
        DmpHostPhase::Streaming);
    assert(host.CanSendVideo());
    assert(host.CanRouteInput());

    DmpFrame video;
    assert(
        host.MakeVideoFrame(
            std::array<std::uint8_t, 4>{
                0x00,
                0x01,
                0x02,
                0x03,
            },
            video,
            error));
    assert(
        video.flags ==
        kDmpEncryptedPayloadFlag);
    assert(video.sequence == 2);

    DmpFrame ping;
    assert(
        host.MakePingFrame(
            std::array<std::uint8_t, 8>{
                1, 2, 3, 4, 5, 6, 7, 8,
            },
            ping,
            error));
    assert(ping.sequence == 3);
}

void TestUnexpectedSequenceFailsClosed() {
    DmpHostConnectionCoordinator host;
    std::string error;
    DmpFrame plain;

    DmpFrame hello{
        DmpMessageType::Hello,
        0,
        2,
        {'{', '}'},
    };

    assert(
        !host.AcceptIncomingWireFrame(
            hello,
            plain,
            error));
    assert(
        host.Phase() ==
        DmpHostPhase::AwaitingHello);
}

void TestRejectedPairingDoesNotOpenSecurity() {
    DmpHostConnectionCoordinator host;
    std::string error;
    DmpFrame plain;

    DmpFrame hello{
        DmpMessageType::Hello,
        0,
        1,
        {'{', '}'},
    };
    assert(
        host.AcceptIncomingWireFrame(
            hello,
            plain,
            error));
    assert(
        host.MarkHelloAccepted(error));

    DmpFrame request;
    assert(
        host.MakePairingRequest(
            std::array<std::uint8_t, 1>{
                0x01,
            },
            request,
            error));

    DmpFrame response{
        DmpMessageType::Pairing,
        0,
        2,
        {0x00},
    };
    assert(
        host.AcceptIncomingWireFrame(
            response,
            plain,
            error));

    DmpSecureSession unused;
    assert(
        host.AcceptPairingResult(
            false,
            unused,
            error));
    assert(!host.IsSecure());
    assert(!host.CanSendVideo());
    assert(!host.CanRouteInput());
    assert(
        host.Phase() ==
        DmpHostPhase::ReadyToPair);
}

void TestResetClearsAllConnectionState() {
    DmpSecureSession hostSession;
    DmpSecureSession receiverSession;
    DerivePair(
        hostSession,
        receiverSession);

    DmpHostConnectionCoordinator host;
    DmpProtectedFrameCodec receiverCodec;
    AdvanceThroughPairing(
        host,
        std::move(hostSession),
        std::move(receiverSession),
        receiverCodec);

    host.Reset();

    assert(!host.IsSecure());
    assert(!host.CanSendVideo());
    assert(!host.CanRouteInput());
    assert(
        host.Phase() ==
        DmpHostPhase::AwaitingHello);

    std::string error;
    DmpFrame plain;
    DmpFrame hello{
        DmpMessageType::Hello,
        0,
        1,
        {'{', '}'},
    };
    assert(
        host.AcceptIncomingWireFrame(
            hello,
            plain,
            error));
}

}  // namespace

int main() {
    TestSecurePhaseProgression();
    TestUnexpectedSequenceFailsClosed();
    TestRejectedPairingDoesNotOpenSecurity();
    TestResetClearsAllConnectionState();
    return 0;
}
