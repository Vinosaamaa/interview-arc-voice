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
        hasUsableInput: Bool,
        isUsingFallback: Bool
    ) -> MicrophoneStartupReadinessDecision {
        if hasUsableInput { return .ready }
        let timeout = isUsingFallback ? fallbackTimeoutSeconds : primaryTimeoutSeconds
        if elapsedSeconds < timeout { return .wait }
        return isUsingFallback ? .fail : .startFallback
    }
}

public struct BluetoothMicrophoneRouteReadinessPolicy: Equatable, Sendable {
    public let minimumStableSeconds: TimeInterval

    public init(minimumStableSeconds: TimeInterval = 0.6) {
        self.minimumStableSeconds = minimumStableSeconds
    }

    public func isReady(
        baselineIsBluetooth: Bool,
        currentRouteIsAvailable: Bool,
        currentRouteMatchesBaseline: Bool,
        changedRouteStableSeconds: TimeInterval
    ) -> Bool {
        if !baselineIsBluetooth { return true }
        guard currentRouteIsAvailable, !currentRouteMatchesBaseline else {
            return false
        }
        return changedRouteStableSeconds >= minimumStableSeconds
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
