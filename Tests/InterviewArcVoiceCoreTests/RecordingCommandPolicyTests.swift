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

@Test func repeatedRecordCommandDuringMicrophoneStartupIsIgnored() {
    #expect(
        RecordingCommandPolicy.action(
            isRecording: false,
            isStarting: true,
            isBusy: false
        ) == .ignore
    )
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
