import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func transientRefreshFailureRetainsLastKnownContext() {
    let previous = voiceContext(
        activityID: "course-schedule",
        runningSince: 1_000
    )

    #expect(
        VoiceContextRetentionPolicy().context(
            previous: previous,
            refreshed: nil
        ) == previous
    )
}

@Test func successfulEmptyRefreshClearsThePreviousActivity() {
    let previous = voiceContext(
        activityID: "course-schedule",
        runningSince: 1_000
    )
    let refreshed = VoiceContextResponse(
        protocolVersion: 1,
        date: "2026-07-24",
        focusedActivity: nil,
        specialist: nil,
        message: "No activity is running."
    )

    #expect(
        VoiceContextRetentionPolicy().context(
            previous: previous,
            refreshed: refreshed
        ) == refreshed
    )
}

@Test func aGeneralCaptureMayLateBindToAnActivityAlreadyRunningAtRecordStart() {
    let activity = focusedActivity(
        id: "course-schedule",
        runningSince: 1_000
    )

    #expect(
        LateCaptureBindingPolicy().activity(
            initiallyLinkedActivityID: nil,
            recordingStartedAtMilliseconds: 2_000,
            refreshedActivity: activity
        ) == activity
    )
}

@Test func aGeneralCaptureNeverBindsToAnActivityStartedAfterRecording() {
    let activity = focusedActivity(
        id: "new-problem",
        runningSince: 2_500
    )

    #expect(
        LateCaptureBindingPolicy().activity(
            initiallyLinkedActivityID: nil,
            recordingStartedAtMilliseconds: 2_000,
            refreshedActivity: activity
        ) == nil
    )
}

@Test func anAlreadyLinkedCaptureNeverMovesWhenFocusChanges() {
    let activity = focusedActivity(
        id: "new-problem",
        runningSince: 1_000
    )

    #expect(
        LateCaptureBindingPolicy().activity(
            initiallyLinkedActivityID: "original-problem",
            recordingStartedAtMilliseconds: 2_000,
            refreshedActivity: activity
        ) == nil
    )
}

@Test func memoExportUsesActivityTitleAndCreatesSiblingTranscript() {
    let date = Date(timeIntervalSince1970: 1_721_863_200)
    let plan = VoiceMemoExportPlan(
        activityTitle: "Course Schedule: BFS / DFS?",
        createdAt: date
    )
    let audio = URL(fileURLWithPath: "/tmp/\(plan.suggestedAudioFilename)")

    #expect(plan.suggestedAudioFilename == "Course Schedule BFS DFS.m4a")
    #expect(plan.transcriptURL(forAudioURL: audio).lastPathComponent == "Course Schedule BFS DFS.txt")
}

@Test func memoExportFallsBackToTimestampWhenUnlinked() {
    let date = Date(timeIntervalSince1970: 1_721_863_200)
    let plan = VoiceMemoExportPlan(activityTitle: nil, createdAt: date)

    #expect(plan.suggestedAudioFilename.hasPrefix("Interview Arc Voice "))
    #expect(plan.suggestedAudioFilename.hasSuffix(".m4a"))
}

@Test func lateBoundRecordingMovesFromTemporaryStorageToLinkedStorage() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "voice-store-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try RecordingStore(rootDirectory: root)
    let temporaryURL = store.nextTemporaryRecordingURL()
    try Data("audio".utf8).write(to: temporaryURL)
    let recording = RecordedCapture(
        url: temporaryURL,
        duration: 2,
        writtenFrameCount: 1,
        writeErrorDescription: nil
    )

    let promoted = try store.promoteToLinkedRecording(
        recording,
        activityID: "course-schedule"
    )

    #expect(promoted.url.deletingLastPathComponent() == store.recordingsDirectory)
    #expect(FileManager.default.fileExists(atPath: promoted.url.path))
    #expect(!FileManager.default.fileExists(atPath: temporaryURL.path))
}

@Test func playbackCompletionRecognizesAVFoundationClockReset() {
    let policy = PlaybackCompletionPolicy()

    #expect(policy.didFinish(previousTime: 40.9, currentTime: 0, duration: 41))
    #expect(!policy.didFinish(previousTime: 12, currentTime: 12, duration: 41))
    #expect(!policy.didFinish(previousTime: 12, currentTime: 0, duration: 41))
}

private func voiceContext(
    activityID: String,
    runningSince: Int64
) -> VoiceContextResponse {
    VoiceContextResponse(
        protocolVersion: 1,
        date: "2026-07-24",
        focusedActivity: focusedActivity(
            id: activityID,
            runningSince: runningSince
        ),
        specialist: nil,
        message: nil
    )
}

private func focusedActivity(
    id: String,
    runningSince: Int64
) -> FocusedVoiceActivity {
    FocusedVoiceActivity(
        activityId: id,
        questionId: nil,
        specialty: .coding,
        interviewArcSpecialty: "leetcode",
        title: id,
        prompt: nil,
        topics: [],
        tags: [],
        companies: [],
        projects: [],
        vocabularyPackIds: [],
        speechTerms: [],
        startedAt: runningSince - 500,
        runningSince: runningSince
    )
}
