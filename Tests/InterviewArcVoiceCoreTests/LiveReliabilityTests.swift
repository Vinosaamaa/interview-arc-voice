import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func pendingCaptureReconciliationRegistersOnlyUnknownServerIdentities() {
    let local = ["capture-a", "capture-b", "capture-c"]
    let server = ["capture-a", "capture-c"]

    #expect(PendingCaptureRegistrationPolicy().captureIDsToRegister(
        localCaptureIDs: local,
        serverCaptureIDs: server
    ) == ["capture-b"])
}

@Test func disconnectedFallbackUsesBoundedExponentialBackoff() {
    let policy = VoiceLiveUpdateFallbackPolicy()

    #expect(policy.delaySeconds(attempt: 0) == 15)
    #expect(policy.delaySeconds(attempt: 1) == 30)
    #expect(policy.delaySeconds(attempt: 9) == 120)
}

@Test func staleOrDuplicateLiveRevisionsAreIgnored() {
    let policy = VoiceLiveRevisionPolicy()

    #expect(policy.shouldApply(revision: 9, latestRevision: 8))
    #expect(!policy.shouldApply(revision: 8, latestRevision: 8))
    #expect(!policy.shouldApply(revision: 0, latestRevision: 8))
}

@Test func connectedFrameTriggersOneAuthoritativeSynchronization() throws {
    var latestRevision = 0
    let signal = try VoiceLiveFrameDecoder().decode(
        Data(#"{"type":"connected","revision":123}"#.utf8),
        latestRevision: &latestRevision
    )

    #expect(signal == .connected(revision: 123))
    #expect(latestRevision == 123)
}

@Test func liveDecoderAppliesOnlyNewPracticeRevisionsAfterConnection() throws {
    var latestRevision = 123
    let decoder = VoiceLiveFrameDecoder()
    let update = try decoder.decode(
        Data(
            #"{"type":"practice_changed","revision":124,"scope":"voice_intent","occurredAt":1000}"#
                .utf8
        ),
        latestRevision: &latestRevision
    )
    let stale = try decoder.decode(
        Data(
            #"{"type":"practice_changed","revision":123,"scope":"voice_intent","occurredAt":999}"#
                .utf8
        ),
        latestRevision: &latestRevision
    )

    #expect(
        update == .practiceChanged(
            VoiceLiveUpdate(
                type: "practice_changed",
                revision: 124,
                scope: "voice_intent",
                occurredAt: 1_000
            )
        )
    )
    #expect(stale == nil)
    #expect(latestRevision == 124)
}

@Test func unresolvedCaptureUsesBoundedSafetyReconciliation() {
    var capture = pendingCapture()
    capture.localState = .waitingForSpecialist
    let policy = VoicePendingReconciliationPolicy()

    #expect(policy.delaySeconds(captures: [capture], attempt: 0) == 15)
    #expect(policy.delaySeconds(captures: [capture], attempt: 1) == 30)
    #expect(policy.delaySeconds(captures: [capture], attempt: 9) == 120)
}

@Test func settledCapturesDoNotCreateRecurringStatusRequests() {
    var capture = pendingCapture()
    capture.localState = .excludedGracePeriod

    #expect(
        VoicePendingReconciliationPolicy()
            .delaySeconds(captures: [capture], attempt: 0) == nil
    )
}

@Test func interruptedAcceptedDeliveryRemainsReconciliationWorkAfterRelaunch() {
    var capture = pendingCapture()
    capture.localState = .acceptedDelivering
    capture.nextAttemptAt = nil

    #expect(
        VoicePendingReconciliationPolicy()
            .delaySeconds(captures: [capture], attempt: 0) == 15
    )
}

@Test func expandedTimerKeepsTheTitleAndClockClusterReadable() {
    #expect(!FloatingWidgetCompactTimerLayoutPolicy.showsPreviousMemoActionsWhenExpanded)
}

@Test func backgroundReconciliationNeverReplacesAnActiveRecordingPresentation() {
    #expect(
        VoiceBackgroundPresentationPolicy.decision(
            foreground: .recording,
            stateUnchangedDuringReconciliation: true
        ) == .preserveForeground
    )
}

@Test func backgroundReconciliationMayPublishStatusOnlyFromAnUnchangedIdleSurface() {
    #expect(
        VoiceBackgroundPresentationPolicy.decision(
            foreground: .idle,
            stateUnchangedDuringReconciliation: true
        ) == .publishBackgroundStatus
    )
    #expect(
        VoiceBackgroundPresentationPolicy.decision(
            foreground: .idle,
            stateUnchangedDuringReconciliation: false
        ) == .preserveForeground
    )
}

@Test func permanentCaptureConflictNeverBecomesHotRetryWork() {
    var capture = pendingCapture()
    capture.localState = .quarantinedConflict
    capture.nextAttemptAt = Date.distantPast

    #expect(!VoiceCaptureRetryPolicy().isDue(capture))
}

@Test func unresolvedLocalCaptureExpiresAfterTwentyFourHours() {
    let capture = pendingCapture(createdAt: Date(timeIntervalSince1970: 1_000))
    let now = Date(timeIntervalSince1970: 1_000 + 86_400)

    #expect(VoiceCaptureRetryPolicy().isExpired(capture, now: now))
}

private func pendingCapture(createdAt: Date = Date()) -> PendingVoiceCapture {
    PendingVoiceCapture(
        id: "capture-test",
        turnID: "turn-test",
        clipID: "clip-test",
        checksum: String(repeating: "a", count: 64),
        activity: FocusedVoiceActivity(
            activityId: "activity-test",
            questionId: "question-test",
            specialty: .coding,
            interviewArcSpecialty: "leetcode",
            title: "Test activity",
            prompt: nil,
            topics: [],
            tags: [],
            companies: [],
            projects: [],
            vocabularyPackIds: [],
            speechTerms: []
        ),
        transcript: "Test transcript",
        audioURL: URL(fileURLWithPath: "/tmp/capture-test.m4a"),
        durationSeconds: 1,
        occurredAt: createdAt,
        transcription: TranscriptionResult(
            text: "Test transcript",
            words: [],
            durationSeconds: 1,
            chunkCount: 1
        ),
        createdAt: createdAt,
        localState: .insertedRegistrationPending
    )
}
