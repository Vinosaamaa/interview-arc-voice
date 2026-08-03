import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func completeRecordingPassesCheapLocalIntegrityChecks() {
    let result = RecordingIntegrityEvaluator.evaluate(
        RecordingIntegrityEvidence(
            wallDurationSeconds: 120,
            decodedDurationSeconds: 119.7,
            fileSizeBytes: 720_000,
            decodedFrameCount: 1_915_200,
            writeErrorDescription: nil
        )
    )

    #expect(result.isComplete)
    #expect(result.reasons.isEmpty)
}

@Test func interruptedRecordingIsRejectedWithoutCallingTranscription() {
    let result = RecordingIntegrityEvaluator.evaluate(
        RecordingIntegrityEvidence(
            wallDurationSeconds: 120,
            decodedDurationSeconds: 41,
            fileSizeBytes: 250_000,
            decodedFrameCount: 656_000,
            writeErrorDescription: "disk full"
        )
    )

    #expect(!result.isComplete)
    #expect(result.reasons.contains(.audioWriteFailed))
    #expect(result.reasons.contains(.durationMismatch))
}

@Test func headerOnlyRecordingRequiresANewCaptureInsteadOfRetranscription() {
    let recovery = RecordingRecoveryPolicy.action(
        for: RecordingIntegrityEvidence(
            wallDurationSeconds: 12,
            decodedDurationSeconds: 0,
            fileSizeBytes: 4_096,
            decodedFrameCount: 0,
            writeErrorDescription: nil
        )
    )

    #expect(recovery == .recordAgain)
}

@Test func interruptedButPlayableRecordingIsPreservedWithoutOfferingRetranscription() {
    let recovery = RecordingRecoveryPolicy.action(
        for: RecordingIntegrityEvidence(
            wallDurationSeconds: 30,
            decodedDurationSeconds: 8,
            fileSizeBytes: 64_000,
            decodedFrameCount: 128_000,
            writeErrorDescription: "The audio device disconnected."
        )
    )

    #expect(recovery == .preserveWithoutRetry)
}

@Test func completeRecordingContinuesToTranscription() {
    let recovery = RecordingRecoveryPolicy.action(
        for: RecordingIntegrityEvidence(
            wallDurationSeconds: 30,
            decodedDurationSeconds: 29.8,
            fileSizeBytes: 180_000,
            decodedFrameCount: 476_800,
            writeErrorDescription: nil,
            encodedAudioBytes: 178_000
        )
    )

    #expect(recovery == .transcribe)
}

@Test func nearSilentAACCaptureRequiresANewRecordingInsteadOfTranscription() {
    let recovery = RecordingRecoveryPolicy.action(
        for: RecordingIntegrityEvidence(
            wallDurationSeconds: 4.99,
            decodedDurationSeconds: 4.99,
            fileSizeBytes: 24_896,
            decodedFrameCount: 79_808,
            writeErrorDescription: nil,
            encodedAudioBytes: 320
        )
    )

    #expect(recovery == .recordAgain)
}

@Test func shortSilentCaptureNeverReachesTheTranscriptionProvider() {
    let recovery = RecordingRecoveryPolicy.action(
        for: RecordingIntegrityEvidence(
            wallDurationSeconds: 0.85,
            decodedDurationSeconds: 0.82,
            fileSizeBytes: 8_192,
            decodedFrameCount: 13_120,
            writeErrorDescription: nil,
            encodedAudioBytes: 2_400,
            peakPowerDecibels: -82
        )
    )

    #expect(recovery == .recordAgain)
}

@Test func shortCaptureWithRealSpeechCanStillBeTranscribed() {
    let recovery = RecordingRecoveryPolicy.action(
        for: RecordingIntegrityEvidence(
            wallDurationSeconds: 0.85,
            decodedDurationSeconds: 0.82,
            fileSizeBytes: 8_192,
            decodedFrameCount: 13_120,
            writeErrorDescription: nil,
            encodedAudioBytes: 2_400,
            peakPowerDecibels: -54
        )
    )

    #expect(recovery == .transcribe)
}

@Test func normalTranscriptDoesNotTriggerASecondProviderCall() async throws {
    let transcriber = CountingTranscriber(results: [
        TranscriptionResult(
            text: "I would use Kahn's algorithm and track indegrees.",
            words: [],
            durationSeconds: 15,
            chunkCount: 1
        ),
    ])
    let reliable = ReliableSpeechTranscriber(base: transcriber)

    let result = try await reliable.transcribe(
        fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
        prompt: "",
        temporaryDirectory: URL(fileURLWithPath: "/tmp"),
        audioDurationSeconds: 15,
        expectedChunkCount: 1
    )

    #expect(result.wasRetried == false)
    let normalCallCount = await transcriber.callCount
    #expect(normalCallCount == 1)
}

