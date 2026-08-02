import Foundation

public enum VoiceDiagnosticOutcome: String, Codable, Equatable, Sendable {
    case delivered
    case noSpeech
    case failed
}

public struct VoiceDiagnosticRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let recordingDurationSeconds: Double
    public let fileFinalizationSeconds: Double
    public let integrityInspectionSeconds: Double
    public let localSpeechScanSeconds: Double
    public let providerWaitSeconds: Double
    public let responseProcessingSeconds: Double
    public let segmentValidationSeconds: Double?
    public let insertionSeconds: Double
    public let totalSeconds: Double
    public let protectionMode: SpeechProtectionMode
    public let omittedUnsupportedSegmentCount: Int
    public let omittedUnsupportedWordCount: Int?
    public let wordAlignmentComplete: Bool?
    public let evaluatedSegmentCount: Int?
    public let wordTimestampCount: Int?
    public let microphoneRecoveryCount: Int?
    public let vadSpeechFrameCount: Int?
    public let vadLongestSpeechRunFrames: Int?
    public let providerRetryOccurred: Bool?
    public let lexicalCoverageEndSeconds: Double?
    public let trailingSpeechLikeFrameCount: Int?
    public let trailingSpeechLikeFraction: Double?
    public let integrityReasons: [TranscriptionIntegrityReason]?
    public let transcriptionEngine: String?
    public let transcriptionModel: String?
    public let localInferenceSeconds: Double?
    public let localFallbackAttempted: Bool?
    public let localValidationReasons: [TranscriptionIntegrityReason]?
    public let outcome: VoiceDiagnosticOutcome

    public init(
        id: UUID,
        createdAt: Date,
        recordingDurationSeconds: Double,
        fileFinalizationSeconds: Double,
        integrityInspectionSeconds: Double,
        localSpeechScanSeconds: Double,
        providerWaitSeconds: Double,
        responseProcessingSeconds: Double,
        segmentValidationSeconds: Double? = nil,
        insertionSeconds: Double,
        totalSeconds: Double,
        protectionMode: SpeechProtectionMode,
        omittedUnsupportedSegmentCount: Int,
        omittedUnsupportedWordCount: Int? = nil,
        wordAlignmentComplete: Bool? = nil,
        evaluatedSegmentCount: Int? = nil,
        wordTimestampCount: Int? = nil,
        microphoneRecoveryCount: Int? = nil,
        vadSpeechFrameCount: Int? = nil,
        vadLongestSpeechRunFrames: Int? = nil,
        providerRetryOccurred: Bool? = nil,
        lexicalCoverageEndSeconds: Double? = nil,
        trailingSpeechLikeFrameCount: Int? = nil,
        trailingSpeechLikeFraction: Double? = nil,
        integrityReasons: [TranscriptionIntegrityReason]? = nil,
        transcriptionEngine: String? = nil,
        transcriptionModel: String? = nil,
        localInferenceSeconds: Double? = nil,
        localFallbackAttempted: Bool? = nil,
        localValidationReasons: [TranscriptionIntegrityReason]? = nil,
        outcome: VoiceDiagnosticOutcome
    ) {
        self.id = id
        self.createdAt = createdAt
        self.recordingDurationSeconds = recordingDurationSeconds
        self.fileFinalizationSeconds = fileFinalizationSeconds
        self.integrityInspectionSeconds = integrityInspectionSeconds
        self.localSpeechScanSeconds = localSpeechScanSeconds
        self.providerWaitSeconds = providerWaitSeconds
        self.responseProcessingSeconds = responseProcessingSeconds
        self.segmentValidationSeconds = segmentValidationSeconds
        self.insertionSeconds = insertionSeconds
        self.totalSeconds = totalSeconds
        self.protectionMode = protectionMode
        self.omittedUnsupportedSegmentCount = omittedUnsupportedSegmentCount
        self.omittedUnsupportedWordCount = omittedUnsupportedWordCount
        self.wordAlignmentComplete = wordAlignmentComplete
        self.evaluatedSegmentCount = evaluatedSegmentCount
        self.wordTimestampCount = wordTimestampCount
        self.microphoneRecoveryCount = microphoneRecoveryCount
        self.vadSpeechFrameCount = vadSpeechFrameCount
        self.vadLongestSpeechRunFrames = vadLongestSpeechRunFrames
        self.providerRetryOccurred = providerRetryOccurred
        self.lexicalCoverageEndSeconds = lexicalCoverageEndSeconds
        self.trailingSpeechLikeFrameCount = trailingSpeechLikeFrameCount
        self.trailingSpeechLikeFraction = trailingSpeechLikeFraction
        self.integrityReasons = integrityReasons
        self.transcriptionEngine = transcriptionEngine
        self.transcriptionModel = transcriptionModel
        self.localInferenceSeconds = localInferenceSeconds
        self.localFallbackAttempted = localFallbackAttempted
        self.localValidationReasons = localValidationReasons
        self.outcome = outcome
    }

    public var report: String {
        [
            "Created: \(createdAt.ISO8601Format())",
            "Recording: \(milliseconds(recordingDurationSeconds))",
            "File finalization: \(milliseconds(fileFinalizationSeconds))",
            "Integrity inspection: \(milliseconds(integrityInspectionSeconds))",
            "Local speech scan: \(milliseconds(localSpeechScanSeconds))",
            "Upload and Groq: \(milliseconds(providerWaitSeconds))",
            "Response processing: \(milliseconds(responseProcessingSeconds))",
            "Segment validation: \(milliseconds(segmentValidationSeconds ?? 0))",
            "Cursor insertion: \(milliseconds(insertionSeconds))",
            "Total: \(milliseconds(totalSeconds))",
            "Protection: \(protectionMode.displayName)",
            "Unsupported segments omitted: \(omittedUnsupportedSegmentCount)",
            "Unsupported words omitted: \(omittedUnsupportedWordCount.map { String($0) } ?? "Unavailable")",
            "Word alignment complete: \(wordAlignmentComplete.map { String($0) } ?? "Unavailable")",
            "Segments evaluated: \(evaluatedSegmentCount.map { String($0) } ?? "Unavailable")",
            "Word timestamps: \(wordTimestampCount.map { String($0) } ?? "Unavailable")",
            "Microphone recovery attempts: \(microphoneRecoveryCount.map { String($0) } ?? "Unavailable")",
            "WebRTC VAD speech frames: \(vadSpeechFrameCount.map { String($0) } ?? "Unavailable")",
            "WebRTC VAD longest run: \(vadLongestSpeechRunFrames.map { String($0) } ?? "Unavailable")",
            "Transcription retried: \(providerRetryOccurred.map { String($0) } ?? "Unavailable")",
            "Provider lexical coverage end: \(seconds(lexicalCoverageEndSeconds))",
            "Trailing speech-like frames: \(trailingSpeechLikeFrameCount.map { String($0) } ?? "Unavailable")",
            "Trailing speech-like fraction: \(fraction(trailingSpeechLikeFraction))",
            "Transcription integrity reasons: \(integrityReasons?.map(\.rawValue).joined(separator: ", ") ?? "None")",
            "Transcription engine: \(transcriptionEngine ?? "Unavailable")",
            "Transcription model: \(transcriptionModel ?? "Unavailable")",
            "Local inference: \(milliseconds(localInferenceSeconds ?? 0))",
            "Local fallback attempted: \(localFallbackAttempted.map { String($0) } ?? "Unavailable")",
            "Local validation reasons: \(localValidationReasons?.map(\.rawValue).joined(separator: ", ") ?? "None")",
            "Outcome: \(outcome.rawValue)",
        ].joined(separator: "\n")
    }

    private func milliseconds(_ seconds: Double) -> String {
        let value = max(0, seconds) * 1_000
        if value > 0, value < 1 { return "<1 ms" }
        return String(format: "%.0f ms", value)
    }

    private func seconds(_ value: Double?) -> String {
        value.map { String(format: "%.2f s", $0) } ?? "Unavailable"
    }

    private func fraction(_ value: Double?) -> String {
        value.map { String(format: "%.3f", $0) } ?? "Unavailable"
    }
}

