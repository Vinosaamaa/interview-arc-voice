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
    public static let hostVerticalInset: CGFloat = 8
    public static let recorderIsBottomSurface = true
    public static let expandsUpward = true
    public static let timerDisclosureAvailableDuringPlayback = true
    public static let timerPanelContentAnchorsToCapsule = true
    public static let contentFillsAnimatedHost = true
    public static let contentAlignment: FloatingWidgetContentAlignment = .bottomTrailing

    public static func usesNativeBackgroundDrag(
        for mode: VoiceWidgetSizeMode
    ) -> Bool {
        // NSPanel's native background dragging treats large portions of a
        // borderless SwiftUI hosting view as window chrome. That steals the
        // first click from Buttons and TextFields. Both widget modes use an
        // explicit drag gesture on non-control surfaces instead.
        _ = mode
        return false
    }

    public static func upperSurfaceViewportHeight(
        hostHeight: CGFloat
    ) -> CGFloat {
        max(
            0,
            hostHeight - capsuleHeight - hostVerticalInset * 2
        )
    }

    public static func upperSurfaceContentHeight(
        hostHeight: CGFloat
    ) -> CGFloat {
        max(
            0,
            upperSurfaceViewportHeight(hostHeight: hostHeight) - timerGap
        )
    }

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

public enum PlannerSelectionTrayPolicy {
    public static let collapsedVisibleCount = 3
    public static let expandedColumnCount = 4
    public static let maximumExpandedRows = 4
    public static let chipHeight: CGFloat = 26
    public static let rowSpacing: CGFloat = 5
    public static let verticalPadding: CGFloat = 12

    public static func hiddenCount(selectionCount: Int) -> Int {
        max(0, selectionCount - collapsedVisibleCount)
    }

    public static func expandedRowCount(selectionCount: Int) -> Int {
        guard selectionCount > 0 else { return 1 }
        return min(
            maximumExpandedRows,
            Int(ceil(Double(selectionCount) / Double(expandedColumnCount)))
        )
    }

    public static func expandedRailHeight(selectionCount: Int) -> CGFloat {
        let rows = expandedRowCount(selectionCount: selectionCount)
        return CGFloat(rows) * chipHeight
            + CGFloat(max(0, rows - 1)) * rowSpacing
            + verticalPadding
    }

    public static func expandedContentScrolls(selectionCount: Int) -> Bool {
        selectionCount > expandedColumnCount * maximumExpandedRows
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
    public static let showsPreviousMemoActionsWhenExpanded = true
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

public enum FloatingWidgetMemoActionPresentation: Equatable, Sendable {
    case compact
    case expanded
}

public enum FloatingWidgetMemoActionLayoutPolicy {
    /// Five 22-point controls, the readable title floor, link state, trailing
    /// microphone, and the shared six-point rhythm fit without compression at
    /// this width. The live host width—not the destination model state—drives
    /// the reveal so Copy and Save never flash inside a still-narrow capsule.
    public static let expandedRevealWidth: CGFloat = 340

    public static func presentation(
        capsuleWidth: CGFloat
    ) -> FloatingWidgetMemoActionPresentation {
        capsuleWidth >= expandedRevealWidth ? .expanded : .compact
    }
}

public enum FloatingWidgetMemoActionPolicy {
    public static func actions(
        for presentation: FloatingWidgetMemoActionPresentation
    ) -> [FloatingWidgetMemoAction] {
        switch presentation {
        case .compact:
            return [.play, .insert, .planToday]
        case .expanded:
            return [.play, .insert, .copy, .save, .planToday]
        }
    }

    public static func isEnabled(
        _ action: FloatingWidgetMemoAction,
        hasTranscript: Bool,
        hasAudio: Bool,
        canPlanToday: Bool
    ) -> Bool {
        switch action {
        case .play, .save:
            return hasAudio
        case .insert, .copy:
            return hasTranscript
        case .planToday:
            return canPlanToday
        }
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

public enum VoiceMenuWindowLayoutPolicy {
    public enum Presentation: Equatable, Sendable {
        case intrinsic
        case scrolling(height: CGFloat)
    }

    public static let preferredMaximumHeight: CGFloat = 720
    public static let minimumMaximumHeight: CGFloat = 360
    public static let visibleScreenMargin: CGFloat = 48

    public static func maximumHeight(
        visibleScreenHeight: CGFloat
    ) -> CGFloat {
        min(
            preferredMaximumHeight,
            max(
                minimumMaximumHeight,
                visibleScreenHeight - visibleScreenMargin
            )
        )
    }

    public static func presentation(
        measuredContentHeight: CGFloat,
        maximumHeight: CGFloat
    ) -> Presentation {
        guard measuredContentHeight > maximumHeight else {
            return .intrinsic
        }
        return .scrolling(height: maximumHeight)
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
