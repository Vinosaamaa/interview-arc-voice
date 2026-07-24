public enum RecordingCommandAction: Equatable, Sendable {
    case start
    case stop
    case ignore
}

public enum RecordingCommandPolicy {
    public static func action(
        isRecording: Bool,
        isStarting: Bool,
        isBusy: Bool
    ) -> RecordingCommandAction {
        if isRecording { return .stop }
        if isStarting || isBusy { return .ignore }
        return .start
    }
}

public enum RecordingPreparationPolicy {
    public static func canPrepare(
        hasGroqCredential: Bool,
        isBusy: Bool
    ) -> Bool {
        hasGroqCredential && !isBusy
    }
}
