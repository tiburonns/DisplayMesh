#include "../DmpProtectedFrameCodec.h"
#include "../DmpSecureSession.h"

#include <array>
#include <cassert>
#include <cstdint>
#include <string>
#include <vector>

using namespace displaymesh;

namespace {

std::array<std::uint8_t, 32> Bytes(
    std::uint8_t start) {
    std::array<std::uint8_t, 32> value{};
    for (std::size_t index = 0; index < value.size(); ++index) {
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
    assert(error.empty());
    assert(
        DmpSecureSession::DeriveFromSharedSecret(
            DmpSecureRole::Receiver,
            secret,
            receiverChallenge,
            hostChallenge,
            receiver,
            error));
    assert(error.empty());
    assert(host.IsReady());
    assert(receiver.IsReady());
}

void TestDirectionalRoundTrip() {
    DmpSecureSession host;
    DmpSecureSession receiver;
    DerivePair(host, receiver);

    const std::vector<std::uint8_t> payload{
        0x10, 0x20, 0x30, 0x40,
    };
    std::vector<std::uint8_t> encrypted;
    std::vector<std::uint8_t> opened;
    std::string error;

    assert(
        host.Seal(
            payload,
            DmpMessageType::Capabilities,
            0,
            7,
            encrypted,
            error));
    assert(
        encrypted.size() ==
        payload.size() +
            kDmpAuthenticatedEncryptionOverhead);
    assert(
        receiver.Open(
            encrypted,
            DmpMessageType::Capabilities,
            kDmpEncryptedPayloadFlag,
            7,
            opened,
            error));
    assert(opened == payload);

    const std::vector<std::uint8_t> pong(8, 0x5A);
    assert(
        receiver.Seal(
            pong,
            DmpMessageType::Pong,
            0,
            8,
            encrypted,
            error));
    assert(
        host.Open(
            encrypted,
            DmpMessageType::Pong,
            kDmpEncryptedPayloadFlag,
            8,
            opened,
            error));
    assert(opened == pong);
}

void TestAadTamperFails() {
    DmpSecureSession host;
    DmpSecureSession receiver;
    DerivePair(host, receiver);

    const std::vector<std::uint8_t> input(40, 0x11);
    std::vector<std::uint8_t> encrypted;
    std::vector<std::uint8_t> opened;
    std::string error;

    assert(
        host.Seal(
            input,
            DmpMessageType::Input,
            0,
            100,
            encrypted,
            error));

    assert(
        !receiver.Open(
            encrypted,
            DmpMessageType::Input,
            kDmpEncryptedPayloadFlag,
            101,
            opened,
            error));
    assert(!error.empty());

    auto tampered = encrypted;
    tampered[12] ^= 0x01;
    assert(
        !receiver.Open(
            tampered,
            DmpMessageType::Input,
            kDmpEncryptedPayloadFlag,
            100,
            opened,
            error));
}

void TestExactEmptyPayload() {
    DmpSecureSession host;
    DmpSecureSession receiver;
    DerivePair(host, receiver);

    std::vector<std::uint8_t> encrypted;
    std::vector<std::uint8_t> opened;
    std::string error;

    assert(
        host.Seal(
            {},
            DmpMessageType::KeyframeRequest,
            0,
            12,
            encrypted,
            error));
    assert(
        encrypted.size() ==
        kDmpAuthenticatedEncryptionOverhead);
    assert(
        receiver.Open(
            encrypted,
            DmpMessageType::KeyframeRequest,
            kDmpEncryptedPayloadFlag,
            12,
            opened,
            error));
    assert(opened.empty());
}

void TestProtectedCodecFailsClosed() {
    DmpSecureSession hostSession;
    DmpSecureSession receiverSession;
    DerivePair(
        hostSession,
        receiverSession);

    DmpProtectedFrameCodec host;
    DmpProtectedFrameCodec receiver;
    std::string error;
    DmpFrame frame;
    DmpFrame opened;

    const std::vector<std::uint8_t> hello{
        '{', '}',
    };
    assert(
        host.OutboundFrame(
            DmpMessageType::Hello,
            hello,
            1,
            frame,
            error));
    assert(frame.flags == 0);

    assert(
        !host.OutboundFrame(
            DmpMessageType::Capabilities,
            hello,
            2,
            frame,
            error));

    host.Install(hostSession);
    receiver.Install(receiverSession);

    const std::vector<std::uint8_t> capabilities{
        0x01, 0x02, 0x03,
    };
    assert(
        host.OutboundFrame(
            DmpMessageType::Capabilities,
            capabilities,
            3,
            frame,
            error));
    assert(
        frame.flags ==
        kDmpEncryptedPayloadFlag);
    assert(
        receiver.InboundFrame(
            frame,
            opened,
            error));
    assert(opened.flags == 0);
    assert(opened.payload == capabilities);

    DmpFrame plaintext{
        DmpMessageType::Telemetry,
        0,
        4,
        {0x01},
    };
    assert(
        !receiver.InboundFrame(
            plaintext,
            opened,
            error));

    assert(
        !host.OutboundFrame(
            DmpMessageType::Pairing,
            hello,
            5,
            frame,
            error));

    host.Clear();
    assert(!host.IsSecure());
}

void TestChallengeValidation() {
    DmpSecureSession session;
    std::string error;
    const auto secret = Bytes(1);
    const auto challenge = Bytes(2);
    const std::array<std::uint8_t, 31> shortChallenge{};

    assert(
        !DmpSecureSession::DeriveFromSharedSecret(
            DmpSecureRole::Host,
            secret,
            shortChallenge,
            challenge,
            session,
            error));
    assert(!error.empty());
}

}  // namespace

int main() {
    TestDirectionalRoundTrip();
    TestAadTamperFails();
    TestExactEmptyPayload();
    TestProtectedCodecFailsClosed();
    TestChallengeValidation();
    return 0;
}
