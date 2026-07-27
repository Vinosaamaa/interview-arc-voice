import Foundation

public enum CaptureRouteKind: Equatable, Sendable {
    case linked
    case general
}

public struct CaptureRoutingPolicy: Sendable {
    public init() {}

    public func route(
        linkToInterviewArc: Bool,
        hasFocusedActivity: Bool
    ) -> CaptureRouteKind {
        guard linkToInterviewArc, hasFocusedActivity else { return .general }
        return .linked
    }
}

public enum CaptureTargetApplicationPolicy {
    public static let codexBundleIdentifier = "com.openai.codex"
    public static let voiceBundleIdentifier = "app.interviewarc.voice"

    private static let transientSystemBundleIdentifiers: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
    ]

    public static func canAttachToInterviewArc(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == codexBundleIdentifier
    }

    public static func canReceiveDictation(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return bundleIdentifier != voiceBundleIdentifier
            && !transientSystemBundleIdentifiers.contains(bundleIdentifier)
    }
}
