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
    case singleTimer
    case dualTimer
}

public enum MiniWidgetPresentationPolicy {
    public static func layout(
        linkEnabled: Bool,
        hasActivityTimer: Bool,
        hasSessionTimer: Bool,
        recordingActive: Bool,
        sessionTimerDisclosed: Bool
    ) -> MiniWidgetLayout {
        guard !recordingActive,
              linkEnabled,
              hasActivityTimer || hasSessionTimer else {
            return .microphoneOnly
        }
        if hasActivityTimer, hasSessionTimer, sessionTimerDisclosed {
            return .dualTimer
        }
        return .singleTimer
    }

    public static func width(for layout: MiniWidgetLayout) -> CGFloat {
        switch layout {
        case .microphoneOnly:
            FloatingWidgetWindowPolicy.miniMicrophoneWidth
        case .singleTimer:
            FloatingWidgetWindowPolicy.miniTimerWidth
        case .dualTimer:
            FloatingWidgetWindowPolicy.miniDualTimerWidth
        }
    }

    public static func canDiscloseSessionTimer(
        hasActivityTimer: Bool,
        hasSessionTimer: Bool
    ) -> Bool {
        hasActivityTimer && hasSessionTimer
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
    // AVAudioRecorder's ordinary close-range speech commonly sits around
    // -35...-22 dB. Saturating at -22 dB gives conversational speech enough
    // visual range without requiring the user to shout.
    public static let quietDecibels: Double = -55
    public static let loudDecibels: Double = -22
    public static let persistentRingDiameter: CGFloat = 44
    public static let persistentRingOpacity = 0.52
    public static let persistentLineWidth: CGFloat = 2.4
    public static let minimumRingDiameter: CGFloat = 44
    public static let maximumRingDiameter: CGFloat = 48
    public static let minimumRingOpacity = 0.46
    public static let maximumRingOpacity = 1.0
    public static let minimumLineWidth: CGFloat = 2.5
    public static let maximumLineWidth: CGFloat = 6.5

    public static func normalizedLevel(decibels: Double) -> Double {
        let span = loudDecibels - quietDecibels
        guard span > 0 else { return 0 }
        return max(0, min(1, (decibels - quietDecibels) / span))
    }

    public static func smoothedLevel(
        previous: Double,
        current: Double,
        response: Double = 0.42
    ) -> Double {
        let clampedResponse = max(0, min(1, response))
        let value = previous + ((current - previous) * clampedResponse)
        return max(0, min(1, value))
    }

    public static func pulseDuration(level: Double) -> TimeInterval {
        1.25 - (max(0, min(1, level)) * 0.72)
    }

    public static func ringDiameter(level: Double, pulse: Double) -> CGFloat {
        let boundedLevel = max(0, min(1, level))
        let boundedPulse = max(0, min(1, pulse))
        return min(
            maximumRingDiameter,
            minimumRingDiameter
                + (CGFloat(boundedLevel) * 3.0)
                + (CGFloat(boundedPulse) * 1.0)
        )
    }

    public static func ringOpacity(level: Double, pulse: Double) -> Double {
        let boundedLevel = max(0, min(1, level))
        let boundedPulse = max(0, min(1, pulse))
        return min(
            maximumRingOpacity,
            minimumRingOpacity + (boundedLevel * 0.58) + (boundedPulse * 0.14)
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

    public static func meterArcFraction(level: Double) -> Double {
        max(0, min(1, level))
    }
}
