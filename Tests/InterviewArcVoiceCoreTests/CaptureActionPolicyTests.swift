import Testing
@testable import InterviewArcVoiceCore

@Test func linkedCaptureCopyIncludesTheExactVoiceEnvelope() {
    let payload = CaptureActionPolicy.copyPayload(
        transcript: "I would use dynamic programming.",
        captureID: "capture-123",
        activityID: "activity-456",
        turnID: "voice-789"
    )

    #expect(payload.hasPrefix("I would use dynamic programming.\n\n"))
    #expect(payload.contains("<!-- interview-arc-voice:v2"))
    #expect(payload.contains("captureId: capture-123"))
    #expect(payload.contains("activityId: activity-456"))
    #expect(payload.contains("turnId: voice-789"))
}

@Test func generalDictationCopyRemainsPlainTextWithoutMetadata() {
    let payload = CaptureActionPolicy.copyPayload(
        transcript: "Plain dictation.",
        captureID: nil,
        activityID: nil,
        turnID: nil
    )

    #expect(payload == "Plain dictation.")
}

@Test func incompleteMetadataNeverProducesAPartialEnvelope() {
    let payload = CaptureActionPolicy.copyPayload(
        transcript: "Keep this plain.",
        captureID: "capture-123",
        activityID: nil,
        turnID: "voice-789"
    )

    #expect(payload == "Keep this plain.")
}

@Test func manualInsertionAlwaysResolvesToATerminalOutcome() {
    #expect(
        CaptureActionPolicy.insertionCompletion(inserted: true) == .delivered
    )
    #expect(
        CaptureActionPolicy.insertionCompletion(inserted: false) == .needsAttention
    )
}
