import Foundation
import Security

enum PeerTrustStatus: Equatable {
    case new
    case trusted
    case identityChanged
}

struct TrustedPeerRecord: Codable, Equatable, Identifiable {
    var id: String { peerID }

    let peerID: String
    let peerName: String
    let identityPublicKey: Data
    let trustedAt: Date
}

private protocol TrustedPeerPersistence {
    func load() throws -> Data?
    func save(_ data: Data?) throws
}

private enum TrustedPeerPersistenceError: Error, LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "DisplayMesh trust-store Keychain error: \(status)"
        }
    }
}

private struct KeychainTrustedPeerPersistence: TrustedPeerPersistence {
    private let service = "com.tiburonns.DisplayMesh.receiverTrust"
    private let account = "trusted-peers-v1"

    func load() throws -> Data? {
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
            throw TrustedPeerPersistenceError.keychain(status)
        }

        return item as? Data
    }

    func save(_ data: Data?) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]

        guard let data else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw TrustedPeerPersistenceError.keychain(status)
            }
            return
        }

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw TrustedPeerPersistenceError.keychain(updateStatus)
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
            throw TrustedPeerPersistenceError.keychain(addStatus)
        }
    }
}

private struct UserDefaultsTrustedPeerPersistence: TrustedPeerPersistence {
    let defaults: UserDefaults
    let storageKey: String

    func load() throws -> Data? {
        defaults.data(forKey: storageKey)
    }

    func save(_ data: Data?) throws {
        if let data {
            defaults.set(data, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }
}

final class TrustedPeerStore {
    private let persistence: any TrustedPeerPersistence

    private(set) var peers: [TrustedPeerRecord]
    private(set) var lastErrorDescription: String?

    init() {
        self.persistence = KeychainTrustedPeerPersistence()
        self.peers = []
        load()
    }

    init(defaults: UserDefaults) {
        self.persistence = UserDefaultsTrustedPeerPersistence(
            defaults: defaults,
            storageKey: "displaymesh.trustedPeers.test.v1"
        )
        self.peers = []
        load()
    }

    var count: Int {
        peers.count
    }

    func status(for request: PairingRequest) -> PeerTrustStatus {
        guard let record = peers.first(
            where: { $0.peerID == request.peerID }
        ) else {
            return .new
        }

        return record.identityPublicKey == request.identityPublicKey
            ? .trusted
            : .identityChanged
    }

    @discardableResult
    func trust(_ request: PairingRequest) -> Bool {
        let previous = peers
        let record = TrustedPeerRecord(
            peerID: request.peerID,
            peerName: request.peerName,
            identityPublicKey: request.identityPublicKey,
            trustedAt: Date()
        )

        if let index = peers.firstIndex(
            where: { $0.peerID == request.peerID }
        ) {
            peers[index] = record
        } else {
            peers.append(record)
        }

        guard persist() else {
            peers = previous
            return false
        }

        return true
    }

    @discardableResult
    func forgetAll() -> Bool {
        let previous = peers
        peers.removeAll()

        do {
            try persistence.save(nil)
            lastErrorDescription = nil
            return true
        } catch {
            peers = previous
            lastErrorDescription = error.localizedDescription
            return false
        }
    }

    private func load() {
        do {
            guard let data = try persistence.load() else {
                peers = []
                lastErrorDescription = nil
                return
            }

            peers = try JSONDecoder().decode(
                [TrustedPeerRecord].self,
                from: data
            )
            lastErrorDescription = nil
        } catch {
            peers = []
            lastErrorDescription = error.localizedDescription
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            let data = try JSONEncoder().encode(peers)
            try persistence.save(data)
            lastErrorDescription = nil
            return true
        } catch {
            lastErrorDescription = error.localizedDescription
            return false
        }
    }
}
