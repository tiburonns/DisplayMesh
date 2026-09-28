import Foundation

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

final class TrustedPeerStore {
    private let defaults: UserDefaults
    private let storageKey = "displaymesh.trustedPeers.v1"

    private(set) var peers: [TrustedPeerRecord]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(
               [TrustedPeerRecord].self,
               from: data
           ) {
            peers = decoded
        } else {
            peers = []
        }
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

    func trust(_ request: PairingRequest) {
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

        persist()
    }

    func forgetAll() {
        peers.removeAll()
        defaults.removeObject(forKey: storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(peers) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
