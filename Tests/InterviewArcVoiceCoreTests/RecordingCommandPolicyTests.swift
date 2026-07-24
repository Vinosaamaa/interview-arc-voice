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
