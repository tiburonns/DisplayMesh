import SwiftUI

struct ReceiverRootView: View {
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var receiver: ReceiverViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TouchSurfaceRepresentable(
                onInput: receiver.captureInput,
                onPanelDescriptor: receiver.updatePanelDescriptor
            )
            .ignoresSafeArea()
            .accessibilityHidden(true)

            VStack(spacing: 16) {
                topBar
                Spacer()
                if !isConnected { onboardingCard }
                else if !receiver.sessionAuthorized { pairingCard }
                Spacer()
                if receiver.diagnosticsEnabled { diagnosticsBar }
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
            if phase == .background { receiver.stopReceiver() }
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
            Button { showingSettings = true } label: {
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
            Circle().fill(statusColor).frame(width: 9, height: 9)
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
                Text("receiver.title").font(.title2.bold())
                Text("receiver.subtitle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            listenerDetail

            Button { receiver.startReceiver() } label: {
                Label("action.startReceiver", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(receiver.isListening)

            if receiver.isListening {
                Button("action.stopReceiver") { receiver.stopReceiver() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(maxWidth: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var pairingCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 38))
                .symbolRenderingMode(.hierarchical)
            Text("pairing.title").font(.title3.bold())
            Text("pairing.message")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("action.disconnect") { receiver.stopReceiver() }
                .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: 500)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    @ViewBuilder
    private var listenerDetail: some View {
        switch receiver.listenerState {
        case .ready(let port):
            Text(String(format: NSLocalizedString("receiver.readyPort", comment: ""), port))
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
        HStack(spacing: 14) {
            Label("\(receiver.capturedInputSamples)", systemImage: "hand.tap")
            if let panel = receiver.panelDescriptor {
                Text("\(panel.pixelWidth)×\(panel.pixelHeight)")
                Text("\(panel.maximumFramesPerSecond) Hz")
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityLabel(Text("diagnostics.title"))
    }
}
