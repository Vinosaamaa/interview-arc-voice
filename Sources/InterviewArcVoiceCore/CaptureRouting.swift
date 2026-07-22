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
