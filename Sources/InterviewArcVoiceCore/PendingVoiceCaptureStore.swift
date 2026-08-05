import Foundation

public enum LocalVoiceCaptureState: String, Codable, Equatable, Sendable {
    case insertedRegistrationPending = "inserted_registration_pending"
    case waitingForSpecialist = "waiting_for_specialist"
    case needsDecision = "needs_decision"
    case excludedGracePeriod = "excluded_grace_period"
    case acceptedDelivering = "accepted_delivering"
    case needsAttention = "needs_attention"
    case audioLostNeedsAcknowledgement = "audio_lost_needs_acknowledgement"
    case audioLostAcknowledged = "audio_lost_acknowledged"
    case quarantinedConflict = "quarantined_conflict"
    case complete
}

public enum VoiceCaptureDeliveryStage: String, Codable, Equatable, Sendable {
    case transcriptPending = "transcript_pending"
    case transcriptCommitted = "transcript_committed"
    case audioPending = "audio_pending"
    case audioAvailable = "audio_available"
    case coachPending = "coach_pending"
    case coachQueued = "coach_queued"
    case complete
}

public struct PendingVoiceCapture: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let turnID: String
    public let clipID: String
    public let checksum: String
    public let workbenchID: String?
    public let activity: FocusedVoiceActivity
    public let transcript: String
    public let audioURL: URL
    public let durationSeconds: Double
    public let occurredAt: Date
    public let transcription: TranscriptionResult
    public let createdAt: Date
    public var localState: LocalVoiceCaptureState?
    public var retryAttempt: Int?
    public var retryStartedAt: Date?
    public var nextAttemptAt: Date?
    public var lastErrorCode: String?
    public var lastErrorStatusCode: Int?
    public var lastErrorMessage: String?
    public var lastErrorRetryable: Bool?
    public var deliveryStage: VoiceCaptureDeliveryStage?
    public var transcriptCommittedAt: Date?
    public var audioAvailableAt: Date?
    public var coachQueuedAt: Date?
    public var coachCompletedAt: Date?
    public var responseGroupID: String?
    public var responseGroupDigest: String?
    public var transcriptInsertedAt: Date?
    public var registrationCompletedAt: Date?

    public init(
        id: String,
        turnID: String,
        clipID: String,
        checksum: String,
        workbenchID: String? = nil,
        activity: FocusedVoiceActivity,
        transcript: String,
        audioURL: URL,
        durationSeconds: Double,
        occurredAt: Date,
        transcription: TranscriptionResult,
        createdAt: Date,
        localState: LocalVoiceCaptureState? = nil,
        retryAttempt: Int? = nil,
        retryStartedAt: Date? = nil,
        nextAttemptAt: Date? = nil,
        lastErrorCode: String? = nil,
        lastErrorStatusCode: Int? = nil,
        lastErrorMessage: String? = nil,
        lastErrorRetryable: Bool? = nil,
        deliveryStage: VoiceCaptureDeliveryStage? = nil,
        transcriptCommittedAt: Date? = nil,
        audioAvailableAt: Date? = nil,
        coachQueuedAt: Date? = nil,
        coachCompletedAt: Date? = nil,
        responseGroupID: String? = nil,
        responseGroupDigest: String? = nil,
        transcriptInsertedAt: Date? = nil,
        registrationCompletedAt: Date? = nil
    ) {
        self.id = id
        self.turnID = turnID
        self.clipID = clipID
        self.checksum = checksum
        self.workbenchID = workbenchID ?? activity.workbenchId
        self.activity = activity
        self.transcript = transcript
        self.audioURL = audioURL
        self.durationSeconds = durationSeconds
        self.occurredAt = occurredAt
        self.transcription = transcription
        self.createdAt = createdAt
        self.localState = localState
        self.retryAttempt = retryAttempt
        self.retryStartedAt = retryStartedAt
        self.nextAttemptAt = nextAttemptAt
        self.lastErrorCode = lastErrorCode
        self.lastErrorStatusCode = lastErrorStatusCode
        self.lastErrorMessage = lastErrorMessage
        self.lastErrorRetryable = lastErrorRetryable
        self.deliveryStage = deliveryStage
        self.transcriptCommittedAt = transcriptCommittedAt
        self.audioAvailableAt = audioAvailableAt
        self.coachQueuedAt = coachQueuedAt
        self.coachCompletedAt = coachCompletedAt
        self.responseGroupID = responseGroupID
        self.responseGroupDigest = responseGroupDigest
        self.transcriptInsertedAt = transcriptInsertedAt
        self.registrationCompletedAt = registrationCompletedAt
    }
}

public actor PendingVoiceCaptureStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func save(_ capture: PendingVoiceCapture) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let url = directory.appending(path: "\(capture.id).json")
        try encoder.encode(capture).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func update(
        id: String,
        _ transform: (inout PendingVoiceCapture) -> Void
    ) throws {
        guard var capture = try item(id: id) else { return }
        transform(&capture)
        try save(capture)
    }

    public func item(id: String) throws -> PendingVoiceCapture? {
        let url = directory.appending(path: "\(id).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(PendingVoiceCapture.self, from: Data(contentsOf: url))
    }

    public func items() throws -> [PendingVoiceCapture] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { try? decoder.decode(PendingVoiceCapture.self, from: Data(contentsOf: $0)) }
        .sorted { $0.createdAt < $1.createdAt }
    }

    public func remove(id: String, deleteAudio: Bool) throws {
        if deleteAudio,
           let capture = try item(id: id),
           FileManager.default.fileExists(atPath: capture.audioURL.path) {
            try FileManager.default.removeItem(at: capture.audioURL)
        }
        let url = directory.appending(path: "\(id).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
