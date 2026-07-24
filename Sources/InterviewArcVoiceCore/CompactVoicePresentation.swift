import Foundation

public enum CompactVoiceLinkState: Equatable, Sendable {
    case off
    case waiting
    case connectedIdle
    case linked
}

public struct CompactVoicePresentation: Equatable, Sendable {
    public let state: CompactVoiceLinkState
    public let title: String
    public let accessibilityLabel: String

    public init(
        state: CompactVoiceLinkState,
        title: String,
        accessibilityLabel: String
    ) {
        self.state = state
        self.title = title
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct CompactVoicePresentationPolicy: Sendable {
    public init() {}

    public func presentation(
        linkEnabled: Bool,
        activeActivityTitle: String?,
        hasOpenSession: Bool,
        sessionIsRunning: Bool
    ) -> CompactVoicePresentation {
        guard linkEnabled else {
            return CompactVoicePresentation(
                state: .off,
                title: "General dictation",
                accessibilityLabel: "General dictation. Interview Arc linking is off."
            )
        }

        if let activeActivityTitle,
           !activeActivityTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CompactVoicePresentation(
                state: .linked,
                title: activeActivityTitle,
                accessibilityLabel: "Linked to \(activeActivityTitle)."
            )
        }

        if hasOpenSession {
            return CompactVoicePresentation(
                state: .connectedIdle,
                title: sessionIsRunning
                    ? "General dictation · no activity running"
                    : "General dictation · session paused",
                accessibilityLabel: sessionIsRunning
                    ? "Interview Arc is connected. No activity is running. Recording uses general dictation."
                    : "Interview Arc is connected. The session is paused. Recording uses general dictation."
            )
        }

        return CompactVoicePresentation(
            state: .waiting,
            title: "No focused activity · general dictation",
            accessibilityLabel: "Auto-link is on. No activity is focused, so recording uses general dictation."
        )
    }
}
