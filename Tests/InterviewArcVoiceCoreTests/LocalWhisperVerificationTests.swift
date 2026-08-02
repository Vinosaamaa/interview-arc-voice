import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func localVerificationReportContainsOnlyAggregateEvidence() throws {
    let result = ArcTranscriptionResult(
        text: "private words stay out of the report",
        words: [
            .init(word: "private", start: 0.2, end: 0.8),
            .init(word: "words", start: 0.9, end: 1.4),
        ],
        segments: [
            .init(start: 0, end: 1.5, text: "private words stay out")
        ],
        durationSeconds: 1.5,
        chunkCount: 1,
        engine: "whisperkit",
        model: "base.en",
        localInferenceSeconds: 0.5124,
        localPromptTokenCount: 7
    )

    let report = LocalWhisperVerificationReport(
        result: result,
        audioDurationSeconds: 2
    )
    let object = try #require(
        JSONSerialization.jsonObject(with: JSONEncoder().encode(report))
            as? [String: Any]
    )

    #expect(report.transcriptWordCount == 7)
    #expect(report.timestampWordCount == 2)
    #expect(report.segmentCount == 1)
    #expect(report.lexicalCoverageEndSeconds == 1.4)
    #expect(report.localInferenceMilliseconds == 512)
    #expect(report.promptConditioningUsed)
    #expect(report.promptTokenCount == 7)
    #expect(object["text"] == nil)
    #expect(object["transcript"] == nil)
    #expect(object["audioPath"] == nil)
    #expect(object["prompt"] == nil)
}

@Test func localVerificationReportNormalizesMissingAggregateMetadata() {
    let report = LocalWhisperVerificationReport(
        result: ArcTranscriptionResult(
            text: "one",
            words: [],
            durationSeconds: 0,
            chunkCount: 1,
            engine: "whisperkit",
            model: "base.en",
            localInferenceSeconds: -1,
            localPromptTokenCount: -3
        ),
        audioDurationSeconds: -10
    )

    #expect(report.audioDurationSeconds == 0)
    #expect(report.lexicalCoverageEndSeconds == 0)
    #expect(report.localInferenceMilliseconds == 0)
    #expect(report.promptTokenCount == 0)
    #expect(!report.promptConditioningUsed)
}

@Test func localVerificationFailureCodesDoNotExposeLocalizedMessages() {
    #expect(
        localWhisperVerificationFailureCode(for: LocalWhisperModelError.unavailable)
            == .modelUnavailable
    )
    #expect(
        localWhisperVerificationFailureCode(for: LocalWhisperModelError.corrupt)
            == .modelCorrupt
    )
    #expect(
        localWhisperVerificationFailureCode(for: CocoaError(.fileReadNoSuchFile))
            == .fileSystemFailed
    )
}
