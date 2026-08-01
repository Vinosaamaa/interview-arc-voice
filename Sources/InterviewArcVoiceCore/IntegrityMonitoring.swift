@preconcurrency import AVFoundation
import AudioToolbox
import Foundation

public enum RecordingIntegrityReason: String, Codable, Equatable, Sendable {
    case audioWriteFailed
    case emptyFile
    case noDecodedFrames
    case durationMismatch
    case insufficientSignal
}

public struct RecordingIntegrityEvidence: Equatable, Sendable {
    public let wallDurationSeconds: Double
    public let decodedDurationSeconds: Double
    public let fileSizeBytes: Int
    public let decodedFrameCount: Int64
    public let writeErrorDescription: String?
    public let encodedAudioBytes: Int?
    public let peakPowerDecibels: Float?

    public init(
        wallDurationSeconds: Double,
        decodedDurationSeconds: Double,
        fileSizeBytes: Int,
        decodedFrameCount: Int64,
        writeErrorDescription: String?,
        encodedAudioBytes: Int? = nil,
        peakPowerDecibels: Float? = nil
    ) {
        self.wallDurationSeconds = wallDurationSeconds
        self.decodedDurationSeconds = decodedDurationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.decodedFrameCount = decodedFrameCount
        self.writeErrorDescription = writeErrorDescription
        self.encodedAudioBytes = encodedAudioBytes
        self.peakPowerDecibels = peakPowerDecibels
    }
}

public struct RecordingIntegrityResult: Equatable, Sendable {
    public let reasons: [RecordingIntegrityReason]
    public var isComplete: Bool { reasons.isEmpty }
}

public enum RecordingRecoveryAction: Equatable, Sendable {
    case transcribe
    case preserveWithoutRetry
    case recordAgain
}

public enum RecordingRecoveryPolicy {
    public static func action(
        for evidence: RecordingIntegrityEvidence
    ) -> RecordingRecoveryAction {
        let integrity = RecordingIntegrityEvaluator.evaluate(evidence)
        if integrity.isComplete {
            return .transcribe
        }
        if integrity.reasons.contains(.insufficientSignal) {
            return .recordAgain
        }
        if evidence.fileSizeBytes >= 512,
           evidence.decodedFrameCount > 0,
           evidence.decodedDurationSeconds > 0 {
            return .preserveWithoutRetry
        }
        return .recordAgain
    }
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
        if evidence.decodedDurationSeconds >= 2,
           let encodedAudioBytes = evidence.encodedAudioBytes {
            let encodedBitsPerSecond =
                Double(encodedAudioBytes) * 8 / evidence.decodedDurationSeconds
            if encodedBitsPerSecond < 1_500 {
                reasons.append(.insufficientSignal)
            }
        }
        if let peakPowerDecibels = evidence.peakPowerDecibels,
           peakPowerDecibels < MicrophoneSignalPolicy.defaultSignalThresholdDecibels {
            reasons.append(.insufficientSignal)
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
            writeErrorDescription: capture.writeErrorDescription,
            encodedAudioBytes: encodedAudioByteCount(at: capture.url),
            peakPowerDecibels: capture.peakPowerDecibels
        )
    }

    private static func encodedAudioByteCount(at url: URL) -> Int? {
        var audioFile: AudioFileID?
        guard AudioFileOpenURL(
            url as CFURL,
            .readPermission,
            0,
            &audioFile
        ) == noErr, let audioFile else {
            return nil
        }
        defer { AudioFileClose(audioFile) }

        var byteCount: UInt64 = 0
        var propertySize = UInt32(MemoryLayout<UInt64>.size)
        guard AudioFileGetProperty(
            audioFile,
            kAudioFilePropertyAudioDataByteCount,
            &propertySize,
            &byteCount
        ) == noErr else {
            return nil
        }
        return Int(clamping: byteCount)
    }
}

public enum TranscriptionIntegrityReason: String, Codable, Equatable, Sendable {
    case emptyTranscript
    case missingChunks
    case providerDurationMismatch
    case implausiblyShortTranscript
    case missingSpeechCoverage
    case promptLeakage
}

public struct TranscriptionIntegrityEvidence: Equatable, Sendable {
    public let audioDurationSeconds: Double
    public let providerDurationSeconds: Double
    public let expectedChunkCount: Int
    public let returnedChunkCount: Int
    public let transcript: String
    public let prompt: String
    public let hasSustainedSpeechAfterProviderCoverage: Bool

