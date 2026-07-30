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

public enum MiniWidgetExpandingStopPolicy {
    // AVAudioRecorder's ordinary close-range speech commonly sits around
    // -35...-22 dB. Saturating at -22 dB gives conversational speech enough
    // visual range without requiring the user to shout.
    public static let quietDecibels: Double = -55
    public static let loudDecibels: Double = -22
    public static let activationThreshold = 0.16
    public static let minimumSize: CGFloat = 4
    public static let maximumSize: CGFloat = 28
    public static let maximumCornerRadius: CGFloat = 6
    public static let attackResponse = 0.60
    public static let releaseResponse = 0.25

    public static func normalizedLevel(decibels: Double) -> Double {
        let span = loudDecibels - quietDecibels
        guard span > 0 else { return 0 }
        return max(0, min(1, (decibels - quietDecibels) / span))
    }

    public static func smoothedLevel(
        previous: Double,
        current: Double
    ) -> Double {
        let response = current >= previous ? attackResponse : releaseResponse
        let clampedResponse = max(0, min(1, response))
        let value = previous + ((current - previous) * clampedResponse)
        return max(0, min(1, value))
    }

    public static func visibleLevel(level: Double) -> Double {
        let bounded = max(0, min(1, level))
        guard bounded > activationThreshold else { return 0 }
        return min(
            1,
            (bounded - activationThreshold) / (1 - activationThreshold)
        )
    }

    public static func stopSize(level: Double) -> CGFloat {
        let visible = visibleLevel(level: level)
        let emphasized = pow(visible, 0.72)
        return minimumSize
            + CGFloat(emphasized) * (maximumSize - minimumSize)
    }

    public static func cornerRadius(for size: CGFloat) -> CGFloat {
        min(
            max(0, size / 2),
            maximumCornerRadius
        )
    }

    public static func accessibilityDescription(level: Double) -> String {
        switch visibleLevel(level: level) {
        case 0:
            "No sound detected"
        case ..<0.35:
            "Quiet sound detected"
        case ..<0.78:
            "Sound detected"
        default:
            "Loud sound detected"
        }
    }
}
