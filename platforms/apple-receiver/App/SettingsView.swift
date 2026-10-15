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

                Section("settings.support.section") {
                    NavigationLink {
                        DisplayMeshFeedbackView()
                    } label: {
                        Label(
                            "settings.support.feedback",
                            systemImage: "bubble.left.and.bubble.right"
                        )
                    }

                    Link(
                        destination: URL(string: "https://github.com/tiburonns/DisplayMesh/issues")!
                    ) {
                        Label(
                            "settings.support.issues",
                            systemImage: "exclamationmark.bubble"
                        )
                    }
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


private struct DisplayMeshFeedbackView: View {
    private enum Category: String, CaseIterable, Identifiable {
        case question
        case suggestion
        case bug
        case feedback

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .question: "feedback.category.question"
            case .suggestion: "feedback.category.suggestion"
            case .bug: "feedback.category.bug"
            case .feedback: "feedback.category.feedback"
            }
        }

        var issuePrefix: String {
            switch self {
            case .question: "Question"
            case .suggestion: "Suggestion"
            case .bug: "Bug"
            case .feedback: "Feedback"
            }
        }
    }

    @Environment(\.openURL) private var openURL
    @State private var category = Category.question
    @State private var message = ""

    var body: some View {
        Form {
            Section("feedback.type") {
                Picker("feedback.category", selection: $category) {
                    ForEach(Category.allCases) { option in
                        Text(option.titleKey).tag(option)
                    }
                }
            }

            Section("feedback.message") {
                TextEditor(text: $message)
                    .frame(minHeight: 160)

                Text("feedback.privacy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    submit()
                } label: {
                    Label("feedback.send", systemImage: "paperplane.fill")
                }
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("feedback.review")
            }
        }
        .navigationTitle("feedback.title")
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func submit() {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/tiburonns/DisplayMesh/issues/new"
        components.queryItems = [
            URLQueryItem(name: "title", value: "[\(category.issuePrefix)] "),
            URLQueryItem(
                name: "body",
                value: """
                \(message)

                ---
                App: DisplayMesh
                Version: \(appVersion)
                Component: Apple receiver
                """
            )
        ]

        if let url = components.url {
            openURL(url)
        }
    }
}
