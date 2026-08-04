import Testing
import Foundation
@testable import InterviewArcVoiceCore

@Test func floatingWidgetHostNeverPaintsOrShadowsItsRectangularWindow() {
    #expect(!FloatingWidgetWindowPolicy.hostIsOpaque)
    #expect(!FloatingWidgetWindowPolicy.usesNativeWindowShadow)
}

@Test func floatingWidgetLeavesTransparentBreathingRoomAroundItsCapsule() {
    #expect(FloatingWidgetWindowPolicy.capsuleHeight == 40)
    #expect(FloatingWidgetWindowPolicy.hostHeight == 56)
    #expect(FloatingWidgetWindowPolicy.hostHeight > FloatingWidgetWindowPolicy.capsuleHeight)
}

@Test func floatingWidgetResizePreservesBottomRightAnchor() {
    let current = CGRect(x: 900, y: 120, width: 250, height: 56)
    let resized = FloatingWidgetGeometryPolicy.anchoredFrame(
        currentFrame: current,
        targetSize: CGSize(width: 430, height: 300)
    )

    #expect(resized.maxX == current.maxX)
    #expect(resized.minY == current.minY)
    #expect(resized.size == CGSize(width: 430, height: 300))
}

@Test func recoveryFallbackDoesNotCancelItselfBeforeExecutingItsAction() {
    #expect(
        FloatingWidgetRecoveryPolicy.shouldCancelFallback(
            for: .popoverDidClose
        )
    )
    #expect(
        !FloatingWidgetRecoveryPolicy.shouldCancelFallback(
            for: .fallbackTimer
        )
    )
}

@Test func compactTimerClusterReservesReadableTitleSpace() {
    #expect(FloatingWidgetCompactTimerLayoutPolicy.activityClockWidth == 52)
    #expect(FloatingWidgetCompactTimerLayoutPolicy.sessionClockWidth == 31)
    #expect(FloatingWidgetCompactTimerLayoutPolicy.expandedSessionClockWidth == 42)
    #expect(FloatingWidgetCompactTimerLayoutPolicy.maximumClusterWidth <= 100)
    #expect(FloatingWidgetCompactTimerLayoutPolicy.minimumTitleWidth >= 58)
    #expect(
        FloatingWidgetCompactTimerLayoutPolicy.sessionClockWidth(for: "13:55")
            == 31
    )
    #expect(
        FloatingWidgetCompactTimerLayoutPolicy.sessionClockWidth(for: "+100:00")
            == 42
    )
}

@Test func activityClockAlwaysShowsHoursMinutesAndSeconds() {
    #expect(CompactTimerTextPolicy.activityElapsed(seconds: 3_845) == "01:04:05")
    #expect(CompactTimerTextPolicy.activityElapsed(seconds: 65) == "00:01:05")
}

@Test func sessionClockOmitsSecondsAndKeepsOvertimeVisible() {
    #expect(CompactTimerTextPolicy.sessionRemaining(seconds: 50_148) == "13:55")
    #expect(CompactTimerTextPolicy.sessionRemaining(seconds: -3_661) == "+01:01")
}

@Test func upperSurfaceMotionUsesOneClippedSurfaceAndRetainsOnlyARealCollapse() {
    #expect(
        FloatingWidgetUpperSurfaceTransitionPolicy.style
            == .singleSurfaceClippedResize
    )
    #expect(
        FloatingWidgetUpperSurfaceTransitionPolicy.renderedSurface(
            desired: .focus,
            retained: .planToday
        ) == .focus
    )
    #expect(
        FloatingWidgetUpperSurfaceTransitionPolicy.shouldRetainOutgoing(
            from: .focus,
            to: nil,
            reduceMotion: false
        )
    )
    #expect(
        !FloatingWidgetUpperSurfaceTransitionPolicy.shouldRetainOutgoing(
            from: .planToday,
            to: .focus,
            reduceMotion: false
        )
    )
    #expect(
        !FloatingWidgetUpperSurfaceTransitionPolicy.shouldRetainOutgoing(
            from: .focus,
            to: nil,
            reduceMotion: true
        )
    )
    #expect(
        FloatingWidgetUpperSurfaceTransitionPolicy.collapseRetentionSeconds
            > FloatingWidgetMotionPolicy.durationSeconds
    )
}