@Test func suspiciousTranscriptRetriesOnceWithoutAPrompt() async throws {
    let transcriber = CountingTranscriber(results: [
        TranscriptionResult(
            text: "",
            words: [],
            durationSeconds: 2,
            chunkCount: 1
        ),
        TranscriptionResult(
            text: "This is the complete answer with the closing statement.",
            words: [],
            durationSeconds: 15,
            chunkCount: 1
        ),
    ])
    let reliable = ReliableSpeechTranscriber(base: transcriber)

    let result = try await reliable.transcribe(
        fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
        prompt: "Context: Basic Calculator II. Vocabulary: stack, operator.",
        temporaryDirectory: URL(fileURLWithPath: "/tmp"),
        audioDurationSeconds: 15,
        expectedChunkCount: 1
    )

    #expect(result.wasRetried)
    #expect(result.transcription.text.contains("complete answer"))
    let retryPrompts = await transcriber.prompts
    #expect(retryPrompts == [
        "Context: Basic Calculator II. Vocabulary: stack, operator.",
        "",
    ])
}

@Test func transcriptEndingBeforeTailSpeechRetriesWithEnhancedProtection() async throws {
    let partial = TranscriptionResult(
        text: "The first part was transcribed but the complete ending was lost.",
        words: timestampedWords(
            "The first part was transcribed but the complete ending was lost.",
            endingAt: 34
        ),
        segments: [
            TranscriptSegment(
                start: 0,
                end: 34,
                text: "The first part was transcribed but the complete ending was lost."
            ),
            // Groq can report a final no-text segment that reaches the audio
            // duration. It must not count as lexical transcript coverage.
            TranscriptSegment(
                start: 34,
                end: 53,
                text: "",
                averageLogProbability: -1.4,
                noSpeechProbability: 0.91
            ),
        ],
        durationSeconds: 53,
        chunkCount: 1,
        timing: TranscriptionTiming(
            chunkPreparationSeconds: 0.01,
            providerWaitSeconds: 0.60,
            responseProcessingSeconds: 0.01
        )
    )
    let complete = TranscriptionResult(
        text: "The first chunk was transcribed, and the complete ending is present.",
        words: timestampedWords(
            "The first chunk was transcribed and the complete ending is present.",
            endingAt: 52.7
        ),
        segments: [
            TranscriptSegment(start: 0, end: 18, text: "The first chunk was transcribed,"),
            TranscriptSegment(start: 18, end: 52.7, text: "and the complete ending is present."),
        ],
        durationSeconds: 53,
        chunkCount: 1,
        timing: TranscriptionTiming(
            chunkPreparationSeconds: 0.01,
            providerWaitSeconds: 0.60,
            responseProcessingSeconds: 0.01
        )
    )
    let transcriber = CountingTranscriber(results: [partial, complete])
    let reliable = ReliableSpeechTranscriber(base: transcriber)

    let result = try await reliable.transcribe(
        fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
        prompt: "Context vocabulary",
        temporaryDirectory: URL(fileURLWithPath: "/tmp"),
        audioDurationSeconds: 53,
        expectedChunkCount: 1,
        speechEvidence: sustainedSpeechEvidence(durationSeconds: 53),
        protectionMode: .enhanced
    )

    #expect(result.wasRetried)
    #expect(result.transcription.text.contains("complete ending"))
    let callCount = await transcriber.callCount
    #expect(callCount == 2)
}

@Test func malformedWordTimestampCannotFallBackToAFullLengthSegment() async throws {
    let partial = malformedFullLengthSegmentPartial()
    let completeText = "The provider returned timestamped text and preserved the spoken ending."
    let complete = TranscriptionResult(
        text: completeText,
        words: timestampedWords(completeText, endingAt: 80.6),
        segments: [
            TranscriptSegment(start: 0, end: 80.6, text: completeText),
        ],
        durationSeconds: 80.88,
        chunkCount: 1
    )
    let transcriber = CountingTranscriber(results: [partial, complete])
    let reliable = ReliableSpeechTranscriber(base: transcriber)

    let result = try await reliable.transcribe(
        fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
        prompt: "Context vocabulary",
        temporaryDirectory: URL(fileURLWithPath: "/tmp"),
        audioDurationSeconds: 80.88,
        expectedChunkCount: 1,
        speechEvidence: sustainedSpeechEvidence(durationSeconds: 80.88),
        protectionMode: .enhanced
    )

    #expect(result.wasRetried)
    #expect(result.transcription.text == completeText)
    #expect(await transcriber.callCount == 2)
    #expect(await transcriber.coverageRecoveryCallCount == 1)
}

