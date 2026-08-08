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

    func testSilentPrimaryAndFallbackStreamsGetTwoControlledRestarts() {
        let recovery = MicrophoneStreamRecoveryPolicy()
        XCTAssertTrue(
            recovery.shouldRestart(
                health: .absent,
                completedRestarts: 0,
                captureBackendIsActive: true
            )
        )
        XCTAssertTrue(
            recovery.shouldRestart(
                health: .absent,
                completedRestarts: 1,
                captureBackendIsActive: true
            )
        )
        XCTAssertFalse(
            recovery.shouldRestart(
                health: .absent,
                completedRestarts: 2,
                captureBackendIsActive: true
            )
        )
        XCTAssertFalse(
            recovery.shouldRestart(
                health: .detected,
                completedRestarts: 0,
                captureBackendIsActive: true
            )
        )
        XCTAssertFalse(
            recovery.shouldRestart(
                health: .absent,
                completedRestarts: 0,
                captureBackendIsActive: false
            )
        )
    }

    func testHistoricalSpeechDoesNotMaskMidCaptureStreamLoss() {
        var monitor = MicrophoneStreamContinuityMonitor(
            dropoutDelaySeconds: 2.5,
            livenessThresholdDecibels: -100
        )

        monitor.observe(elapsedSeconds: 0, powerDecibels: -42)
        monitor.observe(elapsedSeconds: 3.5, powerDecibels: -38)
        XCTAssertEqual(monitor.health(elapsedSeconds: 4), .detected)

        monitor.observe(elapsedSeconds: 4, powerDecibels: -160)
        monitor.observe(elapsedSeconds: 5, powerDecibels: -160)
        monitor.observe(elapsedSeconds: 6, powerDecibels: -160)

        XCTAssertEqual(monitor.health(elapsedSeconds: 6), .absent)
    }

    func testRecentQuietLiveInputKeepsStreamHealthy() {
        var monitor = MicrophoneStreamContinuityMonitor(
            dropoutDelaySeconds: 2.5,
            livenessThresholdDecibels: -100
        )

        monitor.observe(elapsedSeconds: 0, powerDecibels: -90)
        monitor.observe(elapsedSeconds: 2, powerDecibels: -92)
        monitor.observe(elapsedSeconds: 4, powerDecibels: -88)

        XCTAssertEqual(monitor.health(elapsedSeconds: 5), .detected)
    }

    func testMeterFloorCannotBeClassifiedAsLiveInput() {
        XCTAssertLessThan(
            MicrophoneStreamContinuityMonitor.minimumMeterPowerDecibels,
            MicrophoneStreamContinuityMonitor.defaultLivenessThresholdDecibels
        )
    }
}
