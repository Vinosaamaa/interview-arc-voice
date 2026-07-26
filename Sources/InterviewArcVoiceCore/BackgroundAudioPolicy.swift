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
    public let originalVolume: Float
    public let appliedVolume: Float

    public init(
        deviceUID: String,
        originalVolume: Float,
        appliedVolume: Float
    ) {
        self.deviceUID = deviceUID
        self.originalVolume = originalVolume
        self.appliedVolume = appliedVolume
    }
}

public struct BackgroundAudioSessionSnapshot: Codable, Equatable, Sendable {
    public private(set) var routes: [BackgroundAudioVolumeSnapshot]

    public init(routes: [BackgroundAudioVolumeSnapshot] = []) {
        self.routes = routes
    }

    public func route(deviceUID: String) -> BackgroundAudioVolumeSnapshot? {
        routes.first { $0.deviceUID == deviceUID }
    }

    public mutating func remember(_ snapshot: BackgroundAudioVolumeSnapshot) {
        routes.removeAll { $0.deviceUID == snapshot.deviceUID }
        routes.append(snapshot)
    }
}

public enum BackgroundAudioPolicy {
    public static let defaultRelativeLevel: Double = 0.20

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
}
