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

/// Tracks recent microphone-stream liveness independently from the
/// capture-wide peak used by final integrity diagnostics. A historical speech
/// peak must not hide a stream that later stops delivering input.
public struct MicrophoneStreamContinuityMonitor: Equatable, Sendable {
    public static let minimumMeterPowerDecibels: Float = -160
    public static let defaultLivenessThresholdDecibels: Float = -100

    public let dropoutDelaySeconds: TimeInterval
    public let livenessThresholdDecibels: Float

    private var generation: UInt = 0
    private var lastLiveSignalElapsedSeconds: TimeInterval?

    public init(
        dropoutDelaySeconds: TimeInterval = 2.5,
        livenessThresholdDecibels: Float = Self.defaultLivenessThresholdDecibels
    ) {
        self.dropoutDelaySeconds = dropoutDelaySeconds
        self.livenessThresholdDecibels = livenessThresholdDecibels
    }

    public mutating func observe(
        elapsedSeconds: TimeInterval,
        powerDecibels: Float,
        generation: UInt = 0
    ) {
        guard generation == self.generation else { return }
        guard powerDecibels >= livenessThresholdDecibels else { return }
        lastLiveSignalElapsedSeconds = elapsedSeconds
    }

    public func health(
        elapsedSeconds: TimeInterval
    ) -> MicrophoneSignalHealth {
        if let lastLiveSignalElapsedSeconds {
            return elapsedSeconds - lastLiveSignalElapsedSeconds
                >= dropoutDelaySeconds
                ? .absent
                : .detected
        }
        return elapsedSeconds >= dropoutDelaySeconds ? .absent : .warmingUp
    }

    public mutating func reset(generation: UInt = 0) {
        self.generation = generation
        lastLiveSignalElapsedSeconds = nil
    }
}
