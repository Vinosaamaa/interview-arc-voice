import Foundation

public enum LearningVoiceCaptureStoreError: Error, Equatable, Sendable {
    case invalidIdentity
    case identityConflict
}

public enum LearningVoiceCaptureStage: String, Codable, Equatable, Sendable {
    case insertionPending = "insertion_pending"
    case acknowledgementPending = "acknowledgement_pending"
}

public struct PendingLearningVoiceCapture: Codable, Equatable, Identifiable, Sendable {
    public var id: String { operationId }

    public let operationId: String
    public let turnId: String
    public let session: FocusedLearningVoiceSession
    public let transcript: String
    public let checksum: String
    public let audioURL: URL
    public let durationSeconds: Double
    public let occurredAt: Date
    public let transcription: TranscriptionResult
    public let createdAt: Date
    public var stage: LearningVoiceCaptureStage
    public var transcriptInsertedAt: Date?
    public var retryAttempt: Int
    public var lastErrorCode: String?
    public var lastErrorMessage: String?
    public var lastErrorRetryable: Bool?

    public init(
        operationId: String,
        turnId: String,
        session: FocusedLearningVoiceSession,
        transcript: String,
        checksum: String,
        audioURL: URL,
        durationSeconds: Double,
        occurredAt: Date,
        transcription: TranscriptionResult,
        createdAt: Date,
        stage: LearningVoiceCaptureStage = .insertionPending,
        transcriptInsertedAt: Date? = nil,
        retryAttempt: Int = 0,
        lastErrorCode: String? = nil,
        lastErrorMessage: String? = nil,
        lastErrorRetryable: Bool? = nil
    ) {
        self.operationId = operationId
        self.turnId = turnId
        self.session = session
        self.transcript = transcript
        self.checksum = checksum
        self.audioURL = audioURL
        self.durationSeconds = durationSeconds
        self.occurredAt = occurredAt
        self.transcription = transcription
        self.createdAt = createdAt
        self.stage = stage
        self.transcriptInsertedAt = transcriptInsertedAt
        self.retryAttempt = retryAttempt
        self.lastErrorCode = lastErrorCode
        self.lastErrorMessage = lastErrorMessage
        self.lastErrorRetryable = lastErrorRetryable
    }

    public var request: LearningVoiceTranscriptRequest {
        LearningVoiceTranscriptRequest(
            operationId: operationId,
            sessionId: session.sessionId,
            expectedTranscriptRevision: session.transcriptRevision,
            turnId: turnId,
            sequence: session.nextTranscriptSequence,
            transcript: transcript,
            checksum: checksum,
            occurredAt: Int64(occurredAt.timeIntervalSince1970 * 1_000)
        )
    }

    public func hasSameStableIdentity(
        as other: PendingLearningVoiceCapture
    ) -> Bool {
        operationId == other.operationId
            && turnId == other.turnId
            && session == other.session
            && transcript == other.transcript
            && checksum == other.checksum
            && audioURL.standardizedFileURL == other.audioURL.standardizedFileURL
            && durationSeconds == other.durationSeconds
            && occurredAt == other.occurredAt
            && transcription == other.transcription
            && createdAt == other.createdAt
    }
}

public actor LearningVoiceCaptureStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let referenceSeconds = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: referenceSeconds)
            }

            let legacyValue = try container.decode(String.self)
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds,
            ]
            if let date = fractionalFormatter.date(from: legacyValue) {
                return date
            }
            let legacyFormatter = ISO8601DateFormatter()
            legacyFormatter.formatOptions = [.withInternetDateTime]
            guard let date = legacyFormatter.date(from: legacyValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid Learning Voice recovery date."
                )
            }
            return date
        }
    }

    public func saveNew(_ capture: PendingLearningVoiceCapture) throws {
        guard Self.isSafeIdentifier(capture.id) else {
            throw LearningVoiceCaptureStoreError.invalidIdentity
        }
        if let existing = try item(id: capture.id) {
            guard existing.hasSameStableIdentity(as: capture) else {
                throw LearningVoiceCaptureStoreError.identityConflict
            }
            return
        }
        try write(capture)
    }

    public func item(id: String) throws -> PendingLearningVoiceCapture? {
        guard Self.isSafeIdentifier(id) else {
            throw LearningVoiceCaptureStoreError.invalidIdentity
        }
        let url = fileURL(id: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode(
            PendingLearningVoiceCapture.self,
            from: Data(contentsOf: url)
        )
    }

    public func items() throws -> [PendingLearningVoiceCapture] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .compactMap {
            try? decoder.decode(
                PendingLearningVoiceCapture.self,
                from: Data(contentsOf: $0)
            )
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    public func markInserted(id: String, at date: Date = Date()) throws {
        try update(id: id) {
            $0.stage = .acknowledgementPending
            $0.transcriptInsertedAt = $0.transcriptInsertedAt ?? date
            $0.lastErrorCode = nil
            $0.lastErrorMessage = nil
            $0.lastErrorRetryable = nil
        }
    }

    public func recordFailure(
        id: String,
        code: String,
        message: String,
        retryable: Bool
    ) throws {
        try update(id: id) {
            $0.retryAttempt += 1
            $0.lastErrorCode = code
            $0.lastErrorMessage = message
            $0.lastErrorRetryable = retryable
        }
    }

    public func remove(id: String, deleteAudio: Bool) throws {
        guard Self.isSafeIdentifier(id) else {
            throw LearningVoiceCaptureStoreError.invalidIdentity
        }
        if deleteAudio,
           let capture = try item(id: id),
           FileManager.default.fileExists(atPath: capture.audioURL.path) {
            try FileManager.default.removeItem(at: capture.audioURL)
        }
        let url = fileURL(id: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func update(
        id: String,
        _ transform: (inout PendingLearningVoiceCapture) -> Void
    ) throws {
        guard var capture = try item(id: id) else { return }
        let identity = capture
        transform(&capture)
        guard identity.hasSameStableIdentity(as: capture) else {
            throw LearningVoiceCaptureStoreError.identityConflict
        }
        try write(capture)
    }

    private func write(_ capture: PendingLearningVoiceCapture) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let url = fileURL(id: capture.id)
        try encoder.encode(capture).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func fileURL(id: String) -> URL {
        directory.appending(path: "\(id).json")
    }

    private static func isSafeIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              value.count <= 200,
              (Self.isASCIILowercase(first) || Self.isASCIIDigit(first)) else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            Self.isASCIILowercase(scalar)
                || Self.isASCIIDigit(scalar)
                || scalar.value == 46
                || scalar.value == 95
                || scalar.value == 45
        }
    }

    private static func isASCIILowercase(_ scalar: UnicodeScalar) -> Bool {
        (97...122).contains(scalar.value)
    }

    private static func isASCIIDigit(_ scalar: UnicodeScalar) -> Bool {
        (48...57).contains(scalar.value)
    }
}
