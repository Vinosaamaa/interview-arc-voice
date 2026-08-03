import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func localWhisperPromptReaderAcceptsTheMaximumAndRejectsOneExtraByte() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: directory) }

    let acceptedURL = directory.appendingPathComponent("accepted.txt")
    let rejectedURL = directory.appendingPathComponent("rejected.txt")
    try Data(repeating: 65, count: 65_536).write(to: acceptedURL)
    try Data(repeating: 66, count: 65_537).write(to: rejectedURL)

    #expect(try loadBoundedLocalWhisperPrompt(from: acceptedURL).utf8.count == 65_536)
    #expect(throws: LocalWhisperPromptFileError.oversized) {
        try loadBoundedLocalWhisperPrompt(from: rejectedURL)
    }
}

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
