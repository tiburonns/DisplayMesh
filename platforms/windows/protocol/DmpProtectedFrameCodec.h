#pragma once

#include "DmpFrame.h"
#include "DmpSecureSession.h"

#include <optional>
#include <span>
#include <string>

namespace displaymesh {

class DmpProtectedFrameCodec {
public:
    bool IsSecure() const noexcept;
    void Install(DmpSecureSession session);
    void Clear() noexcept;

    bool OutboundFrame(
        DmpMessageType type,
        std::span<const std::uint8_t> payload,
        std::uint32_t sequence,
        DmpFrame& output,
        std::string& error) const;

    bool InboundFrame(
        const DmpFrame& frame,
        DmpFrame& output,
        std::string& error) const;

private:
    static bool IsHandshake(
        DmpMessageType type) noexcept;

    std::optional<DmpSecureSession> session_;
};

}  // namespace displaymesh
