import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func smallLongRecordingIsSplitAtWhisperContextBoundary() {
    let windows = AudioChunkPlan.windows(
        durationSeconds: 45,
        fileSizeBytes: 300_000
    )

    #expect(windows.count == 2)
    #expect(windows[0].startSeconds == 0)
    #expect(windows[0].durationSeconds == 30)
    #expect(windows[1].startSeconds == 28.5)
    #expect(windows[1].durationSeconds == 16.5)
}

@Test func shortRecordingRemainsOneDirectUpload() {
    let windows = AudioChunkPlan.windows(
        durationSeconds: 29.5,
        fileSizeBytes: 262_758
    )

    #expect(windows == [
        AudioChunkWindow(startSeconds: 0, durationSeconds: 29.5),
    ])
}

@Test func durationChunkingKeepsEveryWindowWithinThirtySeconds() {
    let windows = AudioChunkPlan.windows(
        durationSeconds: 95,
        fileSizeBytes: 1_000_000
    )

    #expect(windows.count == 4)
    #expect(windows.allSatisfy { $0.durationSeconds <= 30 })
    #expect(windows.map(\.startSeconds) == [0, 28.5, 57, 85.5])
    #expect(windows.last?.durationSeconds == 9.5)
}

@Test func overlappingDurationChunksMergeWithoutDuplicatingBoundaryWords() {
    let first = AudioChunk(
        url: URL(fileURLWithPath: "/tmp/first.m4a"),
        offsetSeconds: 0,
        durationSeconds: 30,
        isTemporary: true
    )
    let second = AudioChunk(
        url: URL(fileURLWithPath: "/tmp/second.m4a"),
        offsetSeconds: 28.5,
        durationSeconds: 16,
        isTemporary: true
    )

    let assembled = TranscriptAssembler.assemble([
        (
            first,
            GroqTranscription(
                text: "before boundary repeated phrase",
                language: "en",
                duration: 30,
                words: nil,
                segments: nil
            )
        ),
        (
            second,
            GroqTranscription(
                text: "repeated phrase after boundary",
                language: "en",
                duration: 16,
                words: nil,
                segments: nil
            )
        ),
    ])

    #expect(assembled.text == "before boundary repeated phrase after boundary")
}
