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

@Test func runningLearningTimerBlocksInterviewStartUntilLearningIsPaused() {
    #expect(!VoicePlanningTimerControlPolicy.isEnabled(
        subjectID: "interview-a",
        status: .upcoming,
        runningSubjectID: nil,
        learningTimerIsRunning: true,
        mutationInFlight: false
    ))
    #expect(!VoicePlanningTimerControlPolicy.isEnabled(
        subjectID: "interview-a",
        status: .paused,
        runningSubjectID: nil,
        learningTimerIsRunning: true,
        mutationInFlight: false
    ))
    #expect(VoicePlanningTimerControlPolicy.isEnabled(
        subjectID: "interview-a",
        status: .upcoming,
        runningSubjectID: nil,
        learningTimerIsRunning: false,
        mutationInFlight: false
    ))
    #expect(VoicePlanningTimerControlPolicy.isEnabled(
        subjectID: "interview-a",
        status: .running,
        runningSubjectID: "interview-a",
        learningTimerIsRunning: true,
        mutationInFlight: false
    ))
}
