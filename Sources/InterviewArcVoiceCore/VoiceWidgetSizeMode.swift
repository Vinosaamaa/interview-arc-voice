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
    public static let minimumRingDiameter: CGFloat = 40
    public static let maximumRingDiameter: CGFloat = 44
    public static let minimumRingOpacity = 0.62
    public static let maximumRingOpacity = 1.0
    public static let minimumLineWidth: CGFloat = 2.2
    public static let maximumLineWidth: CGFloat = 3.6

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

    public static func ringDiameter(level: Double, pulse: Double) -> CGFloat {
        let boundedLevel = max(0, min(1, level))
        let boundedPulse = max(0, min(1, pulse))
        return min(
            maximumRingDiameter,
            minimumRingDiameter
                + (CGFloat(boundedLevel) * 2.5)
                + (CGFloat(boundedPulse) * 1.5)
        )
    }

    public static func ringOpacity(level: Double, pulse: Double) -> Double {
        let boundedLevel = max(0, min(1, level))
        let boundedPulse = max(0, min(1, pulse))
        return min(
            maximumRingOpacity,
            minimumRingOpacity + (boundedLevel * 0.26) + (boundedPulse * 0.12)
        )
    }

    public static func ringLineWidth(level: Double) -> CGFloat {
        let boundedLevel = max(0, min(1, level))
        return minimumLineWidth
            + (CGFloat(boundedLevel) * (maximumLineWidth - minimumLineWidth))
    }

    public static func shadowOpacity(level: Double) -> Double {
        0.50 + (max(0, min(1, level)) * 0.34)
    }

    public static func shadowRadius(level: Double) -> CGFloat {
        4 + (CGFloat(max(0, min(1, level))) * 5)
    }
}
