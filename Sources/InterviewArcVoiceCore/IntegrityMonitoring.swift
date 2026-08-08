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
    case transcribePlayablePortion
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
            return .transcribePlayablePortion
        }
        return .recordAgain
    }

    public static func shouldAttemptTranscription(
        action: RecordingRecoveryAction,
        speechProtectionEnabled: Bool,
        localSpeechDetected: Bool
    ) -> Bool {
        switch action {
        case .transcribePlayablePortion:
            // Early finalization can truncate the evidence used by local VAD.
            // Empty, undecodable, and insufficient-signal captures have already
            // failed closed in action(for:), so preserve the user's best
            // available transcript instead of trusting a possible false negative.
            return true
        case .transcribe:
            return !speechProtectionEnabled || localSpeechDetected
        case .recordAgain:
            return false
        }
    }

    public static func transcriptionDurationSeconds(
        action: RecordingRecoveryAction,
        evidence: RecordingIntegrityEvidence
    ) -> Double {
        action == .transcribePlayablePortion
            ? evidence.decodedDurationSeconds
            : evidence.wallDurationSeconds
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
    public let engine: String?
    public let model: String?
    public let localInferenceSeconds: Double?
    public let localPromptTokenCount: Int?
    public let coverageUncertain: Bool

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
        trailingSpeechLikeFraction: Double? = nil,
        engine: String? = nil,
        model: String? = nil,
        localInferenceSeconds: Double? = nil,
        localPromptTokenCount: Int? = nil,
        coverageUncertain: Bool = false
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
        self.engine = engine
        self.model = model
        self.localInferenceSeconds = localInferenceSeconds
        self.localPromptTokenCount = localPromptTokenCount
        self.coverageUncertain = coverageUncertain
    }
}

public struct TranscriptionIntegrityFailure: LocalizedError, Sendable {
    public let reasons: [TranscriptionIntegrityReason]
    public let timing: TranscriptionTiming?
    public let providerRetryOccurred: Bool
    public let lexicalCoverageEndSeconds: Double?
    public let trailingSpeechLikeFrameCount: Int?
    public let trailingSpeechLikeFraction: Double?
    public let recoveryCandidate: TranscriptionResult?
    public let localFallbackAttempted: Bool
    public let localFallbackEngine: String?
    public let localFallbackModel: String?
    public let localInferenceSeconds: Double?
    public let localPromptTokenCount: Int?
    public let localValidationReasons: [TranscriptionIntegrityReason]?
    public let localFallbackSkippedBecauseNotReady: Bool

    public init(
        reasons: [TranscriptionIntegrityReason],
        timing: TranscriptionTiming?,
        providerRetryOccurred: Bool,
        lexicalCoverageEndSeconds: Double?,
        trailingSpeechLikeFrameCount: Int?,
        trailingSpeechLikeFraction: Double?,
        recoveryCandidate: TranscriptionResult? = nil,
        localFallbackAttempted: Bool = false,
        localFallbackEngine: String? = nil,
        localFallbackModel: String? = nil,
        localInferenceSeconds: Double? = nil,
        localPromptTokenCount: Int? = nil,
        localValidationReasons: [TranscriptionIntegrityReason]? = nil,
        localFallbackSkippedBecauseNotReady: Bool = false
    ) {
        self.reasons = reasons
        self.timing = timing
        self.providerRetryOccurred = providerRetryOccurred
        self.lexicalCoverageEndSeconds = lexicalCoverageEndSeconds
        self.trailingSpeechLikeFrameCount = trailingSpeechLikeFrameCount
        self.trailingSpeechLikeFraction = trailingSpeechLikeFraction
        self.recoveryCandidate = recoveryCandidate
        self.localFallbackAttempted = localFallbackAttempted
        self.localFallbackEngine = localFallbackEngine
        self.localFallbackModel = localFallbackModel
        self.localInferenceSeconds = localInferenceSeconds
        self.localPromptTokenCount = localPromptTokenCount
        self.localValidationReasons = localValidationReasons
        self.localFallbackSkippedBecauseNotReady =
            localFallbackSkippedBecauseNotReady
    }

