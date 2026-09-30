import Combine
import CoreMedia
import CryptoKit
import Foundation
import UIKit

@MainActor
final class ReceiverViewModel: ObservableObject {
    @Published private(set) var listenerState: ReceiverListenerState = .stopped
    @Published private(set) var panelDescriptor: PanelDescriptor?
    @Published private(set) var capturedInputSamples: UInt64 = 0
    @Published private(set) var sessionAuthorized = false
    @Published private(set) var pendingPairing: PairingRequest?
    @Published private(set) var pendingPeerPreviouslyTrusted = false
    @Published private(set) var trustedPeerCount: Int
    @Published private(set) var lastProtocolError: String?
    @Published private(set) var videoMetrics = ReceiverVideoMetrics()
    @Published var diagnosticsEnabled = false

    let videoSurface = VideoSurfaceController()

    private let listener: ReceiverListener
    private let videoDecoder: H264VideoDecoder
    private let trustedPeerStore: TrustedPeerStore
    private let receiverIdentity: ReceiverIdentity?
    private var lastKeyframeRequestTime: TimeInterval = 0
    private var lastTelemetrySentTime: TimeInterval = 0
    private var admissionTimeoutTask: Task<Void, Never>?
    private var pairingTimeoutTask: Task<Void, Never>?
    private var receiverChallenge: Data?
    private var invalidPairingAttempts = 0
    private static let maximumInvalidPairingAttempts = 3

    init(
        listener: ReceiverListener = ReceiverListener(),
        videoDecoder: H264VideoDecoder = H264VideoDecoder(),
        trustedPeerStore: TrustedPeerStore = TrustedPeerStore(),
        receiverIdentity: ReceiverIdentity? = nil
    ) {
        self.listener = listener
        self.videoDecoder = videoDecoder
        self.trustedPeerStore = trustedPeerStore

        let resolvedIdentity: ReceiverIdentity?
        let identityError: String?
        if let receiverIdentity {
            resolvedIdentity = receiverIdentity
            identityError = nil
        } else {
            do {
                resolvedIdentity = try ReceiverIdentityStore.loadOrCreate()
                identityError = nil
            } catch {
                resolvedIdentity = nil
                identityError = error.localizedDescription
            }
        }
        self.receiverIdentity = resolvedIdentity
        self.trustedPeerCount = trustedPeerStore.count
        self.lastProtocolError =
            trustedPeerStore.lastErrorDescription ?? identityError

        listener.onState = { [weak self] state in
            guard let self else { return }
            listenerState = state

            switch state {
            case .connected:
                resetAuthorization()
                invalidPairingAttempts = 0
                videoDecoder.reset()
                videoSurface.clear()

                guard self.receiverIdentity != nil else {
                    lastProtocolError =
                        PairingValidationError
                            .receiverIdentityUnavailable
                            .localizedDescription
                    listener.disconnectCurrent()
                    return
                }

                lastProtocolError = nil
                sendReceiverHello()
                scheduleAdmissionTimeout()
            case .stopped, .failed:
                resetAuthorization()
                invalidPairingAttempts = 0
                videoDecoder.reset()
                videoSurface.clear()
            default:
                break
            }

            updateIdleTimerPolicy()
        }

        listener.onFrame = { [weak self] frame in
            self?.handle(frame)
        }

        videoDecoder.onFrame = { [weak self] pixelBuffer, _ in
            self?.videoSurface.present(pixelBuffer)
        }

        videoDecoder.onMetrics = { [weak self] metrics in
            guard let self else { return }
            videoMetrics = metrics
            sendTelemetryIfNeeded(metrics)
        }

        videoDecoder.onNeedsKeyframe = { [weak self] in
            self?.requestKeyframe()
        }

        videoDecoder.onError = { [weak self] message in
            self?.lastProtocolError = message
        }
    }

    var isListening: Bool {
        switch listenerState {
        case .stopped, .failed: return false
        case .starting, .ready, .waiting, .connected: return true
        }
    }

