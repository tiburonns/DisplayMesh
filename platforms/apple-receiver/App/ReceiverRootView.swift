import SwiftUI

struct ReceiverRootView: View {
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var receiver: ReceiverViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false
    @State private var resumeReceiverWhenActive = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoSurfaceRepresentable(controller: receiver.videoSurface)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            TouchSurfaceRepresentable(
                onInput: receiver.captureInput,
                onPanelDescriptor: receiver.updatePanelDescriptor
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack(spacing: 16) {
                topBar
                Spacer()

                if !isConnected {
                    onboardingCard
                } else if !receiver.sessionAuthorized {
                    pairingCard
                }

                Spacer()

                if receiver.diagnosticsEnabled {
                    diagnosticsBar
                }
            }
            .padding()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(languageStore)
                .environmentObject(receiver)
                .environment(\.locale, languageStore.selection.locale)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background:
                resumeReceiverWhenActive = receiver.isListening
                if resumeReceiverWhenActive {
                    receiver.stopReceiver()
                }

            case .active:
                if resumeReceiverWhenActive {
                    resumeReceiverWhenActive = false
                    receiver.startReceiver()
                }

            case .inactive:
                break

            @unknown default:
                break
            }
        }
    }

    private var isConnected: Bool {
        if case .connected = receiver.listenerState { return true }
        return false
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            statusBadge
            Spacer()

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("action.settings"))
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 9, height: 9)

            switch receiver.listenerState {
            case .stopped: Text("status.stopped")
            case .starting: Text("status.starting")
            case .ready: Text("status.ready")
            case .waiting: Text("status.waiting")
            case .connected: Text("status.connected")
            case .failed: Text("status.failed")
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch receiver.listenerState {
        case .connected: return .green
        case .ready, .starting: return .blue
        case .waiting: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }

    private var onboardingCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 44, weight: .medium))
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 7) {
                Text("receiver.title")
                    .font(.title2.bold())

                Text("receiver.subtitle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            listenerDetail

            Button {
                receiver.startReceiver()
            } label: {
                Label("action.startReceiver", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(receiver.isListening)

            if receiver.isListening {
                Button("action.stopReceiver") {
                    receiver.stopReceiver()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(maxWidth: 520)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var pairingCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 38))
                .symbolRenderingMode(.hierarchical)

            if let pairing = receiver.pendingPairing {
                Text("pairing.verifyTitle")
                    .font(.title3.bold())

                Text(
                    String(
                        format: NSLocalizedString(
                            "pairing.peerMessage",
                            comment: ""
                        ),
                        pairing.peerName
                    )
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                if receiver.pendingPeerPreviouslyTrusted {
                    Label(
                        "pairing.previouslyTrusted",
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
                }

                Text(
                    String(
                        format: NSLocalizedString(
                            "pairing.identityFingerprint",
                            comment: ""
                        ),
                        pairing.identityFingerprint.uppercased()
                    )
                )
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)

                Text(pairing.normalizedVerificationCode)
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .tracking(5)
                    .accessibilityLabel(
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "pairing.codeAccessibility",
                                    comment: ""
                                ),
                                pairing.normalizedVerificationCode
                            )
                        )
                    )

                HStack {
                    Button("action.reject", role: .destructive) {
                        receiver.rejectPairing()
                    }
                    .buttonStyle(.bordered)

                    Button("action.allow") {
                        receiver.acceptPairing()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
                    .controlSize(.large)

                Text("pairing.waitingTitle")
                    .font(.title3.bold())

                Text("pairing.waitingMessage")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let protocolError = receiver.lastProtocolError {
                Text(protocolError)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("action.disconnect") {
                receiver.stopReceiver()
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var listenerDetail: some View {
        switch receiver.listenerState {
        case .ready(let port):
            Text(
                String(
                    format: NSLocalizedString(
                        "receiver.readyPort",
                        comment: ""
                    ),
                    port
                )
            )
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)

        case .waiting(let message), .failed(let message):
            Text(message)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.center)

        default:
            Text("receiver.localNetworkHint")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var diagnosticsBar: some View {
        let metrics = receiver.videoMetrics

        return HStack(spacing: 14) {
            Label(
                String(
                    format: NSLocalizedString("diagnostics.fps", comment: ""),
                    metrics.framesPerSecond
                ),
                systemImage: "gauge.with.dots.needle.67percent"
            )

            Text(
                String(
                    format: NSLocalizedString("diagnostics.decode", comment: ""),
                    metrics.averageDecodeMilliseconds
                )
            )

            Text(
                String(
                    format: NSLocalizedString("diagnostics.bitrate", comment: ""),
                    metrics.megabitsPerSecond
                )
            )

            Text(
                String(
                    format: NSLocalizedString("diagnostics.dropped", comment: ""),
                    metrics.droppedFrames
                )
            )

            if metrics.hardwareAccelerated == true {
                Image(systemName: "bolt.fill")
                    .accessibilityLabel(Text("diagnostics.hardware"))
            }

            if let panel = receiver.panelDescriptor {
                Text("\(panel.pixelWidth)×\(panel.pixelHeight)")
                Text("\(panel.maximumFramesPerSecond) Hz")
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("diagnostics.title"))
    }
}
