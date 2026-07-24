@preconcurrency import AVFoundation
import Foundation

public enum RecordingIntegrityReason: String, Codable, Equatable, Sendable {
    case audioWriteFailed
    case emptyFile
    case noDecodedFrames
    case durationMismatch
}

public struct RecordingIntegrityEvidence: Equatable, Sendable {
    public let wallDurationSeconds: Double
    public let decodedDurationSeconds: Double
    public let fileSizeBytes: Int
    public let decodedFrameCount: Int64
    public let writeErrorDescription: String?

    public init(
        wallDurationSeconds: Double,
        decodedDurationSeconds: Double,
        fileSizeBytes: Int,
        decodedFrameCount: Int64,
        writeErrorDescription: String?
    ) {
        self.wallDurationSeconds = wallDurationSeconds
        self.decodedDurationSeconds = decodedDurationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.decodedFrameCount = decodedFrameCount
        self.writeErrorDescription = writeErrorDescription
    }
}

public struct RecordingIntegrityResult: Equatable, Sendable {
    public let reasons: [RecordingIntegrityReason]
    public var isComplete: Bool { reasons.isEmpty }
}

public enum RecordingIntegrityEvaluator {
    public static func evaluate(_ evidence: RecordingIntegrityEvidence) -> RecordingIntegrityResult {
        var reasons: [RecordingIntegrityReason] = []
        if evidence.writeErrorDescription != nil { reasons.append(.audioWriteFailed) }
        if evidence.fileSizeBytes < 512 { reasons.append(.emptyFile) }
        if evidence.decodedFrameCount <= 0 { reasons.append(.noDecodedFrames) }
        if evidence.wallDurationSeconds >= 2,
           evidence.decodedDurationSeconds + 1.0 < evidence.wallDurationSeconds * 0.85 {
            reasons.append(.durationMismatch)
        }
        return RecordingIntegrityResult(reasons: reasons)
    }
}

public enum RecordingFileInspector {
    public static func inspect(_ capture: RecordedCapture) throws -> RecordingIntegrityEvidence {
        let resources = try capture.url.resourceValues(forKeys: [.fileSizeKey])
        let audioFile = try AVAudioFile(forReading: capture.url)
        let sampleRate = audioFile.fileFormat.sampleRate
        let decodedFrames = audioFile.length
        let decodedDuration = sampleRate > 0 ? Double(decodedFrames) / sampleRate : 0
        return RecordingIntegrityEvidence(
            wallDurationSeconds: capture.duration,
            decodedDurationSeconds: decodedDuration,
            fileSizeBytes: resources.fileSize ?? 0,
            decodedFrameCount: max(decodedFrames, capture.writtenFrameCount),
            writeErrorDescription: capture.writeErrorDescription
        )
    }
}

public enum TranscriptionIntegrityReason: String, Codable, Equatable, Sendable {
    case emptyTranscript
    case missingChunks
    case providerDurationMismatch
    case implausiblyShortTranscript
    case promptLeakage
}

public struct TranscriptionIntegrityEvidence: Equatable, Sendable {
    public let audioDurationSeconds: Double
    public let providerDurationSeconds: Double
    public let expectedChunkCount: Int
    public let returnedChunkCount: Int
    public let transcript: String
    public let prompt: String

    public init(
        audioDurationSeconds: Double,
        providerDurationSeconds: Double,
        expectedChunkCount: Int,
        returnedChunkCount: Int,
        transcript: String,
        prompt: String
    ) {
        self.audioDurationSeconds = audioDurationSeconds
        self.providerDurationSeconds = providerDurationSeconds
        self.expectedChunkCount = expectedChunkCount
        self.returnedChunkCount = returnedChunkCount
        self.transcript = transcript
        self.prompt = prompt
    }
}

public struct TranscriptionIntegrityResult: Equatable, Sendable {
    public let reasons: [TranscriptionIntegrityReason]
    public var isSuspicious: Bool { !reasons.isEmpty }
}

