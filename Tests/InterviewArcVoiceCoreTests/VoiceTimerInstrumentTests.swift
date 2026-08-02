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

@Test func timerInstrumentDistinguishesCareerFocusFromPracticeResults() throws {
    let focus = try JSONDecoder().decode(
        VoiceTimerActivity.self,
        from: Data(
            #"{"id":"focus-1","questionId":null,"type":"focus_block","title":"Job applications","url":null,"allocatedSeconds":3600,"timer":null,"starred":false,"activityClass":"focus_block","requiresOutcome":false}"#
                .utf8
        )
    )
    let practice = try JSONDecoder().decode(
        VoiceTimerActivity.self,
        from: Data(
            #"{"id":"practice-1","questionId":"course-schedule","type":"leetcode","title":"Course Schedule","url":null,"allocatedSeconds":2400,"timer":null,"starred":false,"activityClass":"practice","requiresOutcome":true}"#
                .utf8
        )
    )

    #expect(focus.isFocusBlock)
    #expect(!focus.needsOutcome)
    #expect(!practice.isFocusBlock)
    #expect(practice.needsOutcome)
}

@Test func sessionFinishBlocksOnlyStartedPracticeWithoutAnOutcome() throws {
    let response = try JSONDecoder().decode(
        VoiceContextResponse.self,
        from: Data(
            #"""
            {
              "protocolVersion": 2,
              "date": "2026-07-27",
              "focusedActivity": null,
              "specialist": null,
              "message": null,
              "timerInstrument": {
                "serverNow": 10000,
                "session": null,
                "activity": null,
                "activities": [
                  {
                    "id": "focus-started",
                    "questionId": null,
                    "type": "focus_block",
                    "title": "Job applications",
                    "url": null,
                    "allocatedSeconds": 3600,
                    "timer": {
                      "accumulatedSeconds": 10,
                      "startedAt": 1000,
                      "runningSince": null,
                      "completed": false,
                      "completedAt": null,
                      "revision": 1
                    },
                    "starred": false,
                    "activityClass": "focus_block",
                    "requiresOutcome": false
                  },
                  {
                    "id": "practice-needs-result",
                    "questionId": "course-schedule",
                    "type": "leetcode",
                    "title": "Course Schedule",
                    "url": null,
                    "allocatedSeconds": 2400,
                    "timer": {
                      "accumulatedSeconds": 10,
                      "startedAt": 1000,
                      "runningSince": null,
                      "completed": false,
                      "completedAt": null,
                      "revision": 1
                    },
                    "starred": false,
                    "activityClass": "practice",
                    "requiresOutcome": true
                  },
                  {
                    "id": "practice-not-started",
                    "questionId": "number-of-islands",
                    "type": "leetcode",
                    "title": "Number of Islands",
                    "url": null,
                    "allocatedSeconds": 2400,
                    "timer": null,
                    "starred": false,
                    "activityClass": "practice",
                    "requiresOutcome": true
                  },
                  {
                    "id": "practice-with-result",
                    "questionId": "two-sum",
                    "type": "leetcode",
                    "title": "Two Sum",
                    "url": null,
                    "allocatedSeconds": 2400,
                    "timer": {
                      "accumulatedSeconds": 10,
                      "startedAt": 1000,
                      "runningSince": null,
                      "completed": false,
                      "completedAt": null,
                      "revision": 1
                    },
                    "starred": false,
                    "activityClass": "practice",
                    "requiresOutcome": true,
                    "outcome": "solved"
                  }
                ]
              }
            }
            """#.utf8
        )
    )

    #expect(response.timerInstrument?.sessionFinishBlockers.map(\.id) == ["practice-needs-result"])
    #expect(VoiceLiveConnectionPolicy.heartbeatIntervalSeconds == 20)
}

@Test func expandedTimerUsesOneTransparentHostForTwoSeparatedSurfaces() {
    #expect(FloatingWidgetWindowPolicy.expandedWidth > FloatingWidgetWindowPolicy.collapsedWidth)
    #expect(FloatingWidgetWindowPolicy.recordingWidth > FloatingWidgetWindowPolicy.collapsedWidth)
    #expect(FloatingWidgetWindowPolicy.recordingWidth < FloatingWidgetWindowPolicy.expandedWidth)
    #expect(FloatingWidgetWindowPolicy.recordingWaveformSampleCount == 64)
    #expect(
        FloatingWidgetWindowPolicy.recordingWaveformBarWidth(
            availableWidth: 180
        ) == 1
    )
    #expect(
        FloatingWidgetWindowPolicy.recordingWaveformBarSpacing(
            availableWidth: 190
        ) == 2
    )
    #expect(FloatingWidgetMotionPolicy.durationSeconds == 0.30)
    #expect(FloatingWidgetWindowPolicy.playbackWidth > FloatingWidgetWindowPolicy.collapsedWidth)
    #expect(FloatingWidgetWindowPolicy.playbackWidth < FloatingWidgetWindowPolicy.expandedWidth)
    #expect(FloatingWidgetWindowPolicy.timerGap == 10)
    #expect(FloatingWidgetWindowPolicy.expandedHostHeight > FloatingWidgetWindowPolicy.hostHeight)
    #expect(
        FloatingWidgetWindowPolicy.expandedDrawerHostHeight
            > FloatingWidgetWindowPolicy.expandedHostHeight
    )
    #expect(FloatingWidgetWindowPolicy.recorderIsBottomSurface)
    #expect(FloatingWidgetWindowPolicy.expandsUpward)
    #expect(FloatingWidgetWindowPolicy.timerDisclosureAvailableDuringPlayback)
    #expect(FloatingWidgetWindowPolicy.timerPanelContentAnchorsToCapsule)
}

@Test func recoveryPopoverPlaybackWaitsUntilItsAnchorHasDisappeared() {
    #expect(
        FloatingWidgetRecoveryPolicy.timing(for: .playRecording)
            == .afterPopoverDismissal
    )
    #expect(
        FloatingWidgetRecoveryPolicy.timing(for: .recordAgain)
            == .afterPopoverDismissal
    )
    #expect(
        FloatingWidgetRecoveryPolicy.timing(for: .useRecoveryTranscript)
            == .afterPopoverDismissal
    )
    #expect(FloatingWidgetRecoveryPolicy.dismissalSettleMilliseconds >= 240)
    #expect(
        FloatingWidgetRecoveryPolicy.timing(for: .saveRecording)
            == .immediate
    )
}

@Test func recordingUsesOneFocusedDisclosureStateFromEveryStartingSurface() {
    let openTimer = FloatingWidgetDisclosureState(
        timerPanelExpanded: true,
        finishingActivityID: "activity-1",
        activityPickerExpanded: false
    )
    #expect(
        FloatingWidgetWindowPolicy.disclosureStateWhenRecordingStarts(
            current: openTimer
        ) == FloatingWidgetDisclosureState(
            timerPanelExpanded: false,
            finishingActivityID: nil,
            activityPickerExpanded: false
        )
    )

    let closedTimer = FloatingWidgetDisclosureState(
        timerPanelExpanded: false,
        finishingActivityID: nil,
        activityPickerExpanded: false
    )
    #expect(
        FloatingWidgetWindowPolicy.disclosureStateWhenRecordingStarts(
            current: closedTimer
        ) == closedTimer
    )

    let openPicker = FloatingWidgetDisclosureState(
        timerPanelExpanded: true,
        finishingActivityID: nil,
        activityPickerExpanded: true
    )
    #expect(
        FloatingWidgetWindowPolicy.disclosureStateWhenRecordingStarts(
            current: openPicker
        ) == closedTimer
    )
}

@Test func connectedSessionWithoutRunningActivityUsesGeneralFallbackPresentation() {
    let policy = CompactVoicePresentationPolicy()

    let runningSession = policy.presentation(
        linkEnabled: true,
        activeActivityTitle: nil,
        hasOpenSession: true,
        sessionIsRunning: true
    )
    #expect(runningSession.state == .connectedIdle)
    #expect(runningSession.title == "General dictation · no activity running")
    #expect(runningSession.accessibilityLabel.contains("Recording uses general dictation"))

    let pausedSession = policy.presentation(
        linkEnabled: true,
        activeActivityTitle: nil,
        hasOpenSession: true,
        sessionIsRunning: false
    )
    #expect(pausedSession.state == .connectedIdle)
    #expect(pausedSession.title == "General dictation · session paused")
}

@Test func activeActivityAndLinkOffRemainDistinctFromConnectedFallback() {
    let policy = CompactVoicePresentationPolicy()

    let linked = policy.presentation(
        linkEnabled: true,
        activeActivityTitle: "Course Schedule",
        hasOpenSession: true,
        sessionIsRunning: true
    )
    #expect(linked.state == .linked)
    #expect(linked.title == "Course Schedule")

    let off = policy.presentation(
        linkEnabled: false,
        activeActivityTitle: "Course Schedule",
        hasOpenSession: true,
        sessionIsRunning: true
    )
    #expect(off.state == .off)
    #expect(off.title == "General dictation")
}

@Test func noSessionAndNoActivityUsesWaitingGeneralDictation() {
    let presentation = CompactVoicePresentationPolicy().presentation(
        linkEnabled: true,
        activeActivityTitle: nil,
        hasOpenSession: false,
        sessionIsRunning: false
    )

    #expect(presentation.state == .waiting)
    #expect(presentation.title == "No focused activity · general dictation")
}
