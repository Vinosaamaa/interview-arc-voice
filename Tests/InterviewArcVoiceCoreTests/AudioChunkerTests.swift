import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func smallLongRecordingRemainsOneDirectUpload() {
    let windows = AudioChunkPlan.windows(
        durationSeconds: 45,
        fileSizeBytes: 300_000
    )

    #expect(windows == [
        AudioChunkWindow(startSeconds: 0, durationSeconds: 45),
    ])
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

@Test func multiMinuteRecordingRemainsOneUploadWhenFileIsProviderSafe() {
    let windows = AudioChunkPlan.windows(
        durationSeconds: 95,
        fileSizeBytes: 1_000_000
    )

    #expect(windows == [
        AudioChunkWindow(startSeconds: 0, durationSeconds: 95),
    ])
}

@Test func recordingAboveProviderSizeLimitUsesBalancedOverlappingChunks() {
    let windows = AudioChunkPlan.windows(
        durationSeconds: 100,
        fileSizeBytes: 50 * 1024 * 1024
    )

    #expect(windows.count == 3)
    #expect(windows[0].startSeconds == 0)
    #expect(abs(windows[0].durationSeconds - 34.333333333333336) < 0.000_001)
    #expect(abs(windows[1].startSeconds - 32.833333333333336) < 0.000_001)
    #expect(abs(windows[2].startSeconds - 65.66666666666667) < 0.000_001)
    #expect(windows.allSatisfy { window in
        let estimatedBytes = Double(50 * 1024 * 1024) * window.durationSeconds / 100
        return estimatedBytes < Double(20 * 1024 * 1024)
    })
}

@Test func coverageRecoveryUsesImmediateThirtySecondOverlappingWindows() {
    let windows = AudioChunkPlan.coverageRecoveryWindows(
        durationSeconds: 95
    )

    #expect(windows == [
        AudioChunkWindow(startSeconds: 0, durationSeconds: 30),
        AudioChunkWindow(startSeconds: 28.5, durationSeconds: 30),
        AudioChunkWindow(startSeconds: 57, durationSeconds: 30),
        AudioChunkWindow(startSeconds: 85.5, durationSeconds: 9.5),
    ])
}

@Test func recoveryConcurrencyIsBoundedWithoutMultiplyingNearLimitBodies() {
    #expect(AudioChunkingPolicy.coverageRecovery.maximumConcurrentRequests == 4)
    #expect(AudioChunkingPolicy.providerLimit.maximumConcurrentRequests == 1)
    #expect(AudioChunkingPolicy.coverageRecovery.requestTimeoutInterval == 8)
    #expect(AudioChunkingPolicy.providerLimit.requestTimeoutInterval == 20)
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
