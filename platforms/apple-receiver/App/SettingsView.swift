import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var receiver: ReceiverViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var feedbackCategory = "feedback.suggestion"
    @State private var feedbackMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.language.section") {
                    Picker("settings.language.label", selection: $languageStore.selection) {
                        Text("settings.language.system").tag(AppLanguage.system)
                        Text("settings.language.english").tag(AppLanguage.english)
                        Text("settings.language.spanish").tag(AppLanguage.spanish)
                    }
                }

                Section("settings.connection.section") {
                    LabeledContent(
                        "settings.connection.port",
                        value: "\(ReceiverListener.port.rawValue)"
                    )
                    LabeledContent(
                        "settings.connection.service",
                        value: "_displaymesh._tcp"
                    )
                    Text("settings.connection.explanation")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("settings.security.section") {
                    Label(
                        "settings.security.pairingRequired",
                        systemImage: "person.badge.shield.checkmark"
                    )

                    Text("settings.security.pairingExplanation")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    LabeledContent(
                        "settings.security.trustedPeers",
                        value: "\(receiver.trustedPeerCount)"
                    )

                    if receiver.trustedPeerCount > 0 {
                        Button(
                            "settings.security.forgetTrustedPeers",
                            role: .destructive
                        ) {
                            receiver.forgetTrustedPeers()
                        }
                    }

                    Label(
                        "settings.security.transportDevelopment",
                        systemImage: "exclamationmark.shield"
                    )
                    .foregroundStyle(.orange)

                    Text("settings.security.transportExplanation")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("settings.diagnostics.section") {
                    Toggle(
                        "settings.diagnostics.toggle",
                        isOn: $receiver.diagnosticsEnabled
                    )
                }

                Section("settings.about.section") {
                    LabeledContent("settings.about.protocol", value: "DMPv1")
                    LabeledContent("settings.about.version", value: appVersion)
                }

                Section("feedback.title") {
                    Picker("feedback.category", selection: $feedbackCategory) {
                        ForEach(["feedback.bug", "feedback.comment", "feedback.suggestion", "feedback.other"], id: \.self) {
                            Text($0)
                        }
                    }
                    TextField("feedback.message", text: $feedbackMessage, axis: .vertical)
                        .lineLimit(5...10)
                    Button("feedback.send", action: sendFeedback)
                        .disabled(feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("feedback.emailDraft")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("settings.title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String

        if let version, let build {
            return "\(version) (\(build))"
        }

        return version ?? "—"
    }

    private func sendFeedback() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "tiburonns@icloud.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "[DisplayMesh] [\(String(localized: String.LocalizationValue(feedbackCategory)))]"),
            URLQueryItem(name: "body", value: "\(feedbackMessage)\n\nDisplayMesh \(appVersion)")
        ]
        if let url = components.url { openURL(url) }
    }
}
