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

public enum FloatingWidgetRecoveryActionTiming: Equatable, Sendable {
    case immediate
    case afterPopoverDismissal
}

public enum FloatingWidgetRecoveryCompletionTrigger: Equatable, Sendable {
    case popoverDidClose
    case fallbackTimer
}

public enum FloatingWidgetRecoveryPolicy {
    /// Safety fallback only. Normal recovery continues from AppKit's
    /// NSPopover.didCloseNotification, not from this delay.
    public static let dismissalSettleMilliseconds = 900

    public static func timing(
        for action: VoiceFailureAction
    ) -> FloatingWidgetRecoveryActionTiming {
        switch action {
        case .playRecording, .recordAgain:
            return .afterPopoverDismissal
        default:
            return .immediate
        }
    }

    public static func shouldCancelFallback(
        for trigger: FloatingWidgetRecoveryCompletionTrigger
    ) -> Bool {
        trigger == .popoverDidClose
    }
}

public enum FloatingWidgetWindowPolicy {
    public static let hostIsOpaque = false
    public static let usesNativeWindowShadow = false
    public static let usesNativeBackgroundDrag = false
    public static let collapsedWidth: CGFloat = 250
    public static let recordingWidth: CGFloat = 340
    public static let miniMicrophoneWidth: CGFloat = 48
    public static let miniMicrophoneSurfaceDiameter: CGFloat = 40
    public static let miniTimerCellWidth: CGFloat = 60
    public static let miniTimerDividerWidth: CGFloat = 9
    public static let miniTimerWidth: CGFloat = 108
    public static let miniDualTimerWidth: CGFloat = 177
    public static let recordingWaveformSampleCount = 64
    public static let recordingWaveformBarWidth: CGFloat = 1
    public static let playbackWidth: CGFloat = 410
    public static let expandedWidth: CGFloat = 430
    public static let plannerWidth: CGFloat = 560
    public static let capsuleHeight: CGFloat = 40
    public static let hostHeight: CGFloat = 56
    public static let timerGap: CGFloat = 10
    public static let expandedHostHeight: CGFloat = 340
    public static let expandedDrawerHostHeight: CGFloat = 418
    public static let plannerHostHeight: CGFloat = 648
    public static let recorderIsBottomSurface = true
    public static let expandsUpward = true
    public static let timerDisclosureAvailableDuringPlayback = true
    public static let timerPanelContentAnchorsToCapsule = true
    public static let contentFillsAnimatedHost = true
    public static let contentAlignment: FloatingWidgetContentAlignment = .bottomTrailing

    public static func recordingWaveformBarWidth(
        availableWidth: CGFloat
    ) -> CGFloat {
        _ = availableWidth
        return recordingWaveformBarWidth
    }

    public static func recordingWaveformBarSpacing(
        availableWidth: CGFloat
    ) -> CGFloat {
        guard recordingWaveformSampleCount > 1 else { return 0 }
        let marksWidth = CGFloat(recordingWaveformSampleCount) * recordingWaveformBarWidth
        return max(
            0,
            (availableWidth - marksWidth) / CGFloat(recordingWaveformSampleCount - 1)
        )
    }

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

public enum FloatingWidgetMotionPolicy {
    public static let durationSeconds: TimeInterval = 0.30
}

public enum MiniWidgetPointerPolicy {
    public static let dragThreshold: CGFloat = 5

    public static func isDrag(translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) >= dragThreshold
    }

    public static func screenTranslation(
        from start: CGPoint,
        to current: CGPoint
    ) -> CGSize {
        CGSize(
            width: current.x - start.x,
            height: current.y - start.y
        )
    }

    public static func translatedOrigin(
        startOrigin: CGPoint,
        startPointer: CGPoint,
        currentPointer: CGPoint
    ) -> CGPoint {
        let translation = screenTranslation(
            from: startPointer,
            to: currentPointer
        )
        return CGPoint(
            x: startOrigin.x + translation.width,
            y: startOrigin.y + translation.height
        )
    }

    public static func clampedOrigin(
        proposed: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: min(
                max(proposed.x, visibleFrame.minX),
                max(visibleFrame.minX, visibleFrame.maxX - panelSize.width)
            ),
            y: min(
                max(proposed.y, visibleFrame.minY),
                max(visibleFrame.minY, visibleFrame.maxY - panelSize.height)
            )
        )
    }
}

public enum FloatingWidgetCompactTimerLayoutPolicy {
    public static let showsPreviousMemoActionsWhenExpanded = false
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

public enum FloatingWidgetMemoAction: Equatable, Hashable, Sendable {
    case play
    case insert
    case copy
    case save
    case planToday
}

public enum FloatingWidgetMemoActionPolicy {
    public static func actions(
        hasTranscript: Bool,
        hasAudio: Bool,
        canPlanToday: Bool
    ) -> [FloatingWidgetMemoAction] {
        let hasMemo = hasTranscript || hasAudio
        guard hasMemo else {
            return canPlanToday ? [.planToday] : []
        }

        var actions: [FloatingWidgetMemoAction] = []
        if hasAudio { actions.append(.play) }
        if hasTranscript { actions.append(.insert) }
        if hasTranscript { actions.append(.copy) }
        if hasAudio { actions.append(.save) }
        if canPlanToday { actions.append(.planToday) }
        return actions
    }
}

public enum RecentTranscriptCardLayoutPolicy {
    public static let cardHeight: CGFloat = 184
    public static let previewHeight: CGFloat = 84
    public static let footerHeight: CGFloat = 36
    public static let metadataWidth: CGFloat = 62
    public static let metadataLineCount = 2
    public static let footerActionSlotCount = 5

    public static func cardHeight(
        transcriptWordCount: Int,
        hasAudio: Bool
    ) -> CGFloat {
        _ = transcriptWordCount
        _ = hasAudio
        return cardHeight
    }
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
