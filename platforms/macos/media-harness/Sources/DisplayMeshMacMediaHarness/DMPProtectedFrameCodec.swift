import Foundation

enum DMPProtectedFrameError: Error, LocalizedError, Equatable {
    case secureSessionRequired(DMPMessageType)
    case unexpectedEncryptedHandshake(DMPMessageType)
    case plaintextRejected(DMPMessageType)

    var errorDescription: String? {
        switch self {
        case .secureSessionRequired(let type):
            return "DisplayMesh secure session is required before sending \(type)"
        case .unexpectedEncryptedHandshake(let type):
            return "DisplayMesh handshake frame must remain plaintext: \(type)"
        case .plaintextRejected(let type):
            return "DisplayMesh rejected plaintext post-pairing frame: \(type)"
        }
    }
}

struct DMPProtectedFrameCodec {
    private(set) var secureSession: DMPSecureSession?

    var isSecure: Bool {
        secureSession != nil
    }

    mutating func install(_ session: DMPSecureSession) {
        secureSession = session
    }

    mutating func clear() {
        secureSession = nil
    }

    func outboundFrame(
        type: DMPMessageType,
        payload: Data,
        sequence: UInt32
    ) throws -> DMPFrame {
        if Self.isHandshake(type) {
            guard secureSession == nil else {
                throw DMPProtectedFrameError
                    .unexpectedEncryptedHandshake(type)
            }
            return DMPFrame(
                type: type,
                flags: 0,
                sequence: sequence,
                payload: payload
            )
        }

        guard let secureSession else {
            throw DMPProtectedFrameError
                .secureSessionRequired(type)
        }

        let encrypted = try secureSession.seal(
            payload,
            type: type,
            flags: 0,
            sequence: sequence
        )
        return DMPFrame(
            type: type,
            flags: DMPFrame.encryptedPayloadFlag,
            sequence: sequence,
            payload: encrypted
        )
    }

    func inboundFrame(_ frame: DMPFrame) throws -> DMPFrame {
        if Self.isHandshake(frame.type) {
            guard frame.flags & DMPFrame.encryptedPayloadFlag == 0 else {
                throw DMPProtectedFrameError
                    .unexpectedEncryptedHandshake(frame.type)
            }
            guard secureSession == nil else {
                throw DMPProtectedFrameError
                    .unexpectedEncryptedHandshake(frame.type)
            }
            return frame
        }

        guard let secureSession else {
            throw DMPProtectedFrameError
                .secureSessionRequired(frame.type)
        }
        guard frame.flags & DMPFrame.encryptedPayloadFlag != 0 else {
            throw DMPProtectedFrameError
                .plaintextRejected(frame.type)
        }

        let plaintext = try secureSession.open(
            frame.payload,
            type: frame.type,
            flags: frame.flags,
            sequence: frame.sequence
        )
        return DMPFrame(
            type: frame.type,
            flags: 0,
            sequence: frame.sequence,
            payload: plaintext
        )
    }

    private static func isHandshake(
        _ type: DMPMessageType
    ) -> Bool {
        type == .hello || type == .pairing
    }
}
