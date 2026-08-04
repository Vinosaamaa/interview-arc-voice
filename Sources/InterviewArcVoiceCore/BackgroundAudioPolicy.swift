import Foundation

public enum BackgroundAudioRecordingMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case unchanged
    case lower
    case mute

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unchanged: "Leave unchanged"
        case .lower: "Lower while recording"
        case .mute: "Mute while recording"
        }
    }
}

public struct BackgroundAudioVolumeSnapshot: Codable, Equatable, Sendable {
    public let deviceUID: String
    public let nominalSampleRate: Double?
    public let outputChannelCount: UInt32?
    public let originalVolume: Float
    public let appliedVolume: Float

    public init(
        deviceUID: String,
        nominalSampleRate: Double? = nil,
        outputChannelCount: UInt32? = nil,
        originalVolume: Float,
        appliedVolume: Float
    ) {
        self.deviceUID = deviceUID
        self.nominalSampleRate = nominalSampleRate
        self.outputChannelCount = outputChannelCount
        self.originalVolume = originalVolume
        self.appliedVolume = appliedVolume
    }

    public func matches(
        deviceUID: String,
        nominalSampleRate: Double,
        outputChannelCount: UInt32
    ) -> Bool {
        guard self.deviceUID == deviceUID else { return false }
        // Legacy snapshots predate profile-aware routing. Preserve their
        // previous UID-only behavior when decoding an interrupted session.
        guard let storedRate = self.nominalSampleRate,
              let storedChannels = self.outputChannelCount else {
            return true
        }
        return abs(storedRate - nominalSampleRate) < 1
            && storedChannels == outputChannelCount
    }
}

public struct BackgroundAudioSessionSnapshot: Codable, Equatable, Sendable {
    public let baseline: BackgroundAudioVolumeSnapshot?
    public private(set) var routes: [BackgroundAudioVolumeSnapshot]

    public init(
        baseline: BackgroundAudioVolumeSnapshot? = nil,
        routes: [BackgroundAudioVolumeSnapshot] = []
    ) {
        self.baseline = baseline
        self.routes = routes
    }

    public func route(
        deviceUID: String,
        nominalSampleRate: Double,
        outputChannelCount: UInt32
    ) -> BackgroundAudioVolumeSnapshot? {
        routes.first {
            $0.matches(
                deviceUID: deviceUID,
                nominalSampleRate: nominalSampleRate,
                outputChannelCount: outputChannelCount
            )
        }
    }

    public mutating func remember(_ snapshot: BackgroundAudioVolumeSnapshot) {
        routes.removeAll {
            $0.matches(
                deviceUID: snapshot.deviceUID,
                nominalSampleRate: snapshot.nominalSampleRate ?? -1,
                outputChannelCount: snapshot.outputChannelCount ?? 0
            )
        }
        routes.append(snapshot)
    }
}

public struct BackgroundAudioBaselineStabilityTracker: Equatable, Sendable {
    public private(set) var stableSince: TimeInterval?

    public init() {}

    public var isTracking: Bool { stableSince != nil }

    public mutating func observe(
        baselineAtOriginalVolume: Bool,
        now: TimeInterval
    ) -> Bool {
        guard baselineAtOriginalVolume else {
            stableSince = nil
            return false
        }
        guard let stableSince else {
            self.stableSince = now
            return false
        }
        return BackgroundAudioPolicy.baselineRestorationIsStable(
            stableFor: now - stableSince
        )
    }
}

public enum BackgroundAudioPolicy {
    public static let defaultRelativeLevel: Double = 0.20
    /// Bluetooth can briefly expose the original profile, accept a volume
    /// write, and then settle again. Keep the durable baseline until the
    /// original route and volume have stayed stable through that window.
    public static let baselineRestorationStabilitySeconds: TimeInterval = 3

    public static func targetVolume(
        currentVolume: Float,
        mode: BackgroundAudioRecordingMode,
        relativeLevel: Double
    ) -> Float? {
        switch mode {
        case .unchanged:
            return nil
        case .lower:
            return max(0, min(1, currentVolume * Float(relativeLevel)))
        case .mute:
            return 0
        }
    }

    public static func shouldRestore(
        currentVolume: Float,
        snapshot: BackgroundAudioVolumeSnapshot,
        tolerance: Float = 0.015
    ) -> Bool {
        abs(currentVolume - snapshot.appliedVolume) <= tolerance
    }

    public static func shouldReapplyAfterRouteChange(
        currentVolume: Float,
        snapshot: BackgroundAudioVolumeSnapshot,
        tolerance: Float = 0.015
    ) -> Bool {
        abs(currentVolume - snapshot.originalVolume) <= tolerance
    }

    public static func shouldRestoreBaseline(
        currentDeviceUID: String,
        currentNominalSampleRate: Double,
        currentOutputChannelCount: UInt32,
        baseline: BackgroundAudioVolumeSnapshot
    ) -> Bool {
        baseline.matches(
            deviceUID: currentDeviceUID,
            nominalSampleRate: currentNominalSampleRate,
            outputChannelCount: currentOutputChannelCount
        )
    }

    /// A temporary Bluetooth hands-free route must stay ducked until the
    /// original stereo route returns. Restoring the temporary route first
    /// creates a short, loud, low-quality burst after Stop.
    public static func shouldRestoreTemporaryRoute(
        hasPendingBaseline: Bool
    ) -> Bool {
        !hasPendingBaseline
    }

    public static func baselineRestorationIsStable(
        stableFor seconds: TimeInterval
    ) -> Bool {
        seconds >= baselineRestorationStabilitySeconds
    }
}