    func startReceiver() {
        guard !isListening else { return }

        do {
            try listener.start()
            updateIdleTimerPolicy()
        } catch {
            listenerState = .failed(error.localizedDescription)
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    func stopReceiver() {
        listener.stop()
        listenerState = .stopped
        resetAuthorization()
        videoDecoder.reset()
        videoSurface.clear()
        updateIdleTimerPolicy()
    }

    func updatePanelDescriptor(_ descriptor: PanelDescriptor) {
        guard descriptor.isValid else {
            lastProtocolError = "DisplayMesh receiver panel descriptor is invalid"
            return
        }
        guard panelDescriptor != descriptor else { return }
        panelDescriptor = descriptor
        sendPanelDescriptorIfAuthorized()
    }

    func captureInput(_ event: ReceiverInputEvent) {
        capturedInputSamples &+= 1
        guard sessionAuthorized else { return }

        do {
            let payload = try DMPInputSample(event: event).encoded()
            listener.send(type: .input, payload: payload)
        } catch {
            lastProtocolError = error.localizedDescription
        }
    }

    func acceptPairing() {
        guard let request = pendingPairing,
              let activeReceiverChallenge = receiverChallenge,
              request.isAuthentic(expectedChallenge: activeReceiverChallenge) else {
            lastProtocolError = PairingValidationError.invalidRequest.localizedDescription
            pendingPairing = nil
            pendingPeerPreviouslyTrusted = false
            sessionAuthorized = false
            listener.disconnectCurrent()
            resetAuthorization()
            return
        }

        guard trustedPeerStore.trust(request) else {
            lastProtocolError =
                trustedPeerStore.lastErrorDescription
                ?? "Could not persist DisplayMesh trusted identity"
            sessionAuthorized = false
            sendPairingResponse(accepted: false, request: request)
            listener.disconnectCurrent()
            resetAuthorization()
            return
        }
        trustedPeerCount = trustedPeerStore.count

        admissionTimeoutTask?.cancel()
        admissionTimeoutTask = nil
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = nil
        do {
            try establishSecureSession(request: request)
        } catch {
            lastProtocolError = error.localizedDescription
            sessionAuthorized = false
            listener.disconnectCurrent()
            resetAuthorization()
            return
        }

        sessionAuthorized = true
        updateIdleTimerPolicy()
        invalidPairingAttempts = 0
        pendingPairing = nil
        pendingPeerPreviouslyTrusted = false
        lastProtocolError = nil
        receiverChallenge = nil
        sendCapabilitiesIfAuthorized()
        sendPanelDescriptorIfAuthorized()
        requestKeyframe(force: true)
    }

    func rejectPairing() {
        let request = pendingPairing
        admissionTimeoutTask?.cancel()
        admissionTimeoutTask = nil
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = nil
        sessionAuthorized = false
        pendingPairing = nil
        pendingPeerPreviouslyTrusted = false
        videoDecoder.reset()
        videoSurface.clear()
        if let request {
            sendPairingResponse(accepted: false, request: request)
        }
        listener.disconnectCurrent()
        resetAuthorization()
    }

    private func handle(_ frame: DMPFrame) {
        guard ReceiverProtocolGate.permits(
            frame.type,
            authorized: sessionAuthorized
        ) else {
            lastProtocolError =
                "Rejected unexpected DMP \(frame.type) frame " +
                (sessionAuthorized ? "after authorization" : "before authorization")
            listener.disconnectCurrent()
            resetAuthorization()
            videoDecoder.reset()
            videoSurface.clear()
            return
        }

        switch frame.type {
        case .hello:
            lastProtocolError = "Unexpected host hello frame"

        case .pairing:
            do {
                let request = try JSONDecoder().decode(
                    PairingRequest.self,
                    from: frame.payload
                )
                guard let receiverChallenge,
                      request.isAuthentic(
                          expectedChallenge: receiverChallenge
                      ) else {
                    throw PairingValidationError.invalidSignature
                }

                guard trustedPeerStore.isOperational else {
                    throw PairingValidationError.trustStoreUnavailable(
                        trustedPeerStore.lastErrorDescription
                            ?? "Unknown Keychain error"
                    )
                }

                admissionTimeoutTask?.cancel()
                admissionTimeoutTask = nil

                switch trustedPeerStore.status(for: request) {
                case .identityChanged:
                    pendingPairing = nil
                    pendingPeerPreviouslyTrusted = false
                    sessionAuthorized = false
                    lastProtocolError =
                        PairingValidationError.identityChanged.localizedDescription
                    sendPairingResponse(
                        accepted: false,
                        request: request
                    )
                    listener.disconnectCurrent()
                    resetAuthorization()

                case .trusted:
                    pendingPairing = request
                    pendingPeerPreviouslyTrusted = true
                    sessionAuthorized = false
                    lastProtocolError = nil
                    schedulePairingTimeout()

                case .new:
                    pendingPairing = request
                    pendingPeerPreviouslyTrusted = false
                    sessionAuthorized = false
                    lastProtocolError = nil
                    schedulePairingTimeout()
                }
            } catch {
                recordInvalidPairing(error)
            }

        case .video:
            guard sessionAuthorized else {
                lastProtocolError = "Rejected video before pairing authorization"
                return
            }

            do {
                let packet = try DMPVideoPacket.decode(frame.payload)
                videoDecoder.submit(packet, sequence: frame.sequence)
            } catch {
                lastProtocolError = error.localizedDescription
                requestKeyframe()
            }

        case .capabilities:
            break

        case .ping:
            listener.send(type: .pong, payload: frame.payload)

        case .error:
            lastProtocolError =
                String(data: frame.payload, encoding: .utf8)
                ?? "DisplayMesh host reported a binary protocol error"

        case .panelDescriptor, .input, .telemetry, .keyframeRequest, .pong:
            break
        }
    }

    private func recordInvalidPairing(_ error: Error) {
        invalidPairingAttempts += 1
        pendingPairing = nil
        pendingPeerPreviouslyTrusted = false
        sessionAuthorized = false
        lastProtocolError = error.localizedDescription

        guard invalidPairingAttempts < Self.maximumInvalidPairingAttempts else {
            listener.disconnectCurrent()
            resetAuthorization()
            return
        }

        rotateReceiverChallenge()
    }

    private func requestKeyframe(force: Bool = false) {
        guard sessionAuthorized else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastKeyframeRequestTime >= 0.25 else { return }
        lastKeyframeRequestTime = now
        listener.send(type: .keyframeRequest, payload: Data())
    }

    func forgetTrustedPeers() {
        let shouldRevokeCurrentSession =
            sessionAuthorized || pendingPairing != nil

        if trustedPeerStore.forgetAll() {
            trustedPeerCount = 0
            lastProtocolError = nil

            if shouldRevokeCurrentSession {
                stopReceiver()
            }
        } else {
            lastProtocolError =
                trustedPeerStore.lastErrorDescription
                ?? "Could not clear DisplayMesh trusted identities"
        }
    }

    private func rotateReceiverChallenge() {
        receiverChallenge = nil
        sendReceiverHello()
    }

    private func sendReceiverHello() {
        do {
            let hello = try ReceiverHello.make()
            receiverChallenge = hello.challenge
            let payload = try JSONEncoder().encode(hello)
            listener.send(type: .hello, payload: payload)
        } catch {
            receiverChallenge = nil
            lastProtocolError = error.localizedDescription
        }
    }

    private func establishSecureSession(
        request: PairingRequest
    ) throws {
        guard let receiverIdentity else {
            throw PairingValidationError.receiverIdentityUnavailable
        }

        let receiverKeyAgreement = P256.KeyAgreement.PrivateKey()
        let hostPublicKey = try P256.KeyAgreement.PublicKey(
            rawRepresentation: request.keyAgreementPublicKey
        )
        let response = try receiverIdentity.makePairingResponse(
            accepted: true,
            receiverName: "DisplayMesh Receiver",
            receiverChallenge: request.challenge,
            hostChallenge: request.hostChallenge,
            keyAgreementPublicKey:
                receiverKeyAgreement.publicKey.rawRepresentation
        )
        let payload = try JSONEncoder().encode(response)
        listener.send(type: .pairing, payload: payload)

        let sharedSecret = try receiverKeyAgreement.sharedSecretFromKeyAgreement(
            with: hostPublicKey
        )
        listener.installSecureSession(
            try DMPSecureSession.derive(
                role: .receiver,
                sharedSecret: sharedSecret,
                receiverChallenge: request.challenge,
                hostChallenge: request.hostChallenge
            )
        )
    }

    private func sendPairingResponse(
        accepted: Bool,
        request: PairingRequest
    ) {
        guard let receiverIdentity else {
            lastProtocolError =
                PairingValidationError
                    .receiverIdentityUnavailable
                    .localizedDescription
            listener.disconnectCurrent()
            return
        }

        do {
            let rejectionKeyAgreement = P256.KeyAgreement.PrivateKey()
            let response = try receiverIdentity.makePairingResponse(
                accepted: accepted,
                receiverName: "DisplayMesh Receiver",
                receiverChallenge: request.challenge,
                hostChallenge: request.hostChallenge,
                keyAgreementPublicKey:
                    rejectionKeyAgreement.publicKey.rawRepresentation
            )
            let payload = try JSONEncoder().encode(response)
            listener.send(type: .pairing, payload: payload)
        } catch {
            lastProtocolError = error.localizedDescription
            listener.disconnectCurrent()
        }
    }

    private func sendTelemetryIfNeeded(_ metrics: ReceiverVideoMetrics) {
        guard sessionAuthorized else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard ReceiverTelemetryCadencePolicy.shouldSend(
            now: now,
            lastSentAt: lastTelemetrySentTime,
            decodeQueueDepth: metrics.decodeQueueDepth
        ) else {
            return
        }
        lastTelemetrySentTime = now

        let telemetry = ReceiverTelemetry(metrics: metrics)
        guard let payload = try? JSONEncoder().encode(telemetry) else { return }
        listener.send(type: .telemetry, payload: payload)
    }

    private func scheduleAdmissionTimeout() {
        admissionTimeoutTask?.cancel()
        admissionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            expireAdmission()
        }
    }

    private func expireAdmission() {
        guard !sessionAuthorized,
              pendingPairing == nil else {
            return
        }

        admissionTimeoutTask = nil
        lastProtocolError =
            PairingValidationError.admissionExpired.localizedDescription
        listener.disconnectCurrent()
        resetAuthorization()
    }

    private func schedulePairingTimeout() {
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            expirePairing()
        }
    }