@Test func floatingPanelResizeProducesVisibleIntermediateFrames() {
    let start = CGRect(x: 900, y: 120, width: 560, height: 648)
    let end = CGRect(x: 1_210, y: 120, width: 250, height: 56)
    let quarter = FloatingWidgetFrameInterpolationPolicy.frame(
        from: start,
        to: end,
        progress: 0.25
    )
    let middle = FloatingWidgetFrameInterpolationPolicy.frame(
        from: start,
        to: end,
        progress: 0.5
    )
    let threeQuarter = FloatingWidgetFrameInterpolationPolicy.frame(
        from: start,
        to: end,
        progress: 0.75
    )

    #expect(quarter.width < start.width && quarter.width > middle.width)
    #expect(middle.width < quarter.width && middle.width > threeQuarter.width)
    #expect(threeQuarter.width < middle.width && threeQuarter.width > end.width)
    #expect(quarter.height < start.height && quarter.height > middle.height)
    #expect(middle.maxX == start.maxX)
    #expect(middle.minY == start.minY)
}

@Test func everyWidgetDirectionUsesNativeWindowSmoothResize() {
    #expect(
        FloatingWidgetMotionPolicy.backend
            == .nativeWindowSmoothResize
    )
    #expect(FloatingWidgetMotionPolicy.durationSeconds == 0.30)
    #expect(
        FloatingWidgetMotionPolicy.deferredWorkDelaySeconds
            > FloatingWidgetMotionPolicy.durationSeconds
    )
}

@Test func upperSurfaceAndRecordingChangesAreAtomicPresentationTransitions() {
    let focus = FloatingWidgetPresentationTransitionPolicy.showFocus(
        from: .compact
    )
    let planner = FloatingWidgetPresentationTransitionPolicy.showPlanner(
        from: focus
    )
    #expect(!planner.timerPanelExpanded)
    #expect(planner.plannerPresented)
    #expect(!planner.dynamicRecordingInterfaceActive)

    #expect(
        FloatingWidgetPresentationTransitionPolicy.showFocus(from: planner)
            == focus
    )
    let recording =
        FloatingWidgetPresentationTransitionPolicy.beginRecording(from: focus)
    #expect(!recording.timerPanelExpanded)
    #expect(!recording.plannerPresented)
    #expect(recording.dynamicRecordingInterfaceActive)

    let invalidPlannerAndFocusRequest =
        FloatingWidgetPresentationTransitionPolicy.settingPlannerPresented(
            true,
            from: focus
        )
    #expect(invalidPlannerAndFocusRequest.plannerPresented)
    #expect(!invalidPlannerAndFocusRequest.timerPanelExpanded)
}

@Test func floatingPanelResizeInterpolationKeepsExactEndpoints() {
    let start = CGRect(x: 900, y: 120, width: 430, height: 340)
    let end = CGRect(x: 1_080, y: 120, width: 250, height: 56)

    #expect(
        FloatingWidgetFrameInterpolationPolicy.frame(
            from: start,
            to: end,
            progress: 0
        ) == start
    )
    #expect(
        FloatingWidgetFrameInterpolationPolicy.frame(
            from: start,
            to: end,
            progress: 1
        ) == end
    )
}

@Test func planToFocusMakesTheVisibleSurfaceFollowEveryShrinkingHostFrame() {
    #expect(
        FloatingWidgetUpperSurfaceTransitionPolicy.visibleWidth(
            for: .focus,
            hostWidth: FloatingWidgetWindowPolicy.plannerWidth
        ) == FloatingWidgetWindowPolicy.plannerWidth
    )
    #expect(
        FloatingWidgetUpperSurfaceTransitionPolicy.visibleWidth(
            for: .focus,
            hostWidth: 500
        ) == 500
    )
    #expect(
        FloatingWidgetUpperSurfaceTransitionPolicy.visibleWidth(
            for: .focus,
            hostWidth: FloatingWidgetWindowPolicy.expandedWidth
        ) == FloatingWidgetWindowPolicy.expandedWidth
    )
}

@Test func compactToFocusKeepsTheAcceptedClippedRevealGeometry() {
    #expect(
        FloatingWidgetUpperSurfaceTransitionPolicy.visibleWidth(
            for: .focus,
            hostWidth: FloatingWidgetWindowPolicy.collapsedWidth
        ) == FloatingWidgetWindowPolicy.expandedWidth
    )
    #expect(
        FloatingWidgetUpperSurfaceTransitionPolicy.visibleWidth(
            for: .planToday,
            hostWidth: FloatingWidgetWindowPolicy.expandedWidth
        ) == FloatingWidgetWindowPolicy.plannerWidth
    )
}

