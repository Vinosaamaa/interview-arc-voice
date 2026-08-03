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

public struct CaptureTargetDescriptor: Equatable, Sendable {
    public let bundleIdentifier: String?
    public let windowTitle: String?

    public init(
        bundleIdentifier: String?,
        windowTitle: String?
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
    }
}

public enum CaptureTargetKind: String, Codable, Equatable, Sendable {
    case desktopCodex
    case codexCLITerminal
    case other
}

public enum CaptureTargetDecisionReason: String, Codable, Equatable, Sendable {
    case desktopCodex
    case verifiedCodexCLIProcess
    case verifiedCodexWorkspace
    case terminalWithoutCodexProcess
    case terminalWithoutWorkspaceEvidence
    case unsupportedApplication
    case missingApplication
}

public struct CaptureTargetDecision: Equatable, Sendable {
    public let canAttach: Bool
    public let kind: CaptureTargetKind
    public let reason: CaptureTargetDecisionReason

    public init(
        canAttach: Bool,
        kind: CaptureTargetKind,
        reason: CaptureTargetDecisionReason
    ) {
        self.canAttach = canAttach
        self.kind = kind
        self.reason = reason
    }
}

public enum CaptureRouteReason: String, Codable, Equatable, Sendable {
    case linkedAtRecordStart
    case linkedAfterContextRefresh
    case linkDisabled
    case unsupportedTarget
    case noFocusedActivity
    case staleFocusedContext
}

public enum CaptureRoutePhase: Equatable, Sendable {
    case recordStart
    case contextRefresh
}

public struct CaptureRouteEvaluation: Equatable, Sendable {
    public let route: CaptureRouteKind
    public let reason: CaptureRouteReason

    public init(route: CaptureRouteKind, reason: CaptureRouteReason) {
        self.route = route
        self.reason = reason
    }
}

public struct CaptureRouteEvaluationPolicy: Sendable {
    public init() {}

    public func evaluate(
        linkEnabled: Bool,
        target: CaptureTargetDecision,
        hasFocusedActivity: Bool,
        contextIsFresh: Bool,
        phase: CaptureRoutePhase = .recordStart
    ) -> CaptureRouteEvaluation {
        guard linkEnabled else {
            return CaptureRouteEvaluation(route: .general, reason: .linkDisabled)
        }
        guard target.canAttach else {
            return CaptureRouteEvaluation(route: .general, reason: .unsupportedTarget)
        }
        guard hasFocusedActivity else {
            return CaptureRouteEvaluation(route: .general, reason: .noFocusedActivity)
        }
        guard contextIsFresh else {
            return CaptureRouteEvaluation(route: .general, reason: .staleFocusedContext)
        }
        return linkedEvaluation(phase: phase)
    }

    public func linkedEvaluation(
        phase: CaptureRoutePhase
    ) -> CaptureRouteEvaluation {
        CaptureRouteEvaluation(
            route: .linked,
            reason: phase == .recordStart
                ? .linkedAtRecordStart
                : .linkedAfterContextRefresh
        )
    }
}

public enum CaptureTargetApplicationPolicy {
    public static let codexBundleIdentifier = "com.openai.codex"
    public static let voiceBundleIdentifier = "app.interviewarc.voice"

    private static let codexTerminalBundleIdentifiers: Set<String> = [
        "com.cmuxterm.app",
        "dev.warp.Warp-Stable",
    ]

    private static let codexWorkspaceTitleMarkers = [
        "codex",
        "interview arc",
    ]

    private static let transientSystemBundleIdentifiers: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
    ]

    public static func decision(
        for descriptor: CaptureTargetDescriptor?
    ) -> CaptureTargetDecision {
        guard let descriptor,
              let bundleIdentifier = descriptor.bundleIdentifier,
              !bundleIdentifier.isEmpty else {
            return CaptureTargetDecision(
                canAttach: false,
                kind: .other,
                reason: .missingApplication
            )
        }
        if bundleIdentifier == codexBundleIdentifier {
            return CaptureTargetDecision(
                canAttach: true,
                kind: .desktopCodex,
                reason: .desktopCodex
            )
        }
        guard codexTerminalBundleIdentifiers.contains(bundleIdentifier) else {
            return CaptureTargetDecision(
                canAttach: false,
                kind: .other,
                reason: .unsupportedApplication
            )
        }
        let title = descriptor.windowTitle?
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            ?? ""
        guard codexWorkspaceTitleMarkers.contains(where: title.contains) else {
            return CaptureTargetDecision(
                canAttach: false,
                kind: .other,
                reason: .terminalWithoutWorkspaceEvidence
            )
        }
        return CaptureTargetDecision(
            canAttach: true,
            kind: .codexCLITerminal,
            reason: .verifiedCodexWorkspace
        )
    }

    public static func canAttachToInterviewArc(bundleIdentifier: String?) -> Bool {
        decision(
            for: CaptureTargetDescriptor(
                bundleIdentifier: bundleIdentifier,
                windowTitle: nil
            )
        ).canAttach
    }

    public static func canReceiveDictation(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return false }
        return bundleIdentifier != voiceBundleIdentifier
            && !transientSystemBundleIdentifiers.contains(bundleIdentifier)
    }
}
