import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func runningTimerCombinesServerIntervalWithLocalContinuation() {
    let timer = VoiceTimerState(
        accumulatedSeconds: 20,
        startedAt: 1_000,
        runningSince: 8_000,
        completed: false,
        completedAt: nil,
        revision: 2
    )
    let receivedAt = Date(timeIntervalSince1970: 100)

    #expect(
        timer.elapsedSeconds(
            serverNow: 18_000,
            receivedAt: receivedAt,
            now: receivedAt.addingTimeInterval(3.8)
        ) == 33
    )
}

@Test func pausedTimerDoesNotAdvanceAfterTheSnapshot() {
    let timer = VoiceTimerState(
        accumulatedSeconds: 91,
        startedAt: 1_000,
        runningSince: nil,
        completed: false,
        completedAt: nil,
        revision: 4
    )
    let receivedAt = Date(timeIntervalSince1970: 100)

    #expect(
        timer.elapsedSeconds(
            serverNow: 18_000,
            receivedAt: receivedAt,
            now: receivedAt.addingTimeInterval(300)
        ) == 91
    )
}

@Test func expandedTimerUsesOneTransparentHostForTwoSeparatedSurfaces() {
    #expect(FloatingWidgetWindowPolicy.expandedWidth > FloatingWidgetWindowPolicy.collapsedWidth)
    #expect(FloatingWidgetWindowPolicy.timerGap == 10)
    #expect(FloatingWidgetWindowPolicy.expandedHostHeight > FloatingWidgetWindowPolicy.hostHeight)
    #expect(
        FloatingWidgetWindowPolicy.expandedDrawerHostHeight
            > FloatingWidgetWindowPolicy.expandedHostHeight
    )
}