    public init(
        audioDurationSeconds: Double,
        providerDurationSeconds: Double,
        expectedChunkCount: Int,
        returnedChunkCount: Int,
        transcript: String,
        prompt: String,
        hasSustainedSpeechAfterProviderCoverage: Bool = false
    ) {
        self.audioDurationSeconds = audioDurationSeconds
        self.providerDurationSeconds = providerDurationSeconds
        self.expectedChunkCount = expectedChunkCount
        self.returnedChunkCount = returnedChunkCount
        self.transcript = transcript
        self.prompt = prompt
        self.hasSustainedSpeechAfterProviderCoverage =
            hasSustainedSpeechAfterProviderCoverage
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
        if evidence.hasSustainedSpeechAfterProviderCoverage {
            reasons.append(.missingSpeechCoverage)
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
    public let omittedUnsupportedSegmentCount: Int
    public let omittedUnsupportedWordCount: Int
    public let wordAlignmentComplete: Bool
    public let evaluatedSegmentCount: Int
    public let wordTimestampCount: Int
    public let segmentValidationSeconds: Double
    public let providerLexicalCoverageEndSeconds: Double?
    public let trailingSpeechLikeFrameCount: Int?
    public let trailingSpeechLikeFraction: Double?

    public init(
        transcription: TranscriptionResult,
        wasRetried: Bool,
        omittedUnsupportedSegmentCount: Int = 0,
        omittedUnsupportedWordCount: Int = 0,
        wordAlignmentComplete: Bool = false,
        evaluatedSegmentCount: Int = 0,
        wordTimestampCount: Int = 0,
        segmentValidationSeconds: Double = 0,
        providerLexicalCoverageEndSeconds: Double? = nil,
        trailingSpeechLikeFrameCount: Int? = nil,
        trailingSpeechLikeFraction: Double? = nil
    ) {
        self.transcription = transcription
        self.wasRetried = wasRetried
        self.omittedUnsupportedSegmentCount = omittedUnsupportedSegmentCount
        self.omittedUnsupportedWordCount = omittedUnsupportedWordCount
        self.wordAlignmentComplete = wordAlignmentComplete
        self.evaluatedSegmentCount = evaluatedSegmentCount
        self.wordTimestampCount = wordTimestampCount
        self.segmentValidationSeconds = segmentValidationSeconds
        self.providerLexicalCoverageEndSeconds =
            providerLexicalCoverageEndSeconds
        self.trailingSpeechLikeFrameCount = trailingSpeechLikeFrameCount
        self.trailingSpeechLikeFraction = trailingSpeechLikeFraction
    }
}

public struct TranscriptionIntegrityFailure: LocalizedError, Sendable {
    public let reasons: [TranscriptionIntegrityReason]
    public let timing: TranscriptionTiming?
    public let providerRetryOccurred: Bool
    public let lexicalCoverageEndSeconds: Double?
    public let trailingSpeechLikeFrameCount: Int?
    public let trailingSpeechLikeFraction: Double?

    public init(
        reasons: [TranscriptionIntegrityReason],
        timing: TranscriptionTiming?,
        providerRetryOccurred: Bool,
        lexicalCoverageEndSeconds: Double?,
        trailingSpeechLikeFrameCount: Int?,
        trailingSpeechLikeFraction: Double?
    ) {
        self.reasons = reasons
        self.timing = timing
        self.providerRetryOccurred = providerRetryOccurred
        self.lexicalCoverageEndSeconds = lexicalCoverageEndSeconds
        self.trailingSpeechLikeFrameCount = trailingSpeechLikeFrameCount
        self.trailingSpeechLikeFraction = trailingSpeechLikeFraction
    }

    public var errorDescription: String? {
        "Groq returned incomplete text twice. The original audio was preserved; use Play, Save, or Retry."
    }
}

public actor ReliableSpeechTranscriber {
    private struct IntegrityCheck {
        let result: TranscriptionIntegrityResult
        let providerLexicalCoverageEndSeconds: Double?
        let trailingSpeechEvidence: SpeechIntervalEvidence?
    }

    private let base: any SpeechTranscribing

    public init(base: any SpeechTranscribing) {
        self.base = base
    }

    public func transcribe(
        fileURL: URL,
        prompt: String,
        temporaryDirectory: URL,
        audioDurationSeconds: Double,
        expectedChunkCount: Int = 1,
        speechEvidence: SpeechEvidenceResult? = nil,
        protectionMode: SpeechProtectionMode = .basic
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
                expectedChunkCount: expectedChunkCount,
                speechEvidence: speechEvidence
            )
            guard !retryCheck.result.isSuspicious else {
                throw integrityFailure(
                    retryCheck,
                    timing: retry.timing
                )
            }
            return try protectedResult(
                retry,
                wasRetried: true,
                speechEvidence: speechEvidence,
                protectionMode: protectionMode,
                integrityCheck: retryCheck
            )
        }
        let firstCheck = check(
            first,
            prompt: prompt,
            audioDurationSeconds: audioDurationSeconds,
            expectedChunkCount: expectedChunkCount,
            speechEvidence: speechEvidence
        )
        guard firstCheck.result.isSuspicious else {
            return try protectedResult(
                first,
                wasRetried: false,
                speechEvidence: speechEvidence,
                protectionMode: protectionMode,
                integrityCheck: firstCheck
            )
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
            expectedChunkCount: expectedChunkCount,
            speechEvidence: speechEvidence
        )
        guard !retryCheck.result.isSuspicious else {
            throw integrityFailure(
                retryCheck,
                timing: combinedTiming(first.timing, retry.timing)
            )
        }
        return try protectedResult(
            retry,
            wasRetried: true,
            speechEvidence: speechEvidence,
            protectionMode: protectionMode,
            integrityCheck: retryCheck
        )
    }

