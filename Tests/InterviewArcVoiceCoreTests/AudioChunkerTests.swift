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
    #expect(windows[0].durationSeconds == 23.25)
    #expect(windows[1].startSeconds == 21.75)
    #expect(windows[1].durationSeconds == 23.25)
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
    #expect(windows.allSatisfy { $0.durationSeconds >= 10 })
    #expect(windows[0].durationSeconds == 24.875)
    #expect(windows.map(\.startSeconds) == [0, 23.375, 46.75, 70.125])
}

@Test func recordingJustPastBoundaryDoesNotCreateTinyTailWindow() {
    let windows = AudioChunkPlan.windows(
        durationSeconds: 31,
        fileSizeBytes: 300_000
    )

    #expect(windows == [
        AudioChunkWindow(startSeconds: 0, durationSeconds: 16.25),
        AudioChunkWindow(startSeconds: 14.75, durationSeconds: 16.25),
    ])
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
