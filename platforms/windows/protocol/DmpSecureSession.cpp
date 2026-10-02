#include "DmpSecureSession.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>

#include <algorithm>
#include <array>
#include <cstring>
#include <limits>
#include <string_view>
#include <vector>

#pragma comment(lib, "bcrypt.lib")

namespace displaymesh {
namespace {

constexpr std::size_t kSha256Size = 32;

bool Succeeded(NTSTATUS status) noexcept {
    return status >= 0;
}

std::string StatusMessage(
    const char* operation,
    NTSTATUS status) {
    return std::string(operation) +
        " failed with NTSTATUS " +
        std::to_string(
            static_cast<unsigned long>(
                static_cast<std::uint32_t>(status)));
}

class AlgorithmHandle {
public:
    AlgorithmHandle() = default;
    ~AlgorithmHandle() {
        if (handle_ != nullptr) {
            BCryptCloseAlgorithmProvider(handle_, 0);
        }
    }

    AlgorithmHandle(const AlgorithmHandle&) = delete;
    AlgorithmHandle& operator=(const AlgorithmHandle&) = delete;

    BCRYPT_ALG_HANDLE* Put() noexcept {
        return &handle_;
    }

    BCRYPT_ALG_HANDLE Get() const noexcept {
        return handle_;
    }

private:
    BCRYPT_ALG_HANDLE handle_{nullptr};
};

class HashHandle {
public:
    ~HashHandle() {
        if (handle_ != nullptr) {
            BCryptDestroyHash(handle_);
        }
    }

    BCRYPT_HASH_HANDLE* Put() noexcept {
        return &handle_;
    }

    BCRYPT_HASH_HANDLE Get() const noexcept {
        return handle_;
    }

private:
    BCRYPT_HASH_HANDLE handle_{nullptr};
};

class KeyHandle {
public:
    ~KeyHandle() {
        if (handle_ != nullptr) {
            BCryptDestroyKey(handle_);
        }
    }

    BCRYPT_KEY_HANDLE* Put() noexcept {
        return &handle_;
    }

