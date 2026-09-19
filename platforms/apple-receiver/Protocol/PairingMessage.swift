import Foundation

struct PairingRequest: Codable, Equatable {
    let peerName: String
    let verificationCode: String
    let protocolVersion: Int

    var normalizedVerificationCode: String {
        verificationCode.filter(\.isNumber)
    }

    var isValid: Bool {
        protocolVersion == Int(DMPFrame.version)
            && normalizedVerificationCode.count == 6
    }
}

struct PairingResponse: Codable, Equatable {
    let accepted: Bool
    let receiverName: String
    let protocolVersion: Int
}
