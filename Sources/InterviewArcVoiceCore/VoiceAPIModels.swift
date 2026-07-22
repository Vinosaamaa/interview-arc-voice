import Foundation

public struct SpecialistRoute: Codable, Equatable, Sendable {
    public let specialty: String
    public let threadId: String
    public let hostId: String?
    public let title: String
}

public struct VoiceContextResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let date: String
    public let focusedActivity: FocusedVoiceActivity?
    public let specialist: SpecialistRoute?
    public let message: String?
}

public struct FocusedVoiceActivity: Codable, Equatable, Sendable {
    public let activityId: String
    public let questionId: String?
    public let specialty: PracticeSpecialty
    public let interviewArcSpecialty: String
    public let title: String
    public let prompt: String?
    public let topics: [String]
    public let tags: [String]
    public let companies: [String]
    public let projects: [String]
    public let vocabularyPackIds: [String]
    public let speechTerms: [String]

    public var vocabularyContext: ActivityContext {
        ActivityContext(
            activityID: activityId,
            specialty: specialty,
            title: title,
            topics: topics,
            tags: tags,
            companies: companies,
            projects: projects,
            vocabularyPackIDs: vocabularyPackIds,
            speechTerms: speechTerms
        )
    }
}

public struct PersistedVoiceTurn: Codable, Equatable, Sendable {
    public let activityId: String
    public let specialty: String
    public let turnId: String
    public let body: String
    public let occurredAt: Int64
    public let speaker: String
    public let source: String
    public let sequence: Int
}

public struct VoiceCaptureResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let turn: PersistedVoiceTurn
}

public struct AudioUploadResponse: Codable, Equatable, Sendable {
    public let clipId: String
    public let activityId: String
    public let transcriptTurnId: String?
    public let filename: String
    public let mimeType: String
    public let label: String
    public let durationSeconds: Int?
    public let status: String
}

public struct DeliveryQueueResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let analysisId: String
    public let status: String
}

public struct CapturedAnswer: Codable, Equatable, Sendable {
    public let captureID: String
    public let turnID: String
    public let activityID: String
    public let specialty: String
    public let title: String
    public let transcript: String
    public let localAudioURL: URL
    public let durationSeconds: Double
    public let occurredAt: Date
    public let clipID: String?
    public let analysisID: String?
}

public enum VoiceBridgeError: LocalizedError, Sendable {
    case missingCredential(String)
    case noFocusedActivity(String)
    case noSpecialist(String)
    case invalidResponse(Int, String)
    case protocolMismatch(Int)
    case microphoneDenied
    case recordingUnavailable
    case emptyTranscript
    case codexUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredential(let name): return "Add your \(name) in Interview Arc Voice settings."
        case .noFocusedActivity(let message): return message
        case .noSpecialist(let message): return message
        case .invalidResponse(let status, let body): return "Request failed (\(status)): \(body)"
        case .protocolMismatch(let version): return "Interview Arc Voice protocol \(version) is not supported by this app."
        case .microphoneDenied: return "Microphone access is required to record an answer."
        case .recordingUnavailable: return "The recording could not be created."
        case .emptyTranscript: return "No speech was detected in this recording."
        case .codexUnavailable(let detail): return "Codex could not receive the answer: \(detail)"
        }
    }
}