    private func protectedResult(
        _ transcription: TranscriptionResult,
        wasRetried: Bool,
        speechEvidence: SpeechEvidenceResult?,
        protectionMode: SpeechProtectionMode,
        integrityCheck: IntegrityCheck
    ) throws -> ReliableTranscription {
        guard let speechEvidence else {
            return ReliableTranscription(
                transcription: transcription,
                wasRetried: wasRetried,
                providerLexicalCoverageEndSeconds:
                    integrityCheck.providerLexicalCoverageEndSeconds,
                trailingSpeechLikeFrameCount:
                    integrityCheck.trailingSpeechEvidence?
                        .speechLikeFrameCount,
                trailingSpeechLikeFraction:
                    integrityCheck.trailingSpeechEvidence?
                        .speechLikeFraction
            )
        }
        let validationStartedAt = Date()
        let protected = SegmentLocalTranscriptValidator.apply(
            transcription,
            speechEvidence: speechEvidence,
            mode: protectionMode
        )
        let validationSeconds = Date().timeIntervalSince(validationStartedAt)
        guard !protected.transcription.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty else {
            throw TranscriptionIntegrityFailure(
                reasons: [.emptyTranscript],
                timing: transcription.timing,
                providerRetryOccurred: wasRetried,
                lexicalCoverageEndSeconds:
                    integrityCheck.providerLexicalCoverageEndSeconds,
                trailingSpeechLikeFrameCount:
                    integrityCheck.trailingSpeechEvidence?
                        .speechLikeFrameCount,
                trailingSpeechLikeFraction:
                    integrityCheck.trailingSpeechEvidence?
                        .speechLikeFraction
            )
        }
        return ReliableTranscription(
            transcription: protected.transcription,
            wasRetried: wasRetried,
            omittedUnsupportedSegmentCount: protected.omittedUnsupportedSegmentCount,
            omittedUnsupportedWordCount: protected.omittedUnsupportedWordCount,
            wordAlignmentComplete: protected.wordAlignmentComplete,
            evaluatedSegmentCount: protected.evaluatedSegmentCount,
            wordTimestampCount: protected.wordTimestampCount,
            segmentValidationSeconds: validationSeconds,
            providerLexicalCoverageEndSeconds:
                integrityCheck.providerLexicalCoverageEndSeconds,
            trailingSpeechLikeFrameCount:
                integrityCheck.trailingSpeechEvidence?
                    .speechLikeFrameCount,
            trailingSpeechLikeFraction:
                integrityCheck.trailingSpeechEvidence?
                    .speechLikeFraction
        )
    }

