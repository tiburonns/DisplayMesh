import Combine
import CoreMedia
import Foundation
import UIKit

@MainActor
final class ReceiverViewModel: ObservableObject {
    @Published private(set) var listenerState: ReceiverListenerState = .stopped
    @Published private(set) var panelDescriptor: PanelDescriptor?
    @Published private(set) var capturedInputSamples: UInt64 = 0
    @Published private(set) var sessionAuthorized = false
    @Published private(set) var pendingPairing: PairingRequest?
    @Published private(set) var lastProtocolError: String?
    @Published private(set) var videoMetrics = ReceiverVideoMetrics()
    @Published var diagnosticsEnabled = false

    let videoSurface = VideoSurfaceController()

    private let listener: ReceiverListener
    private let videoDecoder: H264VideoDecoder
    private var lastKeyframeRequestTime: TimeInterval = 0
    private var lastTelemetrySentTime: TimeInterval = 0
    private var pairingTimeoutTask: Task<Void, Never>?

    init(
        listener: ReceiverListener = ReceiverListener(),
        videoDecoder: H264VideoDecoder = H264VideoDecoder()
    ) {
        self.listener = listener
        self.videoDecoder = videoDecoder

        listener.onState = { [weak self] state in
            guard let self else { return }
            listenerState = state

            switch state {
            case .connected:
                resetAuthorization()
                lastProtocolError = nil
                videoDecoder.reset()
                videoSurface.clear()
            case .stopped, .failed:
                resetAuthorization()
                videoDecoder.reset()
                videoSurface.clear()
            default:
                break
            }
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
            UIApplication.shared.isIdleTimerDisabled = true
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
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func updatePanelDescriptor(_ descriptor: PanelDescriptor) {
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
        guard let request = pendingPairing, request.isValid else {
            lastProtocolError = "Invalid pairing request"
            pendingPairing = nil
            sessionAuthorized = false
            return
        }

        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = nil
        sessionAuthorized = true
        pendingPairing = nil
        lastProtocolError = nil
        sendPairingResponse(accepted: true)
        sendPanelDescriptorIfAuthorized()
        requestKeyframe(force: true)
    }

    func rejectPairing() {
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = nil
        sessionAuthorized = false
        pendingPairing = nil
        videoDecoder.reset()
        videoSurface.clear()
        sendPairingResponse(accepted: false)
    }

    private func handle(_ frame: DMPFrame) {
        switch frame.type {
        case .hello:
            resetAuthorization()
            videoDecoder.reset()
            videoSurface.clear()

        case .pairing:
            do {
                let request = try JSONDecoder().decode(
                    PairingRequest.self,
                    from: frame.payload
                )
                guard request.isValid else {
                    throw PairingValidationError.invalidRequest
                }

                pendingPairing = request
                sessionAuthorized = false
                lastProtocolError = nil
                schedulePairingTimeout()
            } catch {
                pendingPairing = nil
                sessionAuthorized = false
                lastProtocolError = error.localizedDescription
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

        case .capabilities, .panelDescriptor, .input, .telemetry,
             .keyframeRequest, .error:
            break
        }
    }

    private func requestKeyframe(force: Bool = false) {
        guard sessionAuthorized else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastKeyframeRequestTime >= 0.25 else { return }
        lastKeyframeRequestTime = now
        listener.send(type: .keyframeRequest, payload: Data())
    }

    private func sendPairingResponse(accepted: Bool) {
        let response = PairingResponse(
            accepted: accepted,
            receiverName: UIDevice.current.name,
            protocolVersion: Int(DMPFrame.version)
        )

        guard let payload = try? JSONEncoder().encode(response) else { return }
        listener.send(type: .pairing, payload: payload)
    }

    private func sendTelemetryIfNeeded(_ metrics: ReceiverVideoMetrics) {
        guard sessionAuthorized else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTelemetrySentTime >= 1 else { return }
        lastTelemetrySentTime = now

        let telemetry = ReceiverTelemetry(metrics: metrics)
        guard let payload = try? JSONEncoder().encode(telemetry) else { return }
        listener.send(type: .telemetry, payload: payload)
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
        guard pendingPairing != nil, !sessionAuthorized else { return }
        pendingPairing = nil
        pairingTimeoutTask = nil
        lastProtocolError = PairingValidationError.expired.localizedDescription
        sendPairingResponse(accepted: false)
    }

    private func sendPanelDescriptorIfAuthorized() {
        guard sessionAuthorized,
              let panelDescriptor,
              let payload = try? JSONEncoder().encode(panelDescriptor) else {
            return
        }

        listener.send(type: .panelDescriptor, payload: payload)
    }

    private func resetAuthorization() {
        pairingTimeoutTask?.cancel()
        pairingTimeoutTask = nil
        sessionAuthorized = false
        pendingPairing = nil
        lastKeyframeRequestTime = 0
        lastTelemetrySentTime = 0
    }
}

private enum PairingValidationError: LocalizedError {
    case invalidRequest
    case expired

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid DisplayMesh pairing request"
        case .expired:
            return "DisplayMesh pairing request expired"
        }
    }
}