@Test func coverageNoticeNeverReplacesAuthoritativeTimerContent() {
    #expect(FloatingWidgetCoverageNoticePolicy.showsInlineNotice(
        noticePresented: true,
        hasTimerInstrument: false,
        isBusy: false
    ))
    #expect(!FloatingWidgetCoverageNoticePolicy.showsInlineNotice(
        noticePresented: true,
        hasTimerInstrument: true,
        isBusy: false
    ))
    #expect(!FloatingWidgetCoverageNoticePolicy.showsInlineNotice(
        noticePresented: true,
        hasTimerInstrument: false,
        isBusy: true
    ))
}

@Test func animatedHostOwnsGeometryWhileSwiftUIStaysBottomTrailing() {
    #expect(FloatingWidgetWindowPolicy.contentFillsAnimatedHost)
    #expect(FloatingWidgetWindowPolicy.contentAlignment == .bottomTrailing)
}

@Test func visibleCapsuleTracksEveryIntermediateHostWidth() {
    #expect(FloatingWidgetGeometryPolicy.visibleCapsuleWidth(hostWidth: 250) == 250)
    #expect(FloatingWidgetGeometryPolicy.visibleCapsuleWidth(hostWidth: 314) == 314)
    #expect(FloatingWidgetGeometryPolicy.visibleCapsuleWidth(hostWidth: 430) == 430)
}

@Test func compactTitleUsesTheFullRowHeightForVerticalCentering() {
    #expect(FloatingWidgetCompactTimerLayoutPolicy.titleFillsAvailableHeight)
}

@Test func restingFloatingMemoShelfKeepsThreeStablePrimaryActions() {
    #expect(
        FloatingWidgetMemoActionPolicy.actions(
            for: .compact
        ) == [.play, .insert, .planToday]
    )
}

@Test func expandedFloatingMemoShelfAddsCopyAndSaveWithoutReorderingPrimaryActions() {
    #expect(
        FloatingWidgetMemoActionPolicy.actions(
            for: .expanded
        ) == [.play, .insert, .copy, .save, .planToday]
    )
}

@Test func floatingMemoShelfAvailabilityDoesNotChangeItsGeometry() {
    #expect(
        !FloatingWidgetMemoActionPolicy.isEnabled(
            .play,
            hasTranscript: false,
            hasAudio: false,
            canPlanToday: true
        )
    )
    #expect(
        !FloatingWidgetMemoActionPolicy.isEnabled(
            .insert,
            hasTranscript: false,
            hasAudio: true,
            canPlanToday: true
        )
    )
    #expect(
        FloatingWidgetMemoActionPolicy.isEnabled(
            .copy,
            hasTranscript: true,
            hasAudio: false,
            canPlanToday: true
        )
    )
    #expect(
        FloatingWidgetMemoActionPolicy.isEnabled(
            .save,
            hasTranscript: false,
            hasAudio: true,
            canPlanToday: true
        )
    )
    #expect(
        !FloatingWidgetMemoActionPolicy.isEnabled(
            .planToday,
            hasTranscript: true,
            hasAudio: true,
            canPlanToday: false
        )
    )
}

@Test func memoShelfRevealsExpandedActionsOnlyAfterTheCapsuleHasUsableWidth() {
    #expect(
        FloatingWidgetMemoActionLayoutPolicy.presentation(
            capsuleWidth: FloatingWidgetWindowPolicy.collapsedWidth
        ) == .compact
    )
    #expect(
        FloatingWidgetMemoActionLayoutPolicy.presentation(
            capsuleWidth:
                FloatingWidgetMemoActionLayoutPolicy.expandedRevealWidth - 1
        ) == .compact
    )
    #expect(
        FloatingWidgetMemoActionLayoutPolicy.presentation(
            capsuleWidth:
                FloatingWidgetMemoActionLayoutPolicy.expandedRevealWidth
        ) == .expanded
    )
}

@Test func floatingWidgetUsesExplicitDragSurfacesSoControlsReceiveClicks() {
    #expect(!FloatingWidgetWindowPolicy.usesNativeBackgroundDrag(for: .standard))
    #expect(!FloatingWidgetWindowPolicy.usesNativeBackgroundDrag(for: .mini))
    #expect(MiniWidgetPointerPolicy.dragThreshold == 5)
}