    private func check(
        _ result: TranscriptionResult,
        prompt: String,
        audioDurationSeconds: Double,
        expectedChunkCount: Int,
        speechEvidence: SpeechEvidenceResult?
    ) -> IntegrityCheck {
        let providerCoverageEnd = providerLexicalCoverageEnd(result)
        let trailingSpeechEvidence: SpeechIntervalEvidence?
        if let speechEvidence,
           let providerCoverageEnd,
           audioDurationSeconds >= 8,
           providerCoverageEnd + 1 < audioDurationSeconds {
            trailingSpeechEvidence = speechEvidence.evidence(
                from: providerCoverageEnd + 0.25,
                to: min(
                    audioDurationSeconds,
                    speechEvidence.analyzedDurationSeconds
                )
            )
        } else {
            trailingSpeechEvidence = nil
        }
        let hasSustainedSpeechAfterProviderCoverage =
            trailingSpeechEvidence?.hasSustainedSpeech == true
            && (trailingSpeechEvidence?.speechLikeFraction ?? 0) >= 0.05
        return IntegrityCheck(
            result: TranscriptionIntegrityEvaluator.evaluate(
                TranscriptionIntegrityEvidence(
                    audioDurationSeconds: audioDurationSeconds,
                    providerDurationSeconds: result.durationSeconds,
                    expectedChunkCount: expectedChunkCount,
                    returnedChunkCount: result.chunkCount,
                    transcript: result.text,
                    prompt: prompt,
                    hasSustainedSpeechAfterProviderCoverage:
                        hasSustainedSpeechAfterProviderCoverage
                )
            ),
            providerLexicalCoverageEndSeconds: providerCoverageEnd,
            trailingSpeechEvidence: trailingSpeechEvidence
        )
    }

    private func providerLexicalCoverageEnd(
        _ result: TranscriptionResult
    ) -> Double? {
        let canonicalTokens = normalizedTokens(result.text)
        guard !canonicalTokens.isEmpty else { return nil }

        let alignedWords = result.words.filter {
            $0.end.isFinite && $0.start.isFinite && $0.end > $0.start
        }
        let wordTokens = alignedWords.flatMap { normalizedTokens($0.word) }
        if !alignedWords.isEmpty, wordTokens == canonicalTokens {
            return alignedWords.map(\.end).max()
        }

        let lexicalSegments = (result.segments ?? []).filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.end.isFinite
                && $0.start.isFinite
                && $0.end > $0.start
        }
        let segmentTokens = lexicalSegments.flatMap {
            normalizedTokens($0.text)
        }
        if !lexicalSegments.isEmpty, segmentTokens == canonicalTokens {
            return lexicalSegments.map(\.end).max()
        }

        // Sparse or ambiguous provider alignment must fail open. Duration and
        // chunk-count checks still apply, but timestamps that cannot be tied
        // to the canonical text are not evidence of missing speech.
        return nil
    }

    private func normalizedTokens(_ value: String) -> [String] {
        value.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private func integrityFailure(
        _ check: IntegrityCheck,
        timing: TranscriptionTiming?
    ) -> TranscriptionIntegrityFailure {
        TranscriptionIntegrityFailure(
            reasons: check.result.reasons,
            timing: timing,
            providerRetryOccurred: true,
            lexicalCoverageEndSeconds:
                check.providerLexicalCoverageEndSeconds,
            trailingSpeechLikeFrameCount:
                check.trailingSpeechEvidence?.speechLikeFrameCount,
            trailingSpeechLikeFraction:
                check.trailingSpeechEvidence?.speechLikeFraction
        )
    }

    private func combinedTiming(
        _ first: TranscriptionTiming?,
        _ second: TranscriptionTiming?
    ) -> TranscriptionTiming? {
        guard first != nil || second != nil else { return nil }
        return TranscriptionTiming(
            chunkPreparationSeconds:
                (first?.chunkPreparationSeconds ?? 0)
                + (second?.chunkPreparationSeconds ?? 0),
            providerWaitSeconds:
                (first?.providerWaitSeconds ?? 0)
                + (second?.providerWaitSeconds ?? 0),
            responseProcessingSeconds:
                (first?.responseProcessingSeconds ?? 0)
                + (second?.responseProcessingSeconds ?? 0)
        )
    }
}
