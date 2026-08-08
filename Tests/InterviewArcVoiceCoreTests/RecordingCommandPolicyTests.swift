import Testing
@testable import InterviewArcVoiceCore

@Test func firstRecordCommandStartsCapture() {
    #expect(
        RecordingCommandPolicy.action(
            isRecording: false,
            isStarting: false,
            isBusy: false
        ) == .start
    )
}

@Test func repeatedRecordCommandDuringMicrophoneStartupCancelsPreparation() {
    #expect(
        RecordingCommandPolicy.action(
            isRecording: false,
            isStarting: true,
            isBusy: false
        ) == .cancelStart
    )
}

@Test func microphoneStartupBecomesLiveAsSoonAsTheCaptureBackendAdvances() {
    let policy = MicrophoneStartupReadinessPolicy(
        primaryTimeoutSeconds: 1.25,
        fallbackTimeoutSeconds: 1.25
    )

    #expect(policy.decision(
        elapsedSeconds: 0.02,
        captureBackendIsAdvancing: false,
        isUsingFallback: false
    ) == .wait)
    #expect(policy.decision(
        elapsedSeconds: 0.04,
        captureBackendIsAdvancing: true,
        isUsingFallback: false
    ) == .ready)
}

@Test func microphoneStartupUsesOneBoundedFallbackBeforeFailing() {
    let policy = MicrophoneStartupReadinessPolicy(
        primaryTimeoutSeconds: 1.25,
        fallbackTimeoutSeconds: 1.25
    )

    #expect(policy.decision(
        elapsedSeconds: 1.25,
        captureBackendIsAdvancing: false,
        isUsingFallback: false
    ) == .startFallback)
    #expect(policy.decision(
        elapsedSeconds: 1.25,
        captureBackendIsAdvancing: false,
        isUsingFallback: true
    ) == .fail)
}

@Test func microphonePreparationRemainsAllowedAfterStartupIsClaimed() {
    #expect(
        RecordingPreparationPolicy.canPrepare(
            hasGroqCredential: true,
            isBusy: false
        )
    )
}

@Test func microphonePreparationRequiresCredentialAndAnIdlePipeline() {
    #expect(
        !RecordingPreparationPolicy.canPrepare(
            hasGroqCredential: false,
            isBusy: false
        )
    )
    #expect(
        !RecordingPreparationPolicy.canPrepare(
            hasGroqCredential: true,
            isBusy: true
        )
    )
}

@Test func standardWidgetPresentationNeverPrecedesCaptureReadiness() {
    #expect(!RecordingStartupPresentationPolicy.shouldBeginPresentation(
        captureBackendIsReady: false,
        widgetSizeMode: .standard
    ))
    #expect(RecordingStartupPresentationPolicy.shouldBeginPresentation(
        captureBackendIsReady: true,
        widgetSizeMode: .standard
    ))
    #expect(!RecordingStartupPresentationPolicy.shouldBeginPresentation(
        captureBackendIsReady: false,
        widgetSizeMode: .mini
    ))
}

@Test func recordCommandStopsAnActiveCapture() {
    #expect(
        RecordingCommandPolicy.action(
            isRecording: true,
            isStarting: false,
            isBusy: false
        ) == .stop
    )
}

@Test func recorderActivityRemainsAuthoritativeWhenPresentationStateDrifts() {
    #expect(
        RecordingCommandPolicy.action(
            isRecording: true,
            isStarting: false,
            isBusy: true
        ) == .stop
    )
}

@Test func onlyAnUncommandedNativeRecorderCompletionSurfacesAsAFailure() {
    #expect(RecordingTerminationPolicy.shouldSurfaceUnexpectedTermination(
        isCaptureActive: true,
        completionWasExpected: false,
        alreadyReported: false
    ))
    #expect(!RecordingTerminationPolicy.shouldSurfaceUnexpectedTermination(
        isCaptureActive: true,
        completionWasExpected: true,
        alreadyReported: false
    ))
    #expect(!RecordingTerminationPolicy.shouldSurfaceUnexpectedTermination(
        isCaptureActive: false,
        completionWasExpected: false,
        alreadyReported: false
    ))
    #expect(!RecordingTerminationPolicy.shouldSurfaceUnexpectedTermination(
        isCaptureActive: true,
        completionWasExpected: false,
        alreadyReported: true
    ))
}
