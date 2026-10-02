#include "DmpHostConnectionCoordinator.h"

#include <limits>
#include <utility>

namespace displaymesh {

DmpHostPhase
DmpHostConnectionCoordinator::Phase() const noexcept {
    return gate_.Phase();
}

bool
DmpHostConnectionCoordinator::IsSecure() const noexcept {
    return codec_.IsSecure();
}

bool
DmpHostConnectionCoordinator::CanSendVideo() const noexcept {
    return gate_.CanSendVideo() &&
        codec_.IsSecure();
}

bool
DmpHostConnectionCoordinator::CanRouteInput() const noexcept {
    return gate_.CanRouteInput() &&
        codec_.IsSecure();
}

void DmpHostConnectionCoordinator::Reset() noexcept {
    gate_.Reset();
    incomingSequence_.Reset();
    codec_.Clear();
    outboundSequence_ = 1;
}

bool DmpHostConnectionCoordinator::AcceptIncomingWireFrame(
    const DmpFrame& wireFrame,
    DmpFrame& plaintextFrame,
    std::string& error) {
    if (!gate_.PermitsIncoming(
            wireFrame.type)) {
        error =
            "DisplayMesh rejected incoming frame for host phase " +
            std::string(
                HostPhaseName(
                    gate_.Phase()));
        return false;
    }

    if (!incomingSequence_.Accept(
            wireFrame.sequence,
            error)) {
        return false;
    }

    if (!codec_.InboundFrame(
            wireFrame,
            plaintextFrame,
            error)) {
        return false;
    }

    error.clear();
    return true;
}

bool DmpHostConnectionCoordinator::MarkHelloAccepted(
    std::string& error) noexcept {
    return gate_.AcceptHello(error);
}

bool DmpHostConnectionCoordinator::MakePairingRequest(
    std::span<const std::uint8_t> payload,
    DmpFrame& output,
    std::string& error) {
    if (!gate_.CanSendPairingRequest() ||
        codec_.IsSecure()) {
        error =
            "DisplayMesh pairing request is not valid in the current host state";
        return false;
    }

    const auto sequence =
        outboundSequence_;

    if (!codec_.OutboundFrame(
            DmpMessageType::Pairing,
            payload,
            sequence,
            output,
            error)) {
        return false;
    }

    if (!gate_.PairingRequestSent(
            error)) {
        return false;
    }

    (void)NextOutboundSequence();
    error.clear();
    return true;
}

bool DmpHostConnectionCoordinator::AcceptPairingResult(
    bool accepted,
    DmpSecureSession session,
    std::string& error) noexcept {
    if (accepted &&
        !session.IsReady()) {
        error =
            "DisplayMesh accepted pairing requires a ready secure session";
        return false;
    }

    if (!gate_.AcceptPairingResponse(
            accepted,
            error)) {
        return false;
    }

    if (accepted) {
        codec_.Install(
            std::move(session));
    } else {
        codec_.Clear();
    }

    error.clear();
    return true;
}

bool DmpHostConnectionCoordinator::
MarkCapabilitiesAccepted(
    std::string& error) noexcept {
    if (!codec_.IsSecure()) {
        error =
            "DisplayMesh capabilities cannot be accepted before secure-session installation";
        return false;
    }
    return gate_.AcceptCapabilities(error);
}

bool DmpHostConnectionCoordinator::MarkPanelAccepted(
    std::string& error) noexcept {
    if (!codec_.IsSecure()) {
        error =
            "DisplayMesh panel cannot be accepted before secure-session installation";
        return false;
    }
    return gate_.AcceptPanelDescriptor(error);
}

bool DmpHostConnectionCoordinator::MakeVideoFrame(
    std::span<const std::uint8_t> payload,
    DmpFrame& output,
    std::string& error) {
    return MakeStreamingFrame(
        DmpMessageType::Video,
        payload,
        output,
        error);
}

bool DmpHostConnectionCoordinator::MakePingFrame(
    std::span<const std::uint8_t> payload,
    DmpFrame& output,
    std::string& error) {
    if (payload.size() != 8) {
        error =
            "DisplayMesh ping payload must be exactly 8 bytes";
        return false;
    }

    return MakeStreamingFrame(
        DmpMessageType::Ping,
        payload,
        output,
        error);
}

bool DmpHostConnectionCoordinator::MakeStreamingFrame(
    DmpMessageType type,
    std::span<const std::uint8_t> payload,
    DmpFrame& output,
    std::string& error) {
    if (!gate_.CanSendVideo() ||
        !codec_.IsSecure()) {
        error =
            "DisplayMesh streaming output is closed until the authenticated session reaches streaming";
        return false;
    }

    const auto sequence =
        outboundSequence_;

    if (!codec_.OutboundFrame(
            type,
            payload,
            sequence,
            output,
            error)) {
        return false;
    }

    (void)NextOutboundSequence();
    error.clear();
    return true;
}

std::uint32_t
DmpHostConnectionCoordinator::NextOutboundSequence() noexcept {
    const auto current =
        outboundSequence_;
    outboundSequence_ =
        outboundSequence_ ==
                std::numeric_limits<
                    std::uint32_t>::max()
            ? 0U
            : outboundSequence_ + 1U;
    return current;
}

}  // namespace displaymesh