public enum TranscriptionIntegrityEvaluator {
    public static func evaluate(_ evidence: TranscriptionIntegrityEvidence) -> TranscriptionIntegrityResult {
        let trimmed = evidence.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        var reasons: [TranscriptionIntegrityReason] = []
        if trimmed.isEmpty { reasons.append(.emptyTranscript) }
        if evidence.returnedChunkCount < evidence.expectedChunkCount {
            reasons.append(.missingChunks)
        }
        if evidence.audioDurationSeconds >= 4,
           evidence.providerDurationSeconds + 1.5 < evidence.audioDurationSeconds * 0.80 {
            reasons.append(.providerDurationMismatch)
        }
        if evidence.audioDurationSeconds >= 8, trimmed.count < 8 {
            reasons.append(.implausiblyShortTranscript)
        }
        if containsPromptLeakage(transcript: trimmed, prompt: evidence.prompt) {
            reasons.append(.promptLeakage)
        }
        if containsKnownHallucinationBoilerplate(trimmed) {
            reasons.append(.promptLeakage)
        }
        return TranscriptionIntegrityResult(reasons: reasons)
    }

    private static func containsPromptLeakage(transcript: String, prompt: String) -> Bool {
        let transcriptTokens = normalizedTokens(transcript)
        let promptTokens = normalizedTokens(prompt)
        guard transcriptTokens.count >= 6, promptTokens.count >= 6 else { return false }
        let transcriptText = transcriptTokens.joined(separator: " ")
        for start in 0...(promptTokens.count - 6) {
            let phrase = promptTokens[start..<(start + 6)].joined(separator: " ")
            if transcriptText.contains(phrase) { return true }
        }
        return false
    }

    private static func normalizedTokens(_ value: String) -> [String] {
        value.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func containsKnownHallucinationBoilerplate(_ transcript: String) -> Bool {
        let normalized = normalizedTokens(transcript).joined(separator: " ")
        return [
            "thank you for watching",
            "preserve punctuation names acronyms and technical terminology",
            "vocabulary is a very important tool",
            "subtitles by the amara org community",
        ].contains { normalized.contains($0) }
    }
}

public struct ReliableTranscription: Equatable, Sendable {
    public let transcription: TranscriptionResult
    public let wasRetried: Bool
}

public actor ReliableSpeechTranscriber {
    private let base: any SpeechTranscribing

    public init(base: any SpeechTranscribing) {
        self.base = base
    }

    public func transcribe(
        fileURL: URL,
        prompt: String,
        temporaryDirectory: URL,
        audioDurationSeconds: Double,
        expectedChunkCount: Int = 1
    ) async throws -> ReliableTranscription {
        let first: TranscriptionResult
        do {
            first = try await base.transcribe(
                fileURL: fileURL,
                prompt: prompt,
                temporaryDirectory: temporaryDirectory
            )
        } catch {
            let retry = try await base.transcribe(
                fileURL: fileURL,
                prompt: "",
                temporaryDirectory: temporaryDirectory
            )
            let retryCheck = check(
                retry,
                prompt: "",
                audioDurationSeconds: audioDurationSeconds,
                expectedChunkCount: expectedChunkCount
            )
            guard !retryCheck.isSuspicious else {
                throw VoiceBridgeError.suspiciousTranscript(retryCheck.reasons)
            }
            return ReliableTranscription(transcription: retry, wasRetried: true)
        }
        let firstCheck = check(
            first,
            prompt: prompt,
            audioDurationSeconds: audioDurationSeconds,
            expectedChunkCount: expectedChunkCount
        )
        guard firstCheck.isSuspicious else {
            return ReliableTranscription(transcription: first, wasRetried: false)
        }

        let retry = try await base.transcribe(
            fileURL: fileURL,
            prompt: "",
            temporaryDirectory: temporaryDirectory
        )
        let retryCheck = check(
            retry,
            prompt: "",
            audioDurationSeconds: audioDurationSeconds,
            expectedChunkCount: expectedChunkCount
        )
        guard !retryCheck.isSuspicious else {
            throw VoiceBridgeError.suspiciousTranscript(retryCheck.reasons)
        }
        return ReliableTranscription(transcription: retry, wasRetried: true)
    }

    private func check(
        _ result: TranscriptionResult,
        prompt: String,
        audioDurationSeconds: Double,
        expectedChunkCount: Int
    ) -> TranscriptionIntegrityResult {
        TranscriptionIntegrityEvaluator.evaluate(
            TranscriptionIntegrityEvidence(
                audioDurationSeconds: audioDurationSeconds,
                providerDurationSeconds: result.durationSeconds,
                expectedChunkCount: expectedChunkCount,
                returnedChunkCount: result.chunkCount,
                transcript: result.text,
                prompt: prompt
            )
        )
    }
}
