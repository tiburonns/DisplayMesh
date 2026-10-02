#pragma once

#include "DmpFrame.h"
#include "DmpHostSessionGate.h"
#include "DmpProtectedFrameCodec.h"
#include "DmpSecureSession.h"

#include <cstdint>
#include <span>
#include <string>

namespace displaymesh {

// Transport-independent fail-closed boundary for a Windows host connection.
// The live socket service should not route post-pairing traffic around this
// coordinator.
class DmpHostConnectionCoordinator {
public:
    DmpHostPhase Phase() const noexcept;
    bool IsSecure() const noexcept;
    bool CanSendVideo() const noexcept;
    bool CanRouteInput() const noexcept;

    void Reset() noexcept;

    bool AcceptIncomingWireFrame(
        const DmpFrame& wireFrame,
        DmpFrame& plaintextFrame,
        std::string& error);

    bool MarkHelloAccepted(
        std::string& error) noexcept;

    bool MakePairingRequest(
        std::span<const std::uint8_t> payload,
        DmpFrame& output,
        std::string& error);

    bool AcceptPairingResult(
        bool accepted,
        DmpSecureSession session,
        std::string& error) noexcept;

    bool MarkCapabilitiesAccepted(
        std::string& error) noexcept;

    bool MarkPanelAccepted(
        std::string& error) noexcept;

    bool MakeVideoFrame(
        std::span<const std::uint8_t> payload,
        DmpFrame& output,
        std::string& error);

    bool MakePingFrame(
        std::span<const std::uint8_t> payload,
        DmpFrame& output,
        std::string& error);

private:
    bool MakeStreamingFrame(
        DmpMessageType type,
        std::span<const std::uint8_t> payload,
        DmpFrame& output,
        std::string& error);

    std::uint32_t NextOutboundSequence() noexcept;

    DmpHostSessionGate gate_;
    DmpSequenceTracker incomingSequence_;
    DmpProtectedFrameCodec codec_;
    std::uint32_t outboundSequence_{1};
};

}  // namespace displaymesh
