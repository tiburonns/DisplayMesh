#include "DmpProtectedFrameCodec.h"

#include <utility>

namespace displaymesh {

bool DmpProtectedFrameCodec::IsSecure() const noexcept {
    return session_.has_value() &&
        session_->IsReady();
}

void DmpProtectedFrameCodec::Install(
    DmpSecureSession session) {
    session_ = std::move(session);
}

void DmpProtectedFrameCodec::Clear() noexcept {
    session_.reset();
}

bool DmpProtectedFrameCodec::OutboundFrame(
    DmpMessageType type,
    std::span<const std::uint8_t> payload,
    std::uint32_t sequence,
    DmpFrame& output,
    std::string& error) const {
    if (IsHandshake(type)) {
        if (IsSecure()) {
            error =
                "DisplayMesh handshake frame is forbidden after secure-session installation";
            return false;
        }
        output = DmpFrame{
            type,
            0,
            sequence,
            std::vector<std::uint8_t>(
                payload.begin(),
                payload.end()),
        };
        error.clear();
        return true;
    }

    if (!IsSecure()) {
        error =
            "DisplayMesh secure session is required before post-pairing traffic";
        return false;
    }

    std::vector<std::uint8_t> encrypted;
    if (!session_->Seal(
            payload,
            type,
            0,
            sequence,
            encrypted,
            error)) {
        return false;
    }

    output = DmpFrame{
        type,
        kDmpEncryptedPayloadFlag,
        sequence,
        std::move(encrypted),
    };
    error.clear();
    return true;
}

bool DmpProtectedFrameCodec::InboundFrame(
    const DmpFrame& frame,
    DmpFrame& output,
    std::string& error) const {
    if (IsHandshake(frame.type)) {
        if ((frame.flags & kDmpEncryptedPayloadFlag) != 0U ||
            IsSecure()) {
            error =
                "DisplayMesh rejected unexpected encrypted/late handshake frame";
            return false;
        }
        output = frame;
        error.clear();
        return true;
    }

    if (!IsSecure()) {
        error =
            "DisplayMesh secure session is required before accepting post-pairing traffic";
        return false;
    }
    if ((frame.flags & kDmpEncryptedPayloadFlag) == 0U) {
        error =
            "DisplayMesh rejected plaintext post-pairing frame";
        return false;
    }

    std::vector<std::uint8_t> plaintext;
    if (!session_->Open(
            frame.payload,
            frame.type,
            frame.flags,
            frame.sequence,
            plaintext,
            error)) {
        return false;
    }

    output = DmpFrame{
        frame.type,
        0,
        frame.sequence,
        std::move(plaintext),
    };
    error.clear();
    return true;
}

bool DmpProtectedFrameCodec::IsHandshake(
    DmpMessageType type) noexcept {
    return type == DmpMessageType::Hello ||
        type == DmpMessageType::Pairing;
}

}  // namespace displaymesh
