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

@Test func expandedTimerKeepsTheTitleAndClockClusterReadableBesideMemoActions() {
    #expect(FloatingWidgetCompactTimerLayoutPolicy.showsPreviousMemoActionsWhenExpanded)
    #expect(FloatingWidgetCompactTimerLayoutPolicy.minimumTitleWidth >= 58)
    #expect(FloatingWidgetCompactTimerLayoutPolicy.maximumClusterWidth <= 84)
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

@Test func twentyFourHourPendingDeletionRequiresAuthoritativeServerTransition() {
    let capture = pendingCapture(createdAt: Date(timeIntervalSince1970: 1_000))
    let now = Date(timeIntervalSince1970: 1_000 + 86_400)
    let policy = VoiceCaptureLifecyclePolicy()

    #expect(policy.expiryAction(
        capture: capture,
        serverStatus: "pending",
        now: now
    ) == .expirePendingOnServer)
    #expect(policy.expiryAction(
        capture: capture,
        serverStatus: "unrelated",
        now: now
    ) == .deleteExcludedOnServer)
    #expect(policy.expiryAction(
        capture: capture,
        serverStatus: "expired_unclassified",
        now: now
    ) == .removeTerminalLocalEvidence)
}

@Test func uncertainEvidenceNeverAutoExpiresAndStillNeedsAttachOrDiscard() {
    var capture = pendingCapture(createdAt: Date(timeIntervalSince1970: 1_000))
    capture.localState = .needsDecision
    let now = Date(timeIntervalSince1970: 1_000 + 10 * 86_400)

    #expect(!VoiceCaptureRetryPolicy().isExpired(capture, now: now))
    #expect(VoiceCaptureLifecyclePolicy().expiryAction(
        capture: capture,
        serverStatus: "uncertain",
        now: now
    ) == .none)
}

@Test func workbenchCaptureSurfaceIsScopedWithoutDroppingLegacyCurrentActivity() {
    let policy = VoiceCaptureLifecyclePolicy()
    let matching = pendingCapture(workbenchID: "workbench-1")
    let other = pendingCapture(workbenchID: "workbench-2")
    let legacy = pendingCapture(workbenchID: nil)

    #expect(policy.belongsToCurrentWorkbench(
        matching,
        workbenchID: "workbench-1",
        currentActivityIDs: []
    ))
    #expect(!policy.belongsToCurrentWorkbench(
        other,
        workbenchID: "workbench-1",
        currentActivityIDs: []
    ))
    #expect(policy.belongsToCurrentWorkbench(
        legacy,
        workbenchID: "workbench-1",
        currentActivityIDs: ["activity-test"]
    ))
    #expect(!policy.belongsToCurrentWorkbench(
        legacy,
        workbenchID: nil,
        currentActivityIDs: ["activity-test"]
    ))
}

@Test func onlySettledMetadataLeavesAfterSuccessfulWorkbenchRollover() {
    let policy = VoiceCaptureLifecyclePolicy()
    var complete = pendingCapture(workbenchID: "workbench-1")
    complete.localState = .complete
    var unresolved = pendingCapture(workbenchID: "workbench-1")
    unresolved.localState = .acceptedDelivering

    #expect(policy.canRemoveSettledMetadata(
        complete,
        currentWorkbenchID: "workbench-2"
    ))
    #expect(!policy.canRemoveSettledMetadata(
        unresolved,
        currentWorkbenchID: "workbench-2"
    ))
}

private func pendingCapture(
    createdAt: Date = Date(),
    workbenchID: String? = nil
) -> PendingVoiceCapture {
    PendingVoiceCapture(
        id: "capture-test",
        turnID: "turn-test",
        clipID: "clip-test",
        checksum: String(repeating: "a", count: 64),
        activity: FocusedVoiceActivity(
            activityId: "activity-test",
            workbenchId: workbenchID,
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
