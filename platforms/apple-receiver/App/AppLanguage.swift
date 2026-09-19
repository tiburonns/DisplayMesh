import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case spanish

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        case .english: return Locale(identifier: "en")
        case .spanish: return Locale(identifier: "es")
        }
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    static let storageKey = "displaymesh.receiver.language"

    @Published var selection: AppLanguage {
        didSet { defaults.set(selection.rawValue, forKey: Self.storageKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.storageKey),
           let stored = AppLanguage(rawValue: raw) {
            selection = stored
        } else {
            selection = .system
        }
    }
}
