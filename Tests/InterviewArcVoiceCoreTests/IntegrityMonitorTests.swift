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
    private var results: [TranscriptionResult]
    private(set) var prompts: [String] = []

    init(results: [TranscriptionResult]) {
        self.results = results
    }

    var callCount: Int { prompts.count }

    func transcribe(
        fileURL: URL,
        prompt: String,
        temporaryDirectory: URL
    ) async throws -> TranscriptionResult {
        prompts.append(prompt)
        guard !results.isEmpty else { throw VoiceBridgeError.emptyTranscript }
        return results.removeFirst()
    }
}
