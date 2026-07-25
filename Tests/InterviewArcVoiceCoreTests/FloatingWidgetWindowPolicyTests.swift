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
