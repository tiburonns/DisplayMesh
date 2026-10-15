#pragma once

#include "DmpFrame.h"

#include <array>
#include <cstdint>
#include <span>
#include <string>
#include <vector>

namespace displaymesh {

enum class DmpSecureRole {
    Host,
    Receiver,
};

class DmpSecureSession {
public:
    static constexpr std::size_t kChallengeSize = 32;
    static constexpr std::size_t kKeySize = 32;
    static constexpr std::size_t kNonceSize = 12;
    static constexpr std::size_t kTagSize = 16;

    static bool DeriveFromSharedSecret(
        DmpSecureRole role,
        std::span<const std::uint8_t> sharedSecret,
        std::span<const std::uint8_t> receiverChallenge,
        std::span<const std::uint8_t> hostChallenge,
        DmpSecureSession& output,
        std::string& error);

    bool IsReady() const noexcept;

    bool Seal(
        std::span<const std::uint8_t> plaintext,
        DmpMessageType type,
        std::uint16_t flags,
        std::uint32_t sequence,
        std::vector<std::uint8_t>& combined,
        std::string& error) const;

    bool Open(
        std::span<const std::uint8_t> combined,
        DmpMessageType type,
        std::uint16_t flags,
        std::uint32_t sequence,
        std::vector<std::uint8_t>& plaintext,
        std::string& error) const;

private:
    std::array<std::uint8_t, kKeySize> sendKey_{};
    std::array<std::uint8_t, kKeySize> receiveKey_{};
    bool ready_{false};
};

}  // namespace displaymesh
