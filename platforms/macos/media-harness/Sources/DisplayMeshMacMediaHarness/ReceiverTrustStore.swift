import Foundation
import Security

enum ReceiverTrustStatus: Equatable {
    case new
    case trusted
    case identityChanged
}

struct TrustedReceiverRecord: Codable, Equatable, Identifiable {
    var id: String { receiverID }

    let receiverID: String
    let receiverName: String
    let identityPublicKey: Data
    let trustedAt: Date
}

private protocol ReceiverTrustPersistence {
    func load() throws -> Data?
    func save(_ data: Data?) throws
}

enum ReceiverTrustStoreError: Error, LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "DisplayMesh receiver trust Keychain error: \(status)"
        }
    }
}

private struct KeychainReceiverTrustPersistence: ReceiverTrustPersistence {
    private let service = "com.tiburonns.DisplayMesh.host.receiverTrust"
    private let account = "trusted-receivers-v1"

    func load() throws -> Data? {
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
            throw ReceiverTrustStoreError.keychain(status)
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
                throw ReceiverTrustStoreError.keychain(status)
            }
            return
        }
        let update = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else {
            throw ReceiverTrustStoreError.keychain(update)
        }
        var insert = query
        insert[kSecValueData] = data
        insert[kSecAttrAccessible] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let add = SecItemAdd(insert as CFDictionary, nil)
        guard add == errSecSuccess else {
            throw ReceiverTrustStoreError.keychain(add)
        }
    }
}

private struct UserDefaultsReceiverTrustPersistence: ReceiverTrustPersistence {
    let defaults: UserDefaults
    let storageKey: String

    func load() throws -> Data? { defaults.data(forKey: storageKey) }

    func save(_ data: Data?) throws {
        if let data {
            defaults.set(data, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }
}

final class ReceiverTrustStore {
    private let persistence: any ReceiverTrustPersistence
    private(set) var receivers: [TrustedReceiverRecord]
    private(set) var lastErrorDescription: String?

    init() {
        persistence = KeychainReceiverTrustPersistence()
        receivers = []
        load()
    }

    init(defaults: UserDefaults) {
        persistence = UserDefaultsReceiverTrustPersistence(
            defaults: defaults,
            storageKey: "displaymesh.receiverTrust.test.v1"
        )
        receivers = []
        load()
    }

    var isOperational: Bool { lastErrorDescription == nil }

    func status(for response: PairingResponse) -> ReceiverTrustStatus {
        guard let record = receivers.first(
            where: { $0.receiverID == response.receiverID }
        ) else {
            return .new
        }
        return record.identityPublicKey == response.identityPublicKey
            ? .trusted
            : .identityChanged
    }

    @discardableResult
    func trust(_ response: PairingResponse) -> Bool {
        let previous = receivers
        let record = TrustedReceiverRecord(
            receiverID: response.receiverID,
            receiverName: response.receiverName,
            identityPublicKey: response.identityPublicKey,
            trustedAt: Date()
        )
        if let index = receivers.firstIndex(
            where: { $0.receiverID == response.receiverID }
        ) {
            receivers[index] = record
        } else {
            receivers.append(record)
        }
        guard persist() else {
            receivers = previous
            return false
        }
        return true
    }

    private func load() {
        do {
            guard let data = try persistence.load() else {
                receivers = []
                lastErrorDescription = nil
                return
            }
            receivers = try JSONDecoder().decode(
                [TrustedReceiverRecord].self,
                from: data
            )
            lastErrorDescription = nil
        } catch {
            receivers = []
            lastErrorDescription = error.localizedDescription
        }
    }

    @discardableResult
    private func persist() -> Bool {
        do {
            let data = try JSONEncoder().encode(receivers)
            try persistence.save(data)
            lastErrorDescription = nil
            return true
        } catch {
            lastErrorDescription = error.localizedDescription
            return false
        }
    }
}
