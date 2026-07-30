import Foundation
import Testing
@testable import InterviewArcVoiceCore

struct VoiceWidgetSizeModeTests {
    @Test
    func defaultsToStandardWhenNoPreferenceExists() {
        let defaults = isolatedDefaults()

        #expect(VoiceWidgetSizeMode.load(from: defaults) == .standard)
    }

    @Test
    func persistsAndRestoresBothModes() {
        let defaults = isolatedDefaults()

        for mode in VoiceWidgetSizeMode.allCases {
            mode.save(to: defaults)
            #expect(VoiceWidgetSizeMode.load(from: defaults) == mode)
        }
    }

    @Test
    func invalidStoredValueFallsBackToStandard() {
        let defaults = isolatedDefaults()
        defaults.set("tiny", forKey: VoiceWidgetSizeMode.preferenceKey)

        #expect(VoiceWidgetSizeMode.load(from: defaults) == .standard)
    }

    @Test
    func miniShowsATimerOnlyWhenLinkingAndTimerStateBothExist() {
        #expect(
            MiniWidgetPresentationPolicy.layout(
                linkEnabled: false,
                hasActivityTimer: true,
                hasSessionTimer: true,
                recordingActive: false,
                sessionTimerDisclosed: false
            ) == .microphoneOnly
        )
        #expect(
            MiniWidgetPresentationPolicy.layout(
                linkEnabled: true,
                hasActivityTimer: false,
                hasSessionTimer: false,
                recordingActive: false,
                sessionTimerDisclosed: false
            ) == .microphoneOnly
        )
        #expect(
            MiniWidgetPresentationPolicy.layout(
                linkEnabled: true,
                hasActivityTimer: true,
                hasSessionTimer: false,
                recordingActive: false,
                sessionTimerDisclosed: false
            ) == .singleTimer
        )
        #expect(
            MiniWidgetPresentationPolicy.layout(
                linkEnabled: true,
                hasActivityTimer: false,
                hasSessionTimer: true,
                recordingActive: false,
                sessionTimerDisclosed: false
            ) == .singleTimer
        )
    }

    @Test
    func miniRecordingAlwaysCollapsesToTheOneCircleState() {
        #expect(
            MiniWidgetPresentationPolicy.layout(
                linkEnabled: true,
                hasActivityTimer: true,
                hasSessionTimer: true,
                recordingActive: true,
                sessionTimerDisclosed: true
            ) == .microphoneOnly
        )
    }

    @Test
    func miniDisclosesTheSessionOnlyBesideAnActivityTimer() {
        #expect(
            MiniWidgetPresentationPolicy.canDiscloseSessionTimer(
                hasActivityTimer: true,
                hasSessionTimer: true
            )
        )
        #expect(
            !MiniWidgetPresentationPolicy.canDiscloseSessionTimer(
                hasActivityTimer: false,
                hasSessionTimer: true
            )
        )
        #expect(
            MiniWidgetPresentationPolicy.layout(
                linkEnabled: true,
                hasActivityTimer: true,
                hasSessionTimer: true,
                recordingActive: false,
                sessionTimerDisclosed: true
            ) == .dualTimer
        )
    }

    @Test
    func miniPrefersTheActivityTimerAndFallsBackToTheSessionTimer() {
        #expect(
            MiniWidgetPresentationPolicy.timerSource(
                hasActivityTimer: true,
                hasSessionTimer: true
            ) == .activity
        )
        #expect(
            MiniWidgetPresentationPolicy.timerSource(
                hasActivityTimer: false,
                hasSessionTimer: true
            ) == .session
        )
        #expect(
            MiniWidgetPresentationPolicy.timerSource(
                hasActivityTimer: false,
                hasSessionTimer: false
            ) == nil
        )
    }

    @Test
    func miniGeometryHasOneStableWidthPerInformationState() {
        #expect(
            MiniWidgetPresentationPolicy.width(for: .microphoneOnly)
                == FloatingWidgetWindowPolicy.miniMicrophoneWidth
        )
        #expect(
            MiniWidgetPresentationPolicy.width(for: .singleTimer)
                == FloatingWidgetWindowPolicy.miniTimerWidth
        )
        #expect(
            MiniWidgetPresentationPolicy.width(for: .dualTimer)
                == FloatingWidgetWindowPolicy.miniDualTimerWidth
        )
        #expect(
            FloatingWidgetWindowPolicy.miniMicrophoneWidth
                < FloatingWidgetWindowPolicy.miniTimerWidth
        )
        #expect(
            FloatingWidgetWindowPolicy.miniTimerWidth
                < FloatingWidgetWindowPolicy.miniDualTimerWidth
        )
        #expect(
            FloatingWidgetWindowPolicy.miniMicrophoneWidth
                >= FloatingWidgetWindowPolicy.miniMicrophoneSurfaceDiameter + 8
        )
        #expect(
            FloatingWidgetWindowPolicy.miniMicrophoneSurfaceDiameter
                == FloatingWidgetWindowPolicy.capsuleHeight
        )
    }

    @Test
    func miniPointerMovementSeparatesClicksFromDrags() {
        #expect(
            !MiniWidgetPointerPolicy.isDrag(
                translation: CGSize(width: 3, height: 3)
            )
        )
        #expect(
            MiniWidgetPointerPolicy.isDrag(
                translation: CGSize(width: 5, height: 0)
            )
        )

        let origin = MiniWidgetPointerPolicy.translatedOrigin(
            startOrigin: CGPoint(x: 120, y: 80),
            startPointer: CGPoint(x: 400, y: 300),
            currentPointer: CGPoint(x: 525, y: 255)
        )
        #expect(origin == CGPoint(x: 245, y: 35))

        let clamped = MiniWidgetPointerPolicy.clampedOrigin(
            proposed: CGPoint(x: -200, y: 900),
            panelSize: CGSize(width: 108, height: 56),
            visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
        #expect(clamped == CGPoint(x: 0, y: 544))
    }

    @Test
    func standardToMiniResizePreservesTheMicrophoneSideAndBottomBaseline() {
        let standard = CGRect(
            x: 800,
            y: 140,
            width: FloatingWidgetWindowPolicy.collapsedWidth,
            height: FloatingWidgetWindowPolicy.hostHeight
        )
        let mini = FloatingWidgetGeometryPolicy.anchoredFrame(
            currentFrame: standard,
            targetSize: CGSize(
                width: FloatingWidgetWindowPolicy.miniMicrophoneWidth,
                height: FloatingWidgetWindowPolicy.hostHeight
            )
        )

        #expect(mini.maxX == standard.maxX)
        #expect(mini.minY == standard.minY)
    }

    @Test
    func expandingStopIsBoundedResponsiveAndVisibleAtConversationLevel() {
        #expect(
            MiniWidgetExpandingStopPolicy.normalizedLevel(decibels: -90) == 0
        )
        #expect(
            MiniWidgetExpandingStopPolicy.normalizedLevel(decibels: 0) == 1
        )

        let quiet = MiniWidgetExpandingStopPolicy.normalizedLevel(
            decibels: -45
        )
        let conversational = MiniWidgetExpandingStopPolicy.normalizedLevel(
            decibels: -30
        )
        let loud = MiniWidgetExpandingStopPolicy.normalizedLevel(
            decibels: -18
        )
        #expect(loud > quiet)
        #expect(conversational >= 0.7)

        let attack = MiniWidgetExpandingStopPolicy.smoothedLevel(
            previous: 0.1,
            current: 1
        )
        let release = MiniWidgetExpandingStopPolicy.smoothedLevel(
            previous: 0.9,
            current: 0
        )
        #expect(attack - 0.1 > 0.9 - release)
        #expect(
            MiniWidgetExpandingStopPolicy.stopSize(level: 0)
                == MiniWidgetExpandingStopPolicy.minimumSize
        )
        #expect(
            MiniWidgetExpandingStopPolicy.stopSize(level: conversational)
                > MiniWidgetExpandingStopPolicy.stopSize(level: quiet)
        )
        #expect(
            MiniWidgetExpandingStopPolicy.stopSize(level: loud)
                == MiniWidgetExpandingStopPolicy.maximumSize
        )
        #expect(
            MiniWidgetExpandingStopPolicy.maximumSize < 32
        )
        #expect(
            MiniWidgetExpandingStopPolicy.cornerRadius(
                for: MiniWidgetExpandingStopPolicy.minimumSize
            ) == MiniWidgetExpandingStopPolicy.minimumSize / 2
        )
        #expect(
            MiniWidgetExpandingStopPolicy.accessibilityDescription(level: 0)
                == "No sound detected"
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "VoiceWidgetSizeModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
