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

public enum FloatingWidgetWindowPolicy {
    public static let hostIsOpaque = false
    public static let usesNativeWindowShadow = false
    public static let collapsedWidth: CGFloat = 250
    public static let recordingWidth: CGFloat = 340
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

public enum FloatingWidgetGeometryPolicy {
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