@Test func floatingWidgetClipsDisclosuresAtTheRecorderBoundary() {
    #expect(
        FloatingWidgetWindowPolicy.upperSurfaceViewportHeight(
            hostHeight: FloatingWidgetWindowPolicy.plannerHostHeight
        ) == 592
    )
    #expect(
        FloatingWidgetWindowPolicy.upperSurfaceContentHeight(
            hostHeight: FloatingWidgetWindowPolicy.plannerHostHeight
        ) == 582
    )
    #expect(
        FloatingWidgetWindowPolicy.upperSurfaceViewportHeight(
            hostHeight: FloatingWidgetWindowPolicy.hostHeight
        ) == 0
    )
}

@Test func plannerSelectionTrayMakesOverflowExplicit() {
    #expect(PlannerSelectionTrayPolicy.hiddenCount(selectionCount: 2) == 0)
    #expect(PlannerSelectionTrayPolicy.hiddenCount(selectionCount: 11) == 8)
    #expect(PlannerSelectionTrayPolicy.expandedRowCount(selectionCount: 6) == 2)
    #expect(PlannerSelectionTrayPolicy.expandedRowCount(selectionCount: 16) == 4)
    #expect(PlannerSelectionTrayPolicy.expandedRowCount(selectionCount: 24) == 4)
    #expect(
        PlannerSelectionTrayPolicy.expandedRailHeight(selectionCount: 6)
            < PlannerSelectionTrayPolicy.expandedRailHeight(selectionCount: 16)
    )
    #expect(!PlannerSelectionTrayPolicy.expandedContentScrolls(selectionCount: 16))
    #expect(PlannerSelectionTrayPolicy.expandedContentScrolls(selectionCount: 17))
}

@Test func floatingMemoShelfKeepsStableSlotsWhenMemoContentIsMissing() {
    #expect(
        FloatingWidgetMemoActionPolicy.actions(
            for: .compact
        ).count == 3
    )
    #expect(
        FloatingWidgetMemoActionPolicy.actions(
            for: .expanded
        ).count == 5
    )
}

@Test func activeTimerCapsuleStaysReadableInsteadOfShowingMemoActions() {
    #expect(FloatingWidgetCompactTimerLayoutPolicy.showsPreviousMemoActionsWhenExpanded)
}

@Test func recentTranscriptCardKeepsOneStableReadableGeometry() {
    #expect(RecentTranscriptCardLayoutPolicy.cardHeight >= 180)
    #expect(RecentTranscriptCardLayoutPolicy.previewHeight >= 80)
    #expect(RecentTranscriptCardLayoutPolicy.footerHeight >= 34)
    #expect(RecentTranscriptCardLayoutPolicy.metadataLineCount == 2)
    #expect(RecentTranscriptCardLayoutPolicy.footerActionSlotCount == 5)
    #expect(
        RecentTranscriptCardLayoutPolicy.cardHeight(
            transcriptWordCount: 6,
            hasAudio: true
        ) == RecentTranscriptCardLayoutPolicy.cardHeight(
            transcriptWordCount: 302,
            hasAudio: false
        )
    )
}

@Test func voiceMenuShrinksToContentButCapsTallStatesToTheVisibleScreen() {
    #expect(
        VoiceMenuWindowLayoutPolicy.maximumHeight(visibleScreenHeight: 900)
            == VoiceMenuWindowLayoutPolicy.preferredMaximumHeight
    )
    #expect(
        VoiceMenuWindowLayoutPolicy.maximumHeight(visibleScreenHeight: 600)
            == 552
    )
    #expect(
        VoiceMenuWindowLayoutPolicy.maximumHeight(visibleScreenHeight: 320)
            == VoiceMenuWindowLayoutPolicy.minimumMaximumHeight
    )

    #expect(
        VoiceMenuWindowLayoutPolicy.presentation(
            measuredContentHeight: 0,
            maximumHeight: 552
        ) == .intrinsic
    )
    #expect(
        VoiceMenuWindowLayoutPolicy.presentation(
            measuredContentHeight: 520,
            maximumHeight: 552
        ) == .intrinsic
    )
    #expect(
        VoiceMenuWindowLayoutPolicy.presentation(
            measuredContentHeight: 680,
            maximumHeight: 552
        ) == .scrolling(height: 552)
    )
}