public enum DiagnosticTranscriptionRetryPolicy {
    public static func matchingRecord(
        for diagnostic: VoiceDiagnosticRecord,
        in records: [LocalTranscriptRecord]
    ) -> LocalTranscriptRecord? {
        if let exact = records.first(where: {
            $0.id == diagnostic.id && $0.audioReference != nil
        }) {
            return exact
        }

        return records
            .filter {
                $0.audioReference != nil
                    && abs($0.durationSeconds
                        - diagnostic.recordingDurationSeconds) <= 0.75
                    && abs($0.createdAt.timeIntervalSince(
                        diagnostic.createdAt
                    )) <= 30
            }
            .min { lhs, rhs in
                let lhsDateDistance = abs(lhs.createdAt.timeIntervalSince(
                    diagnostic.createdAt
                ))
                let rhsDateDistance = abs(rhs.createdAt.timeIntervalSince(
                    diagnostic.createdAt
                ))
                if lhsDateDistance != rhsDateDistance {
                    return lhsDateDistance < rhsDateDistance
                }
                return abs(lhs.durationSeconds
                    - diagnostic.recordingDurationSeconds)
                    < abs(rhs.durationSeconds
                        - diagnostic.recordingDurationSeconds)
            }
    }

    public static func supportsLocalRetry(
        _ record: LocalTranscriptRecord?
    ) -> Bool {
        guard let record else { return false }
        return record.audioReference != nil && record.captureID == nil
    }
}

public actor VoiceDiagnosticsStore {
    public nonisolated let fileURL: URL

    private let retentionLimit: Int
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        directory: URL,
        retentionLimit: Int = 100,
        fileManager: FileManager = .default
    ) throws {
        self.retentionLimit = max(1, retentionLimit)
        self.fileManager = fileManager
        fileURL = directory.appending(path: "transcription-diagnostics.json")
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        if !fileManager.fileExists(atPath: fileURL.path) {
            try Data("[]".utf8).write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        }
    }

    public func append(_ record: VoiceDiagnosticRecord) throws {
        var current = try records()
        current.removeAll { $0.id == record.id }
        current.insert(record, at: 0)
        try write(Array(current.prefix(retentionLimit)))
    }

    public func records() throws -> [VoiceDiagnosticRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([VoiceDiagnosticRecord].self, from: data)
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func clear() throws {
        try write([])
    }

    private func write(_ records: [VoiceDiagnosticRecord]) throws {
        let data = try encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
