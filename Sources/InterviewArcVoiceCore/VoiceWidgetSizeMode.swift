import Foundation

public enum VoiceWidgetSizeMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case standard
    case mini

    public static let preferenceKey = "voice.widgetSizeMode"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .standard: "Standard"
        case .mini: "Mini"
        }
    }

    public static func load(
        from defaults: UserDefaults = .standard
    ) -> VoiceWidgetSizeMode {
        guard let rawValue = defaults.string(forKey: preferenceKey),
              let mode = VoiceWidgetSizeMode(rawValue: rawValue) else {
            return .standard
        }
        return mode
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }
}

public enum MiniWidgetLayout: Equatable, Sendable {
    case microphoneOnly
    case timer
}

public enum MiniWidgetPresentationPolicy {
    public static func layout(
        linkEnabled: Bool,
        hasActivityTimer: Bool,
        hasSessionTimer: Bool
    ) -> MiniWidgetLayout {
        guard linkEnabled, hasActivityTimer || hasSessionTimer else {
            return .microphoneOnly
        }
        return .timer
    }

    public static func width(for layout: MiniWidgetLayout) -> CGFloat {
        switch layout {
        case .microphoneOnly:
            FloatingWidgetWindowPolicy.miniMicrophoneWidth
        case .timer:
            FloatingWidgetWindowPolicy.miniTimerWidth
        }
    }

    public static func timerSource(
        hasActivityTimer: Bool,
        hasSessionTimer: Bool
    ) -> MiniWidgetTimerSource? {
        if hasActivityTimer { return .activity }
        if hasSessionTimer { return .session }
        return nil
    }
}

public enum MiniWidgetTimerSource: Equatable, Sendable {
    case activity
    case session
}

public enum MiniWidgetAudioGlowPolicy {
    public static let quietDecibels: Double = -55
    public static let loudDecibels: Double = -8

    public static func normalizedLevel(decibels: Double) -> Double {
        let span = loudDecibels - quietDecibels
        guard span > 0 else { return 0 }
        return max(0, min(1, (decibels - quietDecibels) / span))
    }

    public static func smoothedLevel(
        previous: Double,
        current: Double,
        response: Double = 0.18
    ) -> Double {
        let clampedResponse = max(0, min(1, response))
        let value = previous + ((current - previous) * clampedResponse)
        return max(0, min(1, value))
    }

    public static func pulseDuration(level: Double) -> TimeInterval {
        1.45 - (max(0, min(1, level)) * 0.70)
    }
}
