import CryptoKit
import Foundation
import Security

struct HostIdentity {
    let peerID: String
    let privateKey: P256.Signing.PrivateKey

    var fingerprint: String {
        SHA256.hash(data: privateKey.publicKey.rawRepresentation)
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func makePairingRequest(
        peerName: String,
        verificationCode: String,
        challenge: Data
    ) throws -> PairingRequest {
        try PairingRequest.signed(
            peerName: peerName,
            peerID: peerID,
            verificationCode: verificationCode,
            challenge: challenge,
            privateKey: privateKey
        )
    }
}

enum HostIdentityStoreError: Error, LocalizedError {
    case keychain(OSStatus)
    case invalidPeerID
    case invalidPrivateKey

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "DisplayMesh host identity Keychain error: \(status)"
        case .invalidPeerID:
            return "DisplayMesh host peer ID is invalid"
        case .invalidPrivateKey:
            return "DisplayMesh host signing key is invalid"
        }
    }
}

enum HostIdentityStore {
    private static let service = "com.tiburonns.DisplayMesh.hostIdentity"
    private static let peerIDAccount = "peer-id-v1"
    private static let signingKeyAccount = "p256-signing-key-v1"

    static func loadOrCreate() throws -> HostIdentity {
        let peerID: String
        if let data = try read(account: peerIDAccount),
           let stored = String(data: data, encoding: .utf8),
           UUID(uuidString: stored) != nil {
            peerID = stored
        } else {
            peerID = UUID().uuidString
            try write(
                Data(peerID.utf8),
                account: peerIDAccount
            )
        }

        let privateKey: P256.Signing.PrivateKey
        if let data = try read(account: signingKeyAccount) {
            do {
                privateKey = try P256.Signing.PrivateKey(
                    rawRepresentation: data
                )
            } catch {
                throw HostIdentityStoreError.invalidPrivateKey
            }
        } else {
            privateKey = P256.Signing.PrivateKey()
            try write(
                privateKey.rawRepresentation,
                account: signingKeyAccount
            )
        }

        return HostIdentity(
            peerID: peerID,
            privateKey: privateKey
        )
    }

    private static func read(account: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &item
        )

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw HostIdentityStoreError.keychain(status)
        }

        return item as? Data
    }

    private static func write(
        _ data: Data,
        account: String
    ) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw HostIdentityStoreError.keychain(updateStatus)
        }

        var insert = query
        insert[kSecValueData] = data
        insert[kSecAttrAccessible] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(
            insert as CFDictionary,
            nil
        )
        guard addStatus == errSecSuccess else {
            throw HostIdentityStoreError.keychain(addStatus)
        }
    }
}
