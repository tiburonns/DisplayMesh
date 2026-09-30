import CryptoKit
import Foundation
import Security

struct ReceiverIdentity {
    let receiverID: String
    let privateKey: P256.Signing.PrivateKey

    var fingerprint: String {
        SHA256.hash(data: privateKey.publicKey.rawRepresentation)
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func makePairingResponse(
        accepted: Bool,
        receiverName: String,
        receiverChallenge: Data,
        hostChallenge: Data,
        keyAgreementPublicKey: Data
    ) throws -> PairingResponse {
        try PairingResponse.signed(
            accepted: accepted,
            receiverName: receiverName,
            receiverID: receiverID,
            challenge: receiverChallenge,
            hostChallenge: hostChallenge,
            keyAgreementPublicKey: keyAgreementPublicKey,
            privateKey: privateKey
        )
    }
}

enum ReceiverIdentityStoreError: Error, LocalizedError {
    case keychain(OSStatus)
    case invalidReceiverID
    case invalidPrivateKey

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "DisplayMesh receiver identity Keychain error: \(status)"
        case .invalidReceiverID:
            return "DisplayMesh receiver ID is invalid"
        case .invalidPrivateKey:
            return "DisplayMesh receiver signing key is invalid"
        }
    }
}

enum ReceiverIdentityStore {
    private static let service = "com.tiburonns.DisplayMesh.receiverIdentity"
    private static let receiverIDAccount = "receiver-id-v1"
    private static let signingKeyAccount = "p256-signing-key-v1"

    static func loadOrCreate() throws -> ReceiverIdentity {
        let receiverID: String
        if let data = try read(account: receiverIDAccount),
           let stored = String(data: data, encoding: .utf8) {
            guard UUID(uuidString: stored) != nil else {
                throw ReceiverIdentityStoreError.invalidReceiverID
            }
            receiverID = stored
        } else {
            receiverID = UUID().uuidString
            try write(Data(receiverID.utf8), account: receiverIDAccount)
        }

        let privateKey: P256.Signing.PrivateKey
        if let data = try read(account: signingKeyAccount) {
            do {
                privateKey = try P256.Signing.PrivateKey(
                    rawRepresentation: data
                )
            } catch {
                throw ReceiverIdentityStoreError.invalidPrivateKey
            }
        } else {
            privateKey = P256.Signing.PrivateKey()
            try write(
                privateKey.rawRepresentation,
                account: signingKeyAccount
            )
        }

        return ReceiverIdentity(
            receiverID: receiverID,
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
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw ReceiverIdentityStoreError.keychain(status)
        }
        return item as? Data
    }

    private static func write(_ data: Data, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let update = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else {
            throw ReceiverIdentityStoreError.keychain(update)
        }

        var insert = query
        insert[kSecValueData] = data
        insert[kSecAttrAccessible] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let add = SecItemAdd(insert as CFDictionary, nil)
        guard add == errSecSuccess else {
            throw ReceiverIdentityStoreError.keychain(add)
        }
    }
}
