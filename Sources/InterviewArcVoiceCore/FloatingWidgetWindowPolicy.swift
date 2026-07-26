import Foundation

public struct FloatingWidgetDisclosureState: Equatable, Sendable {
    public let timerPanelExpanded: Bool
    public let finishingActivityID: String?
    public let activityPickerExpanded: Bool

    public init(
        timerPanelExpanded: Bool,
        finishingActivityID: String?,
        activityPickerExpanded: Bool
    ) {
        self.timerPanelExpanded = timerPanelExpanded
        self.finishingActivityID = finishingActivityID
        self.activityPickerExpanded = activityPickerExpanded
    }
}

public enum FloatingWidgetContentAlignment: Equatable, Sendable {
    case bottomTrailing
}

public enum FloatingWidgetWindowPolicy {
    public static let hostIsOpaque = false
    public static let usesNativeWindowShadow = false
    public static let collapsedWidth: CGFloat = 250
    public static let recordingWidth: CGFloat = 340
    public static let recordingWaveformSampleCount = 32
    public static let recordingWaveformBarSpacing: CGFloat = 1.5
    public static let playbackWidth: CGFloat = 410
    public static let expandedWidth: CGFloat = 430
    public static let capsuleHeight: CGFloat = 40
    public static let hostHeight: CGFloat = 56
    public static let timerGap: CGFloat = 10
    public static let expandedHostHeight: CGFloat = 300
    public static let expandedDrawerHostHeight: CGFloat = 378
    public static let recorderIsBottomSurface = true
    public static let expandsUpward = true
    public static let timerDisclosureAvailableDuringPlayback = true
    public static let timerPanelContentAnchorsToCapsule = true
    public static let contentFillsAnimatedHost = true
    public static let contentAlignment: FloatingWidgetContentAlignment = .bottomTrailing

    public static func disclosureStateWhenRecordingStarts(
        current: FloatingWidgetDisclosureState
    ) -> FloatingWidgetDisclosureState {
        _ = current
        return FloatingWidgetDisclosureState(
            timerPanelExpanded: false,
            finishingActivityID: nil,
            activityPickerExpanded: false
        )
    }
}

public enum FloatingWidgetCompactTimerLayoutPolicy {
    public static let minimumTitleWidth: CGFloat = 58
    public static let titleFillsAvailableHeight = true
    public static let activityClockWidth: CGFloat = 36
    public static let sessionClockWidth: CGFloat = 42
    public static let clusterSpacing: CGFloat = 2
    public static let dividerWidth: CGFloat = 1
    public static let maximumClusterWidth =
        activityClockWidth
        + sessionClockWidth
        + dividerWidth
        + (clusterSpacing * 2)
}

public enum FloatingWidgetGeometryPolicy {
    public static func visibleCapsuleWidth(hostWidth: CGFloat) -> CGFloat {
        max(0, hostWidth)
    }

    public static func anchoredFrame(
        currentFrame: CGRect,
        targetSize: CGSize
    ) -> CGRect {
        CGRect(
            x: currentFrame.maxX - targetSize.width,
            y: currentFrame.minY,
            width: targetSize.width,
            height: targetSize.height
        )
    }
}
