import XCTest
@testable import InterviewArcVoiceCore

final class MicrophoneSignalPolicyTests: XCTestCase {
    private let policy = MicrophoneSignalPolicy(
        warningDelaySeconds: 2.5,
        signalThresholdDecibels: -65
    )

    func testWarmsUpBeforeWarningDelay() {
        XCTAssertEqual(
            policy.health(elapsedSeconds: 2.49, peakPowerDecibels: -160),
            .warmingUp
        )
    }

    func testReportsAbsentSignalAfterWarningDelay() {
        XCTAssertEqual(
            policy.health(elapsedSeconds: 2.5, peakPowerDecibels: -160),
            .absent
        )
    }

    func testAnyPlausibleSignalKeepsCaptureHealthy() {
        XCTAssertEqual(
            policy.health(elapsedSeconds: 30, peakPowerDecibels: -54),
            .detected
        )
    }

    func testThresholdBoundaryCountsAsSignal() {
        XCTAssertEqual(
            policy.health(elapsedSeconds: 3, peakPowerDecibels: -65),
            .detected
        )
    }

    func testSilentStreamGetsOneControlledRestart() {
        let recovery = MicrophoneStreamRecoveryPolicy()
        XCTAssertTrue(recovery.shouldRestart(health: .absent, completedRestarts: 0))
        XCTAssertFalse(recovery.shouldRestart(health: .absent, completedRestarts: 1))
        XCTAssertFalse(recovery.shouldRestart(health: .detected, completedRestarts: 0))
    }
}
