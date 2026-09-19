import SwiftUI

@main
struct DisplayMeshReceiverApp: App {
    @StateObject private var languageStore = AppLanguageStore()
    @StateObject private var receiver = ReceiverViewModel()

    var body: some Scene {
        WindowGroup {
            ReceiverRootView()
                .environmentObject(languageStore)
                .environmentObject(receiver)
                .environment(\.locale, languageStore.selection.locale)
        }
    }
}
