enum ReceiverAwakePolicy {
    static func shouldKeepScreenAwake(
        listenerState: ReceiverListenerState,
        sessionAuthorized: Bool
    ) -> Bool {
        guard sessionAuthorized else { return false }

        if case .connected = listenerState {
            return true
        }

        return false
    }
}