@Test func sustainedSpeechInsideAProviderWordGapTriggersRetry() async throws {
    let partialText = "How do I actually search in Codex UI?"
    let partialWords = [
        TranscriptWord(word: "How", start: 0.1, end: 0.35),
        TranscriptWord(word: "do", start: 0.4, end: 0.55),
        TranscriptWord(word: "I", start: 0.6, end: 0.7),
        TranscriptWord(word: "actually", start: 0.75, end: 1.15),
        TranscriptWord(word: "search", start: 1.2, end: 1.55),
        TranscriptWord(word: "in", start: 1.6, end: 1.75),
        TranscriptWord(word: "Codex", start: 1.8, end: 2.2),
        TranscriptWord(word: "UI?", start: 13.5, end: 13.84),
    ]
    let partial = TranscriptionResult(
        text: partialText,
        words: partialWords,
        segments: [
            TranscriptSegment(start: 0, end: 13.84, text: partialText),
        ],
        durationSeconds: 14.4,
        chunkCount: 1
    )
    let completeText = partialText
        + " And which model is active right now?"
    let complete = TranscriptionResult(
        text: completeText,
        words: timestampedWords(completeText, endingAt: 14.2),
        durationSeconds: 14.4,
        chunkCount: 1
    )
    let transcriber = CountingTranscriber(results: [partial, complete])
    let reliable = ReliableSpeechTranscriber(base: transcriber)

    let result = try await reliable.transcribe(
        fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
        prompt: "",
        temporaryDirectory: URL(fileURLWithPath: "/tmp"),
        audioDurationSeconds: 14.4,
        speechEvidence: sustainedSpeechEvidence(durationSeconds: 14.4),
        protectionMode: .enhanced
    )

    #expect(result.wasRetried)
    #expect(result.transcription.text == completeText)
    #expect(await transcriber.callCount == 2)
}

@Test func basicProtectionDoesNotRejectProviderTextForInternalTimestampGaps() async throws {
    let text = "How do I actually search in Codex UI?"
    let transcription = TranscriptionResult(
        text: text,
        words: [
            TranscriptWord(word: "How", start: 0.1, end: 0.35),
            TranscriptWord(word: "do", start: 0.4, end: 0.55),
            TranscriptWord(word: "I", start: 0.6, end: 0.7),
            TranscriptWord(word: "actually", start: 0.75, end: 1.15),
            TranscriptWord(word: "search", start: 1.2, end: 1.55),
            TranscriptWord(word: "in", start: 1.6, end: 1.75),
            TranscriptWord(word: "Codex", start: 1.8, end: 2.2),
            TranscriptWord(word: "UI?", start: 13.5, end: 13.84),
        ],
        durationSeconds: 14.4,
        chunkCount: 1
    )
    let transcriber = CountingTranscriber(results: [transcription])
    let reliable = ReliableSpeechTranscriber(base: transcriber)

    let result = try await reliable.transcribe(
        fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
        prompt: "",
        temporaryDirectory: URL(fileURLWithPath: "/tmp"),
        audioDurationSeconds: 14.4,
        speechEvidence: sustainedSpeechEvidence(durationSeconds: 14.4),
        protectionMode: .basic
    )

    #expect(result.transcription.text == text)
    #expect(!result.wasRetried)
    #expect(await transcriber.callCount == 1)
}

@Test func repeatedMalformedWordTimestampPartialFailsInsteadOfDelivering() async {
    let partial = malformedFullLengthSegmentPartial()
    let transcriber = CountingTranscriber(results: [partial, partial])
    let reliable = ReliableSpeechTranscriber(base: transcriber)

    do {
        _ = try await reliable.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
            prompt: "Context vocabulary",
            temporaryDirectory: URL(fileURLWithPath: "/tmp"),
            audioDurationSeconds: 80.88,
            expectedChunkCount: 1,
            speechEvidence: sustainedSpeechEvidence(durationSeconds: 80.88),
            protectionMode: .enhanced
        )
        Issue.record("Expected a recoverable missing-speech failure")
    } catch let failure as TranscriptionIntegrityFailure {
        #expect(failure.reasons.contains(.missingSpeechCoverage))
        #expect(failure.providerRetryOccurred)
        #expect(failure.lexicalCoverageEndSeconds == 72)
        #expect(failure.trailingSpeechLikeFrameCount != nil)
        #expect(failure.recoveryCandidate?.text == partial.text)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await transcriber.callCount == 2)
}

