import Foundation

public enum MicrophoneSignalHealth: String, Codable, Equatable, Sendable {
    case warmingUp
    case detected
    case absent
}

public struct MicrophoneSignalPolicy: Equatable, Sendable {
    public static let defaultSignalThresholdDecibels: Float = -65

    public let warningDelaySeconds: TimeInterval
    public let signalThresholdDecibels: Float

    public init(
        warningDelaySeconds: TimeInterval = 2.5,
        signalThresholdDecibels: Float = Self.defaultSignalThresholdDecibels
    ) {
        self.warningDelaySeconds = warningDelaySeconds
        self.signalThresholdDecibels = signalThresholdDecibels
    }

    public func health(
        elapsedSeconds: TimeInterval,
        peakPowerDecibels: Float
    ) -> MicrophoneSignalHealth {
        if peakPowerDecibels >= signalThresholdDecibels {
            return .detected
        }
        if elapsedSeconds >= warningDelaySeconds {
            return .absent
        }
        return .warmingUp
    }
}

public struct MicrophoneStreamRecoveryPolicy: Equatable, Sendable {
    public let maximumAutomaticRestarts: Int

    public init(maximumAutomaticRestarts: Int = 2) {
        self.maximumAutomaticRestarts = maximumAutomaticRestarts
    }

    public func shouldRestart(
        health: MicrophoneSignalHealth,
        completedRestarts: Int,
        captureBackendIsActive: Bool
    ) -> Bool {
        captureBackendIsActive
            && health == .absent
            && completedRestarts < maximumAutomaticRestarts
    }
}
