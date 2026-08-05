import Foundation
import Testing
@testable import InterviewArcVoiceCore

private enum LiveReliabilityCodingKey: String, CodingKey {
    case body
}

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

@Test func explicitDeliveryRetrySignalForcesOneNativeRecoveryAttempt() {
    let policy = VoiceLiveRetryPolicy()

    #expect(policy.mode(for: "voice_delivery_retry") == .forced)
    #expect(policy.mode(for: "voice_capture") == .scheduled)
    #expect(policy.mode(for: "voice_intent") == .scheduled)
    #expect(policy.mode(for: "timer") == .none)
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
    #expect(FloatingWidgetCompactTimerLayoutPolicy.maximumClusterWidth <= 100)
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

@Test func deliveryRetryScheduleStartsAtFifteenSecondsAndIsBounded() {
    let policy = VoiceCaptureRetryPolicy()
    let now = Date(timeIntervalSince1970: 1_000)

    #expect(policy.nextAttempt(attempt: 1, now: now).timeIntervalSince(now) == 15)
    #expect(policy.nextAttempt(attempt: 2, now: now).timeIntervalSince(now) == 30)
    #expect(policy.nextAttempt(attempt: 7, now: now).timeIntervalSince(now) == 3_600)
    #expect(policy.nextAttempt(attempt: 50, now: now).timeIntervalSince(now) == 3_600)
}

@Test func permanentServerDeliveryConflictQuarantinesWithoutRetry() {
    let decision = VoiceDeliveryFailurePolicy().decision(
        error: InterviewArcAPIError(
            statusCode: 409,
            message: "Stored group differs.",
            code: "voice_response_group_conflict",
            retryable: false
        ),
        capture: pendingCapture()
    )

    #expect(decision == .quarantine(
        code: "voice_response_group_conflict",
        statusCode: 409,
        message: "Stored group differs."
    ))
}

@Test func retryableDeliveryEventuallyNeedsAttentionInsteadOfLoopingForever() {
    var capture = pendingCapture(createdAt: Date(timeIntervalSince1970: 1_000))
    capture.localState = .acceptedDelivering
    capture.retryAttempt = VoiceCaptureRetryPolicy.maximumAutomaticAttempts - 1
    capture.retryStartedAt = Date(timeIntervalSince1970: 1_000)
    let decision = VoiceDeliveryFailurePolicy().decision(
        error: InterviewArcAPIError(
            statusCode: 503,
            message: "Temporary Worker failure.",
            code: "worker_unavailable",
            retryable: true
        ),
        capture: capture,
        now: Date(timeIntervalSince1970: 1_100)
    )

    #expect(decision == .needsAttention(
        code: "worker_unavailable",
        statusCode: 503,
        message: "Temporary Worker failure."
    ))
}

@Test func retryableDeliveryPreservesTheServerErrorAndSchedulesOneStageRetry() {
    let now = Date(timeIntervalSince1970: 2_000)
    let decision = VoiceDeliveryFailurePolicy().decision(
        error: InterviewArcAPIError(
            statusCode: 503,
            message: "Temporary Worker failure.",
            code: "worker_unavailable",
            retryable: true
        ),
        capture: pendingCapture(),
        now: now
    )

    #expect(decision == .retry(
        attempt: 1,
        retryStartedAt: now,
        nextAttemptAt: now.addingTimeInterval(15),
        code: "worker_unavailable",
        statusCode: 503,
        message: "Temporary Worker failure."
    ))
}

@Test func successfulResponseDecodeFailureRemainsBoundedRetryWork() {
    let decodingError = DecodingError.keyNotFound(
        LiveReliabilityCodingKey.body,
        .init(codingPath: [], debugDescription: "Missing body")
    )
    let classified = VoiceDeliveryErrorPolicy().retryableAPIError(for: decodingError)

    #expect(classified?.code == "response_decoding_failure")
    #expect(classified?.retryable == true)
    #expect(VoiceDeliveryErrorPolicy().retryableAPIError(for: CocoaError(.fileNoSuchFile)) == nil)
}

@Test func needsAttentionDoesNotRestartBackgroundReconciliation() {
    var capture = pendingCapture()
    capture.localState = .needsAttention
    capture.lastErrorRetryable = true
    capture.nextAttemptAt = nil

    #expect(!VoiceCaptureRetryPolicy().isDue(capture))
    #expect(
        VoicePendingReconciliationPolicy()
            .delaySeconds(captures: [capture], attempt: 0) == nil
    )
}

@Test func authoritativeDeliveryReceiptPreventsDuplicateTranscriptRetry() {
    let blocker = VoiceDeliveryBlocker(
        captureId: "capture-test",
        turnId: "turn-test",
        status: "activity_related",
        responseTurnId: "response-test",
        memberOrder: 0,
        memberCount: 3,
        groupStatus: "provisional",
        groupDigest: String(repeating: "b", count: 64),
        canonicalUserTurnPresent: false,
        canonicalResponseTurnPresent: false,
        transcriptDeliveryState: "received",
        audioState: "not_registered",
        audioLossAcknowledged: false,
        deletionState: "not_started",
        lastError: nil,
        retryable: true,
        allowedActions: ["retry_delivery", "delete_exact_group"]
    )

    #expect(VoiceDeliveryReceiptPolicy().action(for: blocker) == .resumeAfterTranscript(
        responseGroupID: "response-test",
        responseGroupDigest: String(repeating: "b", count: 64)
    ))
}

@Test func authoritativeQuarantineReceiptStopsAutomaticDelivery() {
    let blocker = VoiceDeliveryBlocker(
        captureId: "capture-test",
        turnId: "turn-test",
        status: "quarantined_conflict",
        responseTurnId: "response-test",
        memberOrder: 0,
        memberCount: 3,
        groupStatus: "quarantined_conflict",
        groupDigest: String(repeating: "c", count: 64),
        canonicalUserTurnPresent: false,
        canonicalResponseTurnPresent: false,
        transcriptDeliveryState: "received",
        audioState: "not_registered",
        audioLossAcknowledged: false,
        deletionState: "not_started",
        lastError: "Canonical group needs repair.",
        retryable: false,
        allowedActions: ["restore_exact_group", "delete_exact_group"]
    )

    #expect(VoiceDeliveryReceiptPolicy().action(for: blocker) == .quarantine(
        responseGroupID: "response-test",
        responseGroupDigest: String(repeating: "c", count: 64)
    ))
}

@Test func absentDeliveryReceiptUsesNormalTranscriptDelivery() {
    #expect(VoiceDeliveryReceiptPolicy().action(for: nil) == .deliverTranscript)
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
    #expect(!policy.canRemoveSettledMetadata(
        complete,
        currentWorkbenchID: nil
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