@Test func localFallbackCanRecoverAfterWholeAndChunkedCoverageFailures() async throws {
    let partial = malformedFullLengthSegmentPartial()
    let completeText = "The local fallback preserved the complete spoken answer through the ending."
    let localResult = TranscriptionResult(
        text: completeText,
        words: [],
        durationSeconds: 12,
        chunkCount: 1,
        engine: "whisperkit",
        model: "base.en",
        localInferenceSeconds: 1.25,
        localPromptTokenCount: 17
    )
    let provider = CountingTranscriber(results: [partial, partial])
    let local = CountingTranscriber(results: [localResult])
    let reliable = ReliableSpeechTranscriber(
        base: provider,
        localFallback: local
    )

    let result = try await reliable.transcribe(
        fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
        prompt: "Context vocabulary",
        temporaryDirectory: URL(fileURLWithPath: "/tmp"),
        audioDurationSeconds: 80.88,
        expectedChunkCount: 3,
        speechEvidence: sustainedSpeechEvidence(durationSeconds: 80.88),
        protectionMode: .enhanced
    )

    #expect(result.transcription.text == completeText)
    #expect(result.wasRetried)
    #expect(result.engine == "whisperkit")
    #expect(result.model == "base.en")
    #expect(result.localInferenceSeconds == 1.25)
    #expect(result.localPromptTokenCount == 17)
    #expect(result.transcription.durationSeconds == 80.88)
    #expect(result.transcription.chunkCount == 3)
    #expect(await provider.callCount == 2)
    #expect(await provider.coverageRecoveryCallCount == 1)
    #expect(await local.callCount == 1)
    #expect(await local.prompts == ["Context vocabulary"])
}

@Test func initialProviderFailureStillUsesLocalCoverageRecovery() async throws {
    let partial = malformedFullLengthSegmentPartial()
    let completeText = "Local recovery remains available after the initial provider request fails."
    let provider = CountingTranscriber(
        results: [partial],
        failuresBeforeResults: 1
    )
    let local = CountingTranscriber(
        results: [TranscriptionResult(
            text: completeText,
            words: [],
            durationSeconds: 5,
            chunkCount: 1,
            engine: "whisperkit",
            model: "base.en"
        )]
    )
    let reliable = ReliableSpeechTranscriber(
        base: provider,
        localFallback: local
    )

    let result = try await reliable.transcribe(
        fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
        prompt: "Context vocabulary",
        temporaryDirectory: URL(fileURLWithPath: "/tmp"),
        audioDurationSeconds: 80.88,
        expectedChunkCount: 2,
        speechEvidence: sustainedSpeechEvidence(durationSeconds: 80.88),
        protectionMode: .enhanced
    )

    #expect(result.transcription.text == completeText)
    #expect(result.transcription.durationSeconds == 80.88)
    #expect(result.transcription.chunkCount == 2)
    #expect(await provider.callCount == 2)
    #expect(await local.callCount == 1)
}

@Test func twoPartialProviderResultsFailRecoverablyInsteadOfDeliveringEitherOne() async {
    let partial = TranscriptionResult(
        text: "Only the beginning is present.",
        words: timestampedWords("Only the beginning is present.", endingAt: 21),
        segments: [
            TranscriptSegment(start: 0, end: 21, text: "Only the beginning is present."),
            TranscriptSegment(start: 21, end: 53, text: ""),
        ],
        durationSeconds: 53,
        chunkCount: 1,
        timing: TranscriptionTiming(
            chunkPreparationSeconds: 0.01,
            providerWaitSeconds: 0.60,
            responseProcessingSeconds: 0.01
        )
    )
    let transcriber = CountingTranscriber(results: [partial, partial])
    let reliable = ReliableSpeechTranscriber(base: transcriber)

    do {
        _ = try await reliable.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
            prompt: "Context vocabulary",
            temporaryDirectory: URL(fileURLWithPath: "/tmp"),
            audioDurationSeconds: 53,
            expectedChunkCount: 1,
            speechEvidence: sustainedSpeechEvidence(durationSeconds: 53),
            protectionMode: .enhanced
        )
        Issue.record("Expected a recoverable suspicious-transcript failure")
    } catch let failure as TranscriptionIntegrityFailure {
        #expect(failure.reasons.contains(.missingSpeechCoverage))
        #expect(failure.providerRetryOccurred)
        #expect(failure.lexicalCoverageEndSeconds == 21)
        #expect(failure.trailingSpeechLikeFrameCount != nil)
        #expect(failure.trailingSpeechLikeFraction != nil)
        #expect(failure.timing?.providerWaitSeconds == 1.20)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let callCount = await transcriber.callCount
    #expect(callCount == 2)
    #expect(await transcriber.coverageRecoveryCallCount == 1)
}