    public var errorDescription: String? {
        "Groq recovery could not produce a trusted complete transcript. The best available text and original audio were preserved for review or retry."
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
                speechEvidence: speechEvidence,
                protectionMode: protectionMode
            )
            guard !retryCheck.result.isSuspicious else {
                return try recoverBestProviderCandidateOrThrow(
                    retryCheck: retryCheck,
                    checkedCandidates: [(retry, retryCheck)],
                    timing: retry.timing,
                    speechEvidence: speechEvidence,
                    protectionMode: protectionMode
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
            speechEvidence: speechEvidence,
            protectionMode: protectionMode
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

        let retry: TranscriptionResult
        if firstCheck.result.reasons.contains(.missingSpeechCoverage) {
            do {
                retry = try await base.transcribeCoverageRecovery(
                    fileURL: fileURL,
                    temporaryDirectory: temporaryDirectory
                )
            } catch {
                return try recoverBestProviderCandidateOrThrow(
                    retryCheck: firstCheck,
                    checkedCandidates: [(first, firstCheck)],
                    timing: first.timing,
                    speechEvidence: speechEvidence,
                    protectionMode: protectionMode
                )
            }
        } else {
            retry = try await base.transcribe(
                fileURL: fileURL,
                prompt: "",
                temporaryDirectory: temporaryDirectory
            )
        }
        let retryCheck = check(
            retry,
            prompt: "",
            audioDurationSeconds: audioDurationSeconds,
            expectedChunkCount: expectedChunkCount,
            speechEvidence: speechEvidence,
            protectionMode: protectionMode
        )
        guard !retryCheck.result.isSuspicious else {
            return try recoverBestProviderCandidateOrThrow(
                retryCheck: retryCheck,
                checkedCandidates: [
                    (first, firstCheck),
                    (retry, retryCheck),
                ],
                timing: combinedTiming(first.timing, retry.timing),
                speechEvidence: speechEvidence,
                protectionMode: protectionMode
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

    private func recoverBestProviderCandidateOrThrow(
        retryCheck: IntegrityCheck,
        checkedCandidates: [(
            TranscriptionResult,
            IntegrityCheck
        )],
        timing: TranscriptionTiming?,
        speechEvidence: SpeechEvidenceResult?,
        protectionMode: SpeechProtectionMode
    ) throws -> ReliableTranscription {
        if let candidate = recoverableCandidate(checkedCandidates),
           let candidateCheck = checkedCandidates.first(where: {
               $0.0 == candidate
           })?.1 {
            return try coverageUncertainResult(
                candidate,
                check: candidateCheck,
                timing: timing,
                speechEvidence: speechEvidence,
                protectionMode: protectionMode,
                wasRetried: true
            )
        }
        throw integrityFailure(
            retryCheck,
            timing: timing,
            recoveryCandidate: recoverableCandidate(checkedCandidates)
        )
    }

    private func coverageUncertainResult(
        _ candidate: TranscriptionResult,
        check: IntegrityCheck,
        timing: TranscriptionTiming?,
        speechEvidence: SpeechEvidenceResult?,
        protectionMode: SpeechProtectionMode,
        wasRetried: Bool
    ) throws -> ReliableTranscription {
        let timedCandidate = TranscriptionResult(
            text: candidate.text,
            words: candidate.words,
            segments: candidate.segments,
            durationSeconds: candidate.durationSeconds,
            chunkCount: candidate.chunkCount,
            timing: timing ?? candidate.timing,
            engine: candidate.engine,
            model: candidate.model,
            localInferenceSeconds: candidate.localInferenceSeconds,
            localPromptTokenCount: candidate.localPromptTokenCount
        )
        return try protectedResult(
            timedCandidate,
            wasRetried: wasRetried,
            speechEvidence: speechEvidence,
            protectionMode: protectionMode,
            integrityCheck: check,
            coverageUncertain: true
        )
    }

    private func protectedResult(
        _ transcription: TranscriptionResult,
        wasRetried: Bool,
        speechEvidence: SpeechEvidenceResult?,
        protectionMode: SpeechProtectionMode,
        integrityCheck: IntegrityCheck,
        coverageUncertain: Bool = false
    ) throws -> ReliableTranscription {
        guard let speechEvidence, protectionMode != .off else {
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
                        .speechLikeFraction,
                engine: transcription.engine,
                model: transcription.model,
                localInferenceSeconds: transcription.localInferenceSeconds,
                localPromptTokenCount: transcription.localPromptTokenCount,
                coverageUncertain: coverageUncertain
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
                    .speechLikeFraction,
            engine: protected.transcription.engine,
            model: protected.transcription.model,
            localInferenceSeconds:
                protected.transcription.localInferenceSeconds,
            localPromptTokenCount:
                protected.transcription.localPromptTokenCount,
            coverageUncertain: coverageUncertain
        )
    }

    private func check(
        _ result: TranscriptionResult,
        prompt: String,
        audioDurationSeconds: Double,
        expectedChunkCount: Int,
        speechEvidence: SpeechEvidenceResult?,
        protectionMode: SpeechProtectionMode
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
        let evaluatesProviderSpeechCoverage = protectionMode == .enhanced
        let hasSustainedSpeechAfterProviderCoverage =
            evaluatesProviderSpeechCoverage
            && trailingSpeechEvidence?.hasSustainedSpeech == true
            && (trailingSpeechEvidence?.speechLikeFraction ?? 0) >= 0.05
        let hasSustainedSpeechBetweenProviderWords =
            evaluatesProviderSpeechCoverage
            && containsSustainedSpeechBetweenProviderWords(
                result,
                audioDurationSeconds: audioDurationSeconds,
                speechEvidence: speechEvidence
            )
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
                        || hasSustainedSpeechBetweenProviderWords
                )
            ),
            providerLexicalCoverageEndSeconds: providerCoverageEnd,
            trailingSpeechEvidence: trailingSpeechEvidence
        )
    }

    private func containsSustainedSpeechBetweenProviderWords(
        _ result: TranscriptionResult,
        audioDurationSeconds: Double,
        speechEvidence: SpeechEvidenceResult?
    ) -> Bool {
        guard let speechEvidence else { return false }
        let words = result.words
            .filter {
                $0.start.isFinite
                    && $0.end.isFinite
                    && $0.end > $0.start
                    && $0.start >= 0
                    && $0.end <= audioDurationSeconds + 0.5
            }
            .sorted { $0.start < $1.start }
        guard words.count >= 2 else { return false }

        for (previous, next) in zip(words, words.dropFirst()) {
            let gapStart = previous.end + 0.15
            let gapEnd = next.start - 0.15
            guard gapEnd - gapStart >= 0.75 else { continue }
            let local = speechEvidence.evidence(
                from: gapStart,
                to: min(gapEnd, speechEvidence.analyzedDurationSeconds)
            )
            if local.hasSustainedSpeech,
               local.speechLikeFraction >= 0.10 {
                return true
            }
        }
        return false
    }

    private func providerLexicalCoverageEnd(
        _ result: TranscriptionResult
    ) -> Double? {
        let canonicalTokens = normalizedTokens(result.text)
        guard !canonicalTokens.isEmpty else { return nil }

        // Segment timestamps are acoustic windows, not lexical boundaries.
        // A segment may reach the end of the audio even when its returned text
        // omits later speech, so it must never substitute for word coverage.
        // Sparse or ambiguous word alignment still fails open; duration and
        // chunk-count checks continue to apply.
        guard !result.words.isEmpty else { return nil }
        var canonicalIndex = canonicalTokens.startIndex
        var latestValidEnd: Double?
        for word in result.words {
            let tokens = normalizedTokens(word.word)
            guard !tokens.isEmpty else { continue }
            for token in tokens {
                guard canonicalIndex < canonicalTokens.endIndex,
                      canonicalTokens[canonicalIndex] == token else {
                    return nil
                }
                canonicalTokens.formIndex(after: &canonicalIndex)
            }
            if word.end.isFinite,
               word.start.isFinite,
               word.end > word.start {
                latestValidEnd = max(latestValidEnd ?? word.end, word.end)
            }
        }
        guard canonicalIndex == canonicalTokens.endIndex else { return nil }
        return latestValidEnd
    }

    private func normalizedTokens(_ value: String) -> [String] {
        value.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private func integrityFailure(
        _ check: IntegrityCheck,
        timing: TranscriptionTiming?,
        recoveryCandidate: TranscriptionResult? = nil,
        localFallbackAttempted: Bool = false,
        localFallbackEngine: String? = nil,
        localFallbackModel: String? = nil,
        localInferenceSeconds: Double? = nil,
        localPromptTokenCount: Int? = nil,
        localValidationReasons: [TranscriptionIntegrityReason]? = nil,
        localFallbackSkippedBecauseNotReady: Bool = false
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
                check.trailingSpeechEvidence?.speechLikeFraction,
            recoveryCandidate: recoveryCandidate,
            localFallbackAttempted: localFallbackAttempted,
            localFallbackEngine: localFallbackEngine,
            localFallbackModel: localFallbackModel,
            localInferenceSeconds: localInferenceSeconds,
            localPromptTokenCount: localPromptTokenCount,
            localValidationReasons: localValidationReasons,
            localFallbackSkippedBecauseNotReady:
                localFallbackSkippedBecauseNotReady
        )
    }

    private func recoverableCoverageCandidate(
        _ candidates: [(TranscriptionResult, IntegrityCheck)]
    ) -> TranscriptionResult? {
        candidates
            .filter { transcription, check in
                !transcription.text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
                    && check.result.reasons.contains(.missingSpeechCoverage)
                    && !check.result.reasons.contains(.promptLeakage)
                    && !check.result.reasons.contains(.emptyTranscript)
            }
            .map(\.0)
            .max(by: preferredRecoveryCandidate)
    }

    private func recoverablePromptLeakageCandidate(
        _ candidates: [(TranscriptionResult, IntegrityCheck)]
    ) -> TranscriptionResult? {
        candidates
            .filter { transcription, check in
                let reasons = check.result.reasons
                return !transcription.text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
                    && !reasons.contains(.emptyTranscript)
                    && reasons.contains(.promptLeakage)
                    && reasons.allSatisfy {
                        $0 == .missingSpeechCoverage || $0 == .promptLeakage
                    }
            }
            .map(\.0)
            .max(by: preferredRecoveryCandidate)
    }

    private func recoverableCandidate(
        _ candidates: [(TranscriptionResult, IntegrityCheck)]
    ) -> TranscriptionResult? {
        recoverableCoverageCandidate(candidates)
            ?? recoverablePromptLeakageCandidate(candidates)
    }

    private func preferredRecoveryCandidate(
        _ lhs: TranscriptionResult,
        _ rhs: TranscriptionResult
    ) -> Bool {
        let lhsWords = lhs.text.split(whereSeparator: \.isWhitespace).count
        let rhsWords = rhs.text.split(whereSeparator: \.isWhitespace).count
        if lhsWords != rhsWords { return lhsWords < rhsWords }
        return lhs.text.count < rhs.text.count
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
