import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var languageStore: AppLanguageStore
    @EnvironmentObject private var receiver: ReceiverViewModel
    @Environment(\.dismiss) private var dismiss

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
}