@Test func uncertainLocalFallbackRemainsPreservedAndDiagnosable() async {
    let partial = malformedFullLengthSegmentPartial()
    let provider = CountingTranscriber(results: [partial, partial])
    let local = CountingTranscriber(
        results: [partial],
        engine: "whisperkit",
        model: "base.en"
    )
    let reliable = ReliableSpeechTranscriber(
        base: provider,
        localFallback: local
    )

    do {
        _ = try await reliable.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
            prompt: "Context vocabulary",
            temporaryDirectory: URL(fileURLWithPath: "/tmp"),
            audioDurationSeconds: 80.88,
            speechEvidence: sustainedSpeechEvidence(durationSeconds: 80.88),
            protectionMode: .enhanced
        )
        Issue.record("Expected local fallback to remain uncertain")
    } catch let failure as TranscriptionIntegrityFailure {
        #expect(failure.localFallbackAttempted)
        #expect(failure.localFallbackEngine == "whisperkit")
        #expect(failure.localFallbackModel == "base.en")
        #expect(failure.localValidationReasons?.contains(.missingSpeechCoverage) == true)
        #expect(failure.recoveryCandidate != nil)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func coldLocalFallbackNeverBlocksCoverageRecovery() async {
    let partial = malformedFullLengthSegmentPartial()
    let provider = CountingTranscriber(results: [partial, partial])
    let coldLocal = CountingTranscriber(
        results: [partial],
        engine: "whisperkit",
        model: "base.en",
        isReadyForImmediateTranscription: false
    )
    let reliable = ReliableSpeechTranscriber(
        base: provider,
        localFallback: coldLocal
    )

    do {
        _ = try await reliable.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
            prompt: "Context vocabulary",
            temporaryDirectory: URL(fileURLWithPath: "/tmp"),
            audioDurationSeconds: 80.88,
            speechEvidence: sustainedSpeechEvidence(durationSeconds: 80.88),
            protectionMode: .enhanced
        )
        Issue.record("Expected the provider candidate to remain uncertain")
    } catch let failure as TranscriptionIntegrityFailure {
        #expect(failure.recoveryCandidate?.text == partial.text)
        #expect(!failure.localFallbackAttempted)
        #expect(failure.localFallbackSkippedBecauseNotReady)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await coldLocal.callCount == 0)
}

