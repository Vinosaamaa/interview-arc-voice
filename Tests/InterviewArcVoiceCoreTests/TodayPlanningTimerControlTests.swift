import Testing
@testable import InterviewArcVoiceCore

@Test func planningTimerControlPreservesOneAuthoritativeRunningActivity() {
    #expect(VoicePlanningTimerControlPolicy.isEnabled(
        subjectID: "a",
        status: .upcoming,
        runningSubjectID: nil,
        mutationInFlight: false
    ))
    #expect(VoicePlanningTimerControlPolicy.isEnabled(
        subjectID: "a",
        status: .running,
        runningSubjectID: "a",
        mutationInFlight: false
    ))
    #expect(!VoicePlanningTimerControlPolicy.isEnabled(
        subjectID: "b",
        status: .paused,
        runningSubjectID: "a",
        mutationInFlight: false
    ))
    #expect(!VoicePlanningTimerControlPolicy.isEnabled(
        subjectID: "a",
        status: .completed,
        runningSubjectID: nil,
        mutationInFlight: false
    ))
    #expect(!VoicePlanningTimerControlPolicy.isEnabled(
        subjectID: "a",
        status: .paused,
        runningSubjectID: nil,
        mutationInFlight: true
    ))
}
