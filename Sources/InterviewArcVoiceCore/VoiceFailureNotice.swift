import Foundation

public enum VoiceFailureKind: String, Codable, Equatable, Hashable, Sendable {
    case microphone
    case recording
    case transcription
    case insertion
    case interviewArc
    case configuration
    case playback
    case export
}

public enum VoiceFailureAction: String, Codable, Equatable, Hashable, Sendable {
    case recordAgain
    case retryTranscription
    case playRecording
    case saveRecording
    case useRecoveryTranscript
    case insertAgain
    case enableAccessibility
    case openSettings
    case retryConnection
}

public struct VoiceFailureNotice: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: VoiceFailureKind
    public let title: String
    public let message: String
    public let detail: String
    public let actions: [VoiceFailureAction]
    public let occurredAt: Date

    public init(
        id: UUID = UUID(),
        kind: VoiceFailureKind,
        title: String,
        message: String,
        detail: String,
        actions: [VoiceFailureAction],
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.detail = detail
        self.actions = actions
        self.occurredAt = occurredAt
    }
}

public struct CredentialFailureRecoveryPolicy: Sendable {
    public init() {}

    public func retainedFailure(
        _ failure: VoiceFailureNotice?,
        configurationIsReady: Bool
    ) -> VoiceFailureNotice? {
        guard failure?.kind == .configuration,
              configurationIsReady else {
            return failure
        }
        return nil
    }
}