@Test func combinedCoverageAndDurationFailureStillPreservesReviewableText() async {
    let partial = TranscriptionResult(
        text: "The usable beginning remains available for manual review.",
        words: timestampedWords(
            "The usable beginning remains available for manual review.",
            endingAt: 14
        ),
        durationSeconds: 14,
        chunkCount: 1
    )
    let transcriber = CountingTranscriber(results: [partial, partial])
    let reliable = ReliableSpeechTranscriber(base: transcriber)

    do {
        _ = try await reliable.transcribe(
            fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
            prompt: "Context vocabulary",
            temporaryDirectory: URL(fileURLWithPath: "/tmp"),
            audioDurationSeconds: 53,
            speechEvidence: sustainedSpeechEvidence(durationSeconds: 53),
            protectionMode: .enhanced
        )
        Issue.record("Expected an uncertain recovery candidate")
    } catch let failure as TranscriptionIntegrityFailure {
        #expect(failure.reasons.contains(.missingSpeechCoverage))
        #expect(failure.reasons.contains(.providerDurationMismatch))
        #expect(failure.recoveryCandidate?.text == partial.text)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func promptLeakageIsTreatedAsSuspicious() {
    let result = TranscriptionIntegrityEvaluator.evaluate(
        TranscriptionIntegrityEvidence(
            audioDurationSeconds: 30,
            providerDurationSeconds: 30,
            expectedChunkCount: 1,
            returnedChunkCount: 1,
            transcript: "Context Basic Calculator II Vocabulary stack operator precedence",
            prompt: "Context: Basic Calculator II. Vocabulary: stack, operator precedence."
        )
    )

    #expect(result.isSuspicious)
    #expect(result.reasons.contains(.promptLeakage))
}

@Test func sparseWordTimestampsAloneDoNotMakeTranscriptSuspicious() {
    let result = TranscriptionIntegrityEvaluator.evaluate(
        TranscriptionIntegrityEvidence(
            audioDurationSeconds: 120,
            providerDurationSeconds: 120,
            expectedChunkCount: 1,
            returnedChunkCount: 1,
            transcript: "This remains a complete transcript even when word alignment is sparse.",
            prompt: ""
        )
    )

    #expect(!result.isSuspicious)
}

private actor CountingTranscriber: SpeechTranscribing {
    nonisolated let diagnosticEngine: String
    nonisolated let diagnosticModel: String?
    private var results: [TranscriptionResult]
    private var failuresBeforeResults: Int
    nonisolated let isReadyForImmediateTranscription: Bool
    private(set) var prompts: [String] = []
    private(set) var coverageRecoveryCallCount = 0

    init(
        results: [TranscriptionResult],
        engine: String = "fixture",
        model: String? = nil,
        failuresBeforeResults: Int = 0,
        isReadyForImmediateTranscription: Bool = true
    ) {
        self.results = results
        self.failuresBeforeResults = max(0, failuresBeforeResults)
        diagnosticEngine = engine
        diagnosticModel = model
        self.isReadyForImmediateTranscription =
            isReadyForImmediateTranscription
    }

    var callCount: Int { prompts.count }

    func transcribe(
        fileURL: URL,
        prompt: String,
        temporaryDirectory: URL
    ) async throws -> TranscriptionResult {
        prompts.append(prompt)
        if failuresBeforeResults > 0 {
            failuresBeforeResults -= 1
            throw VoiceBridgeError.invalidResponse(503, "fixture failure")
        }
        guard !results.isEmpty else { throw VoiceBridgeError.emptyTranscript }
        return results.removeFirst()
    }

    func transcribeCoverageRecovery(
        fileURL: URL,
        temporaryDirectory: URL
    ) async throws -> TranscriptionResult {
        coverageRecoveryCallCount += 1
        prompts.append("")
        guard !results.isEmpty else { throw VoiceBridgeError.emptyTranscript }
        return results.removeFirst()
    }
}

private func sustainedSpeechEvidence(durationSeconds: Double) -> SpeechEvidenceResult {
    let frameDuration = 0.02
    let frameCount = Int(durationSeconds / frameDuration)
    let levels = (0..<frameCount).map { index in
        Float(index.isMultiple(of: 2) ? -24 : -34)
    }
    return SpeechEvidenceResult(
        containsSpeech: true,
        analyzedDurationSeconds: durationSeconds,
        speechLikeFrameCount: frameCount,
        longestSpeechRunFrames: frameCount,
        noiseFloorDecibels: -48,
        peakFrameDecibels: -24,
        vadSpeechFrameCount: frameCount,
        vadLongestSpeechRunFrames: frameCount,
        frameDurationSeconds: frameDuration,
        speechLikeFrames: Array(repeating: true, count: frameCount),
        frameDecibels: levels
    )
}

private func timestampedWords(
    _ text: String,
    endingAt end: Double
) -> [TranscriptWord] {
    let values = text.split(separator: " ").map(String.init)
    guard !values.isEmpty else { return [] }
    let duration = end / Double(values.count)
    return values.enumerated().map { index, value in
        TranscriptWord(
            word: value,
            start: Double(index) * duration,
            end: Double(index + 1) * duration
        )
    }
}

private func malformedFullLengthSegmentPartial() -> TranscriptionResult {
    let text = "The provider returned timestamped text but omitted the spoken ending."
    var words = timestampedWords(text, endingAt: 72)
    words[3] = TranscriptWord(
        word: words[3].word,
        start: words[3].start,
        end: words[3].start
    )
    return TranscriptionResult(
        text: text,
        words: words,
        segments: [
            TranscriptSegment(start: 0, end: 80.88, text: text),
        ],
        durationSeconds: 80.88,
        chunkCount: 1
    )
}
