import Foundation

public enum RecordingCommandAction: Equatable, Sendable {
    case start
    case stop
    case cancelStart
    case ignore
}

public enum RecordingCommandPolicy {
    public static func action(
        isRecording: Bool,
        isStarting: Bool,
        isBusy: Bool
    ) -> RecordingCommandAction {
        if isRecording { return .stop }
        if isStarting { return .cancelStart }
        if isBusy { return .ignore }
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

public enum RecordingStartupPresentationPolicy {
    public static func shouldBeginPresentation(
        captureBackendIsReady: Bool,
        widgetSizeMode: VoiceWidgetSizeMode
    ) -> Bool {
        _ = widgetSizeMode
        captureBackendIsReady
    }
}

public enum MicrophoneStartupReadinessDecision: Equatable, Sendable {
    case wait
    case ready
    case startFallback
    case fail
}

public struct MicrophoneStartupReadinessPolicy: Equatable, Sendable {
    public let primaryTimeoutSeconds: TimeInterval
    public let fallbackTimeoutSeconds: TimeInterval

    public init(
        primaryTimeoutSeconds: TimeInterval = 4,
        fallbackTimeoutSeconds: TimeInterval = 2
    ) {
        self.primaryTimeoutSeconds = primaryTimeoutSeconds
        self.fallbackTimeoutSeconds = fallbackTimeoutSeconds
    }

    public func decision(
        elapsedSeconds: TimeInterval,
        captureBackendIsAdvancing: Bool,
        isUsingFallback: Bool
    ) -> MicrophoneStartupReadinessDecision {
        if captureBackendIsAdvancing { return .ready }
        let timeout = isUsingFallback ? fallbackTimeoutSeconds : primaryTimeoutSeconds
        if elapsedSeconds < timeout { return .wait }
        return isUsingFallback ? .fail : .startFallback
    }
}

public enum RecordingTerminationPolicy {
    public static func shouldSurfaceUnexpectedTermination(
        isCaptureActive: Bool,
        completionWasExpected: Bool,
        alreadyReported: Bool
    ) -> Bool {
        isCaptureActive && !completionWasExpected && !alreadyReported
    }
}
