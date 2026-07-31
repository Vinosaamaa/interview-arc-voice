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
    #expect(FloatingWidgetCompactTimerLayoutPolicy.activityClockWidth == 36)
    #expect(FloatingWidgetCompactTimerLayoutPolicy.sessionClockWidth == 42)
    #expect(FloatingWidgetCompactTimerLayoutPolicy.maximumClusterWidth <= 84)
    #expect(FloatingWidgetCompactTimerLayoutPolicy.minimumTitleWidth >= 58)
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

@Test func floatingMemoShelfKeepsOnlyPrimaryActionsBesideTheTitle() {
    #expect(
        FloatingWidgetMemoActionPolicy.actions(
            shelf: .primary,
            hasTranscript: true,
            hasAudio: true,
            canPlanToday: true
        ) == [.play, .insert, .more]
    )
    #expect(
        FloatingWidgetMemoActionPolicy.actions(
            shelf: .secondary,
            hasTranscript: true,
            hasAudio: true,
            canPlanToday: true
        ) == [.back, .copy, .save, .planToday]
    )
}

@Test func floatingMemoShelfAvoidsAnEmptyMoreMode() {
    #expect(
        FloatingWidgetMemoActionPolicy.actions(
            shelf: .primary,
            hasTranscript: false,
            hasAudio: false,
            canPlanToday: true
        ) == [.planToday]
    )
    #expect(
        FloatingWidgetMemoActionPolicy.actions(
            shelf: .primary,
            hasTranscript: false,
            hasAudio: false,
            canPlanToday: false
        ).isEmpty
    )
}

@Test func activeTimerCapsuleStaysReadableInsteadOfShowingMemoActions() {
    #expect(!FloatingWidgetCompactTimerLayoutPolicy.showsPreviousMemoActionsWhenExpanded)
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