    BCRYPT_KEY_HANDLE Get() const noexcept {
        return handle_;
    }

private:
    BCRYPT_KEY_HANDLE handle_{nullptr};
};

bool QueryUlong(
    BCRYPT_HANDLE handle,
    const wchar_t* property,
    ULONG& value,
    std::string& error) {
    ULONG copied = 0;
    const auto status = BCryptGetProperty(
        handle,
        property,
        reinterpret_cast<PUCHAR>(&value),
        sizeof(value),
        &copied,
        0);
    if (!Succeeded(status) || copied != sizeof(value)) {
        error = StatusMessage("BCryptGetProperty", status);
        return false;
    }
    return true;
}

bool Sha256(
    std::span<const std::uint8_t> input,
    std::array<std::uint8_t, kSha256Size>& digest,
    std::string& error) {
    AlgorithmHandle algorithm;
    auto status = BCryptOpenAlgorithmProvider(
        algorithm.Put(),
        BCRYPT_SHA256_ALGORITHM,
        nullptr,
        0);
    if (!Succeeded(status)) {
        error = StatusMessage(
            "BCryptOpenAlgorithmProvider(SHA256)",
            status);
        return false;
    }

    ULONG objectLength = 0;
    if (!QueryUlong(
            algorithm.Get(),
            BCRYPT_OBJECT_LENGTH,
            objectLength,
            error)) {
        return false;
    }

    std::vector<std::uint8_t> object(objectLength);
    HashHandle hash;
    status = BCryptCreateHash(
        algorithm.Get(),
        hash.Put(),
        object.data(),
        static_cast<ULONG>(object.size()),
        nullptr,
        0,
        0);
    if (!Succeeded(status)) {
        error = StatusMessage("BCryptCreateHash", status);
        return false;
    }

    if (!input.empty()) {
        status = BCryptHashData(
            hash.Get(),
            const_cast<PUCHAR>(input.data()),
            static_cast<ULONG>(input.size()),
            0);
        if (!Succeeded(status)) {
            error = StatusMessage("BCryptHashData", status);
            return false;
        }
    }

    status = BCryptFinishHash(
        hash.Get(),
        digest.data(),
        static_cast<ULONG>(digest.size()),
        0);
    if (!Succeeded(status)) {
        error = StatusMessage("BCryptFinishHash", status);
        return false;
    }

    error.clear();
    return true;
}

bool HmacSha256(
    std::span<const std::uint8_t> key,
    std::span<const std::uint8_t> input,
    std::array<std::uint8_t, kSha256Size>& digest,
    std::string& error) {
    AlgorithmHandle algorithm;
    auto status = BCryptOpenAlgorithmProvider(
        algorithm.Put(),
        BCRYPT_SHA256_ALGORITHM,
        nullptr,
        BCRYPT_ALG_HANDLE_HMAC_FLAG);
    if (!Succeeded(status)) {
        error = StatusMessage(
            "BCryptOpenAlgorithmProvider(HMAC-SHA256)",
            status);
        return false;
    }

    ULONG objectLength = 0;
    if (!QueryUlong(
            algorithm.Get(),
            BCRYPT_OBJECT_LENGTH,
            objectLength,
            error)) {
        return false;
    }

    std::vector<std::uint8_t> object(objectLength);
    HashHandle hash;
    status = BCryptCreateHash(
        algorithm.Get(),
        hash.Put(),
        object.data(),
        static_cast<ULONG>(object.size()),
        const_cast<PUCHAR>(key.data()),
        static_cast<ULONG>(key.size()),
        0);
    if (!Succeeded(status)) {
        error = StatusMessage("BCryptCreateHash(HMAC)", status);
        return false;
    }

    if (!input.empty()) {
        status = BCryptHashData(
            hash.Get(),
            const_cast<PUCHAR>(input.data()),
            static_cast<ULONG>(input.size()),
            0);
        if (!Succeeded(status)) {
            error = StatusMessage("BCryptHashData(HMAC)", status);
            return false;
        }
    }

    status = BCryptFinishHash(
        hash.Get(),
        digest.data(),
        static_cast<ULONG>(digest.size()),
        0);
    if (!Succeeded(status)) {
        error = StatusMessage("BCryptFinishHash(HMAC)", status);
        return false;
    }

    error.clear();
    return true;
}

bool HkdfSha256OneBlock(
    std::span<const std::uint8_t> ikm,
    std::span<const std::uint8_t> salt,
    std::string_view info,
    std::array<std::uint8_t, DmpSecureSession::kKeySize>& output,
    std::string& error) {
    std::array<std::uint8_t, kSha256Size> prk{};
    if (!HmacSha256(
            salt,
            ikm,
            prk,
            error)) {
        return false;
    }

    std::vector<std::uint8_t> expandInput(
        info.begin(),
        info.end());
    expandInput.push_back(0x01);

    std::array<std::uint8_t, kSha256Size> block{};
    if (!HmacSha256(
            prk,
            expandInput,
            block,
            error)) {
        return false;
    }

    static_assert(
        DmpSecureSession::kKeySize <= kSha256Size);
    std::copy_n(
        block.begin(),
        DmpSecureSession::kKeySize,
        output.begin());
    error.clear();
    return true;
}

std::array<std::uint8_t, 8> AdditionalAuthenticatedData(
    DmpMessageType type,
    std::uint16_t flags,
    std::uint32_t sequence) {
    return {
        kDmpVersion,
        static_cast<std::uint8_t>(type),
        static_cast<std::uint8_t>(flags >> 8),
        static_cast<std::uint8_t>(flags),
        static_cast<std::uint8_t>(sequence >> 24),
        static_cast<std::uint8_t>(sequence >> 16),
        static_cast<std::uint8_t>(sequence >> 8),
        static_cast<std::uint8_t>(sequence),
    };
}

bool CreateChaChaKey(
    std::span<const std::uint8_t> keyBytes,
    AlgorithmHandle& algorithm,
    KeyHandle& key,
    std::vector<std::uint8_t>& keyObject,
    std::string& error) {
    auto status = BCryptOpenAlgorithmProvider(
        algorithm.Put(),
        BCRYPT_CHACHA20_POLY1305_ALGORITHM,
        nullptr,
        0);
    if (!Succeeded(status)) {
        error = StatusMessage(
            "BCryptOpenAlgorithmProvider(CHACHA20_POLY1305)",
            status);
        return false;
    }

    ULONG objectLength = 0;
    if (!QueryUlong(
            algorithm.Get(),
            BCRYPT_OBJECT_LENGTH,
            objectLength,
            error)) {
        return false;
    }
    keyObject.resize(objectLength);

    status = BCryptGenerateSymmetricKey(
        algorithm.Get(),
        key.Put(),
        keyObject.empty() ? nullptr : keyObject.data(),
        static_cast<ULONG>(keyObject.size()),
        const_cast<PUCHAR>(keyBytes.data()),
        static_cast<ULONG>(keyBytes.size()),
        0);
    if (!Succeeded(status)) {
        error = StatusMessage(
            "BCryptGenerateSymmetricKey(CHACHA20_POLY1305)",
            status);
        return false;
    }

    error.clear();
    return true;
}

bool EncryptChaChaPoly(
    std::span<const std::uint8_t> keyBytes,
    std::span<const std::uint8_t> plaintext,
    std::span<const std::uint8_t> aad,
    std::array<std::uint8_t, DmpSecureSession::kNonceSize>& nonce,
    std::vector<std::uint8_t>& ciphertext,
    std::array<std::uint8_t, DmpSecureSession::kTagSize>& tag,
    std::string& error) {
    auto status = BCryptGenRandom(
        nullptr,
        nonce.data(),
        static_cast<ULONG>(nonce.size()),
        BCRYPT_USE_SYSTEM_PREFERRED_RNG);
    if (!Succeeded(status)) {
        error = StatusMessage("BCryptGenRandom", status);
        return false;
    }

    AlgorithmHandle algorithm;
    std::vector<std::uint8_t> keyObject;
    KeyHandle key;
    if (!CreateChaChaKey(
            keyBytes,
            algorithm,
            key,
            keyObject,
            error)) {
        return false;
    }

    BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO authInfo;
    BCRYPT_INIT_AUTH_MODE_INFO(authInfo);
    authInfo.pbNonce = nonce.data();
    authInfo.cbNonce = static_cast<ULONG>(nonce.size());
    authInfo.pbAuthData =
        aad.empty() ? nullptr : const_cast<PUCHAR>(aad.data());
    authInfo.cbAuthData = static_cast<ULONG>(aad.size());
    authInfo.pbTag = tag.data();
    authInfo.cbTag = static_cast<ULONG>(tag.size());

    ciphertext.resize(plaintext.size());
    std::uint8_t emptyInput = 0;
    std::uint8_t emptyOutput = 0;
    auto* inputPointer = plaintext.empty()
        ? &emptyInput
        : const_cast<PUCHAR>(plaintext.data());
    auto* outputPointer = ciphertext.empty()
        ? &emptyOutput
        : ciphertext.data();

    ULONG written = 0;
    status = BCryptEncrypt(
        key.Get(),
        inputPointer,
        static_cast<ULONG>(plaintext.size()),
        &authInfo,
        nullptr,
        0,
        outputPointer,
        static_cast<ULONG>(ciphertext.size()),
        &written,
        0);
    if (!Succeeded(status) ||
        written != ciphertext.size()) {
        error = StatusMessage("BCryptEncrypt", status);
        ciphertext.clear();
        return false;
    }

    error.clear();
    return true;
}

bool DecryptChaChaPoly(
    std::span<const std::uint8_t> keyBytes,
    std::span<const std::uint8_t> ciphertext,
    std::span<const std::uint8_t> aad,
    std::span<const std::uint8_t> nonce,
    std::span<const std::uint8_t> tag,
    std::vector<std::uint8_t>& plaintext,
    std::string& error) {
    AlgorithmHandle algorithm;
    std::vector<std::uint8_t> keyObject;
    KeyHandle key;
    if (!CreateChaChaKey(
            keyBytes,
            algorithm,
            key,
            keyObject,
            error)) {
        return false;
    }

    BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO authInfo;
    BCRYPT_INIT_AUTH_MODE_INFO(authInfo);
    authInfo.pbNonce =
        const_cast<PUCHAR>(nonce.data());
    authInfo.cbNonce = static_cast<ULONG>(nonce.size());
    authInfo.pbAuthData =
        aad.empty() ? nullptr : const_cast<PUCHAR>(aad.data());
    authInfo.cbAuthData = static_cast<ULONG>(aad.size());
    authInfo.pbTag =
        const_cast<PUCHAR>(tag.data());
    authInfo.cbTag = static_cast<ULONG>(tag.size());

    plaintext.resize(ciphertext.size());
    std::uint8_t emptyInput = 0;
    std::uint8_t emptyOutput = 0;
    auto* inputPointer = ciphertext.empty()
        ? &emptyInput
        : const_cast<PUCHAR>(ciphertext.data());
    auto* outputPointer = plaintext.empty()
        ? &emptyOutput
        : plaintext.data();

    ULONG written = 0;
    const auto status = BCryptDecrypt(
        key.Get(),
        inputPointer,
        static_cast<ULONG>(ciphertext.size()),
        &authInfo,
        nullptr,
        0,
        outputPointer,
        static_cast<ULONG>(plaintext.size()),
        &written,
        0);
    if (!Succeeded(status) ||
        written != plaintext.size()) {
        error =
            "DisplayMesh secure-session payload authentication failed";
        plaintext.clear();
        return false;
    }

    error.clear();
    return true;
}

}  // namespace

bool DmpSecureSession::DeriveFromSharedSecret(
    DmpSecureRole role,
    std::span<const std::uint8_t> sharedSecret,
    std::span<const std::uint8_t> receiverChallenge,
    std::span<const std::uint8_t> hostChallenge,
    DmpSecureSession& output,
    std::string& error) {
    if (sharedSecret.empty()) {
        error = "DisplayMesh secure-session shared secret is empty";
        return false;
    }
    if (receiverChallenge.size() != kChallengeSize ||
        hostChallenge.size() != kChallengeSize) {
        error = "DisplayMesh secure-session challenges are invalid";
        return false;
    }

    std::vector<std::uint8_t> transcript;
    constexpr std::string_view label =
        "DMP1-SECURE-SESSION";
    transcript.insert(
        transcript.end(),
        label.begin(),
        label.end());
    transcript.insert(
        transcript.end(),
        receiverChallenge.begin(),
        receiverChallenge.end());
    transcript.insert(
        transcript.end(),
        hostChallenge.begin(),
        hostChallenge.end());

    std::array<std::uint8_t, kSha256Size> salt{};
    if (!Sha256(
            transcript,
            salt,
            error)) {
        return false;
    }

    std::array<std::uint8_t, kKeySize> hostToReceiver{};
    std::array<std::uint8_t, kKeySize> receiverToHost{};

    if (!HkdfSha256OneBlock(
            sharedSecret,
            salt,
            "DMP1-HOST-TO-RECEIVER",
            hostToReceiver,
            error) ||
        !HkdfSha256OneBlock(
            sharedSecret,
            salt,
            "DMP1-RECEIVER-TO-HOST",
            receiverToHost,
            error)) {
        return false;
    }

    if (role == DmpSecureRole::Host) {
        output.sendKey_ = hostToReceiver;
        output.receiveKey_ = receiverToHost;
    } else {
        output.sendKey_ = receiverToHost;
        output.receiveKey_ = hostToReceiver;
    }
    output.ready_ = true;
    error.clear();
    return true;
}

bool DmpSecureSession::IsReady() const noexcept {
    return ready_;
}

bool DmpSecureSession::Seal(
    std::span<const std::uint8_t> plaintext,
    DmpMessageType type,
    std::uint16_t flags,
    std::uint32_t sequence,
    std::vector<std::uint8_t>& combined,
    std::string& error) const {
    if (!ready_) {
        error = "DisplayMesh secure session is not ready";
        return false;
    }
    if (!ValidatePayloadSize(
            type,
            plaintext.size(),
            0,
            error)) {
        return false;
    }

    const auto authenticatedFlags =
        static_cast<std::uint16_t>(
            flags | kDmpEncryptedPayloadFlag);
    const auto aad =
        AdditionalAuthenticatedData(
            type,
            authenticatedFlags,
            sequence);

    std::array<std::uint8_t, kNonceSize> nonce{};
    std::array<std::uint8_t, kTagSize> tag{};
    std::vector<std::uint8_t> ciphertext;
    if (!EncryptChaChaPoly(
            sendKey_,
            plaintext,
            aad,
            nonce,
            ciphertext,
            tag,
            error)) {
        return false;
    }

    combined.clear();
    combined.reserve(
        nonce.size() +
        ciphertext.size() +
        tag.size());
    combined.insert(
        combined.end(),
        nonce.begin(),
        nonce.end());
    combined.insert(
        combined.end(),
        ciphertext.begin(),
        ciphertext.end());
    combined.insert(
        combined.end(),
        tag.begin(),
        tag.end());
    error.clear();
    return true;
}

bool DmpSecureSession::Open(
    std::span<const std::uint8_t> combined,
    DmpMessageType type,
    std::uint16_t flags,
    std::uint32_t sequence,
    std::vector<std::uint8_t>& plaintext,
    std::string& error) const {
    if (!ready_) {
        error = "DisplayMesh secure session is not ready";
        return false;
    }
    if ((flags & kDmpEncryptedPayloadFlag) == 0U) {
        error = "DisplayMesh rejected plaintext post-pairing frame";
        return false;
    }
    if (!ValidatePayloadSize(
            type,
            combined.size(),
            flags,
            error)) {
        return false;
    }
    if (combined.size() < kNonceSize + kTagSize) {
        error = "DisplayMesh secure-session payload is truncated";
        return false;
    }

    const auto nonce =
        combined.first(kNonceSize);
    const auto tag =
        combined.last(kTagSize);
    const auto ciphertext =
        combined.subspan(
            kNonceSize,
            combined.size() -
                kNonceSize -
                kTagSize);
    const auto aad =
        AdditionalAuthenticatedData(
            type,
            flags,
            sequence);

    if (!DecryptChaChaPoly(
            receiveKey_,
            ciphertext,
            aad,
            nonce,
            tag,
            plaintext,
            error)) {
        return false;
    }

    std::string sizeError;
    if (!ValidatePayloadSize(
            type,
            plaintext.size(),
            0,
            sizeError)) {
        error =
            "DisplayMesh decrypted payload violates DMP size contract";
        plaintext.clear();
        return false;
    }

    error.clear();
    return true;
}

}  // namespace displaymesh