    private func expirePairing() {
        guard let request = pendingPairing, !sessionAuthorized else { return }
        pendingPairing = nil
        pendingPeerPreviouslyTrusted = false
        pairingTimeoutTask = nil
        lastProtocolError = PairingValidationError.expired.localizedDescription
        sendPairingResponse(accepted: false, request: request)
        listener.disconnectCurrent()
        resetAuthorization()
    }

    private func sendCapabilitiesIfAuthorized() {
        guard sessionAuthorized else { return }

        let capabilities = ReceiverCapabilities.development(
            panel: panelDescriptor,
            encryptedTransport: true
        )
        guard capabilities.isValid,
              let payload = try? JSONEncoder().encode(capabilities) else {
            lastProtocolError =
                "DisplayMesh receiver capabilities are invalid"
            return
        }

        listener.send(type: .capabilities, payload: payload)
    }

    private func sendPanelDescriptorIfAuthorized() {
        guard sessionAuthorized,
              let panelDescriptor,
              panelDescriptor.isValid,
              let payload = try? JSONEncoder().encode(panelDescriptor) else {
            return
        }

        listener.send(type: .panelDescriptor, payload: payload)
    }

    private func updateIdleTimerPolicy() {
        UIApplication.shared.isIdleTimerDisabled =
            ReceiverAwakePolicy.shouldKeepScreenAwake(
                listenerState: listenerState,
                sessionAuthorized: sessionAuthorized
            )
    }

    private func resetAuthorization() {
        admissionTimeoutTask?.cancel()
        admissionTimeoutTask = nil
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = nil
        sessionAuthorized = false
        pendingPairing = nil
        pendingPeerPreviouslyTrusted = false
        receiverChallenge = nil
        lastKeyframeRequestTime = 0
        lastTelemetrySentTime = 0
        updateIdleTimerPolicy()
    }
}

private enum PairingValidationError: LocalizedError {
    case invalidRequest
    case invalidSignature
    case identityChanged
    case trustStoreUnavailable(String)
    case receiverIdentityUnavailable
    case admissionExpired
    case expired

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid DisplayMesh pairing request"
        case .invalidSignature:
            return "DisplayMesh pairing identity could not be verified"
        case .identityChanged:
            return "This computer's DisplayMesh identity changed. Forget trusted computers before pairing it again."
        case .trustStoreUnavailable(let detail):
            return "DisplayMesh cannot verify trusted computers: \(detail)"
        case .receiverIdentityUnavailable:
            return "DisplayMesh receiver identity is unavailable; pairing is disabled"
        case .admissionExpired:
            return "DisplayMesh connection did not present a valid pairing request in time"
        case .expired:
            return "DisplayMesh pairing request expired"
        }
    }
}
