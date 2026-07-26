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

    public static func canAttachToInterviewArc(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == codexBundleIdentifier
    }
}
