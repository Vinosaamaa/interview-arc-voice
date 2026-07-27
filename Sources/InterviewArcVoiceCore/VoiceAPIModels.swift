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
    public let timerInstrument: VoiceTimerInstrument?
    public let specialist: SpecialistRoute?
    public let message: String?
}

public struct VoiceTimerState: Codable, Equatable, Sendable {
    public let accumulatedSeconds: Int
    public let startedAt: Int64?
    public let runningSince: Int64?
    public let completed: Bool
    public let completedAt: Int64?
    public let revision: Int

    public var isRunning: Bool {
        runningSince != nil && !completed
    }

    public func elapsedSeconds(
        serverNow: Int64,
        receivedAt: Date,
        now: Date
    ) -> Int {
        guard let runningSince, !completed else {
            return accumulatedSeconds
        }
        let openInterval = max(0, Int((serverNow - runningSince) / 1_000))
        let localContinuation = max(0, Int(now.timeIntervalSince(receivedAt)))
        return accumulatedSeconds + openInterval + localContinuation
    }
}

public struct VoiceTimerSession: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let allocatedSeconds: Int
    public let activityIds: [String]
    public let timer: VoiceTimerState
}

public struct VoiceTimerActivity: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let questionId: String?
    public let type: String
    public let title: String
    public let url: String?
    public let allocatedSeconds: Int
    public let timer: VoiceTimerState?
    public let starred: Bool
    public var activityClass: String? = nil
    public var requiresOutcome: Bool? = nil
    public var outcome: VoicePracticeOutcome? = nil

    public var isFocusBlock: Bool {
        activityClass == "focus_block" || type == "focus_block"
    }

    public var needsOutcome: Bool {
        (requiresOutcome ?? !isFocusBlock) && outcome == nil
    }
}

public struct VoiceTimerInstrument: Codable, Equatable, Sendable {
    public let serverNow: Int64
    public let session: VoiceTimerSession?
    public let activity: VoiceTimerActivity?
    public let activities: [VoiceTimerActivity]

    public var sessionFinishBlockers: [VoiceTimerActivity] {
        activities.filter {
            $0.timer?.startedAt != nil && $0.needsOutcome
        }
    }
}

public enum VoiceLiveConnectionPolicy {
    public static let heartbeatIntervalSeconds = 20
}

public enum VoicePracticeOutcome: String, Codable, CaseIterable, Equatable, Sendable {
    case solved
    case solvedAfterReviewingApproach = "solved_after_reviewing_approach"
    case failed
}

public struct VoiceTimerMutationResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let timerInstrument: VoiceTimerInstrument
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
    public let startedAt: Int64?
    public let runningSince: Int64?

    public init(
        activityId: String,
        questionId: String?,
        specialty: PracticeSpecialty,
        interviewArcSpecialty: String,
        title: String,
        prompt: String?,
        topics: [String],
        tags: [String],
        companies: [String],
        projects: [String],
        vocabularyPackIds: [String],
        speechTerms: [String],
        startedAt: Int64? = nil,
        runningSince: Int64? = nil
    ) {
        self.activityId = activityId
        self.questionId = questionId
        self.specialty = specialty
        self.interviewArcSpecialty = interviewArcSpecialty
        self.title = title
        self.prompt = prompt
        self.topics = topics
        self.tags = tags
        self.companies = companies
        self.projects = projects
        self.vocabularyPackIds = vocabularyPackIds
        self.speechTerms = speechTerms
        self.startedAt = startedAt
        self.runningSince = runningSince
    }

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

public struct VoiceCaptureEnvelope: Equatable, Sendable {
    public let captureID: String
    public let activityID: String
    public let turnID: String
    public let transcript: String

    public init(captureID: String, activityID: String, turnID: String, transcript: String) {
        self.captureID = captureID
        self.activityID = activityID
        self.turnID = turnID
        self.transcript = transcript
    }

    public var editorText: String {
        """
        \(transcript)

        <!-- interview-arc-voice:v2
        captureId: \(commentSafe(captureID))
        activityId: \(commentSafe(activityID))
        turnId: \(commentSafe(turnID))
        intentDecisionRequired: true
        transcriptStoredLocallyUntilAccepted: true
        -->

        """
    }

    private func commentSafe(_ value: String) -> String {
        value
            .replacingOccurrences(of: "--", with: "%2D%2D")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }
}

public struct VoiceCaptureIntent: Codable, Equatable, Sendable {
    public let captureId: String
    public let activityId: String
    public let turnId: String
    public let clipId: String
    public let specialty: String
    public let status: String
    public let checksum: String
    public let occurredAt: Int64
    public let decidedAt: Int64?
    public let decisionSource: String?
    public let decisionReason: String?
    public let lastError: String?
}

public struct VoiceCaptureIntentResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let intent: VoiceCaptureIntent
}

public struct VoiceCaptureIntentListResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let intents: [VoiceCaptureIntent]
    public let legacyOrphans: [LegacyVoiceCapture]
    public let nextCursor: String?
}

public struct LegacyVoiceCapture: Codable, Equatable, Identifiable, Sendable {
    public var id: String { clipId }
    public let clipId: String
    public let activityId: String
    public let turnId: String
    public let occurredAt: Int64
    public let excerpt: String
    public let durationSeconds: Int?
    public let status: String
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
    case incompleteRecording([RecordingIntegrityReason])
    case suspiciousTranscript([TranscriptionIntegrityReason])
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
        case .incompleteRecording:
            return "Recording ended early. The original audio was preserved; use Play or Save before trying again."
        case .suspiciousTranscript:
            return "The transcript may be incomplete. The original audio was preserved; use Play, Save, or Retry."
        case .codexUnavailable(let detail): return "Codex could not receive the answer: \(detail)"
        }
    }
}

public struct InterviewArcAPIError: LocalizedError, Equatable, Sendable {
    public let statusCode: Int
    public let message: String
    public let code: String?
    public let retryable: Bool

    public init(statusCode: Int, message: String, code: String?, retryable: Bool) {
        self.statusCode = statusCode
        self.message = message
        self.code = code
        self.retryable = retryable
    }

    public var errorDescription: String? {
        "Request failed (\(statusCode)): \(message)"
    }
}
