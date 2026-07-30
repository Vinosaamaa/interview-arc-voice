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
    func audioGlowLevelIsBoundedSmoothedAndFasterWhenLouder() {
        #expect(MiniWidgetAudioGlowPolicy.normalizedLevel(decibels: -90) == 0)
        #expect(MiniWidgetAudioGlowPolicy.normalizedLevel(decibels: 0) == 1)

        let quiet = MiniWidgetAudioGlowPolicy.normalizedLevel(decibels: -45)
        let conversational = MiniWidgetAudioGlowPolicy.normalizedLevel(
            decibels: -30
        )
        let loud = MiniWidgetAudioGlowPolicy.normalizedLevel(decibels: -18)
        #expect(loud > quiet)
        #expect(conversational >= 0.7)

        let smoothed = MiniWidgetAudioGlowPolicy.smoothedLevel(
            previous: 0.2,
            current: 1
        )
        #expect(smoothed >= 0.5)
        #expect(smoothed < 1)
        #expect(
            MiniWidgetAudioGlowPolicy.pulseDuration(level: loud)
                < MiniWidgetAudioGlowPolicy.pulseDuration(level: quiet)
        )

        #expect(
            MiniWidgetAudioGlowPolicy.ringOpacity(level: loud, pulse: 1)
                > MiniWidgetAudioGlowPolicy.ringOpacity(level: quiet, pulse: 0)
        )
        #expect(
            MiniWidgetAudioGlowPolicy.ringLineWidth(level: loud)
                > MiniWidgetAudioGlowPolicy.ringLineWidth(level: quiet)
        )
        #expect(
            MiniWidgetAudioGlowPolicy.maximumLineWidth
                >= MiniWidgetAudioGlowPolicy.persistentLineWidth * 2
        )
        #expect(
            MiniWidgetAudioGlowPolicy.meterArcDiameter
                + MiniWidgetAudioGlowPolicy.maximumLineWidth
                <= MiniWidgetAudioGlowPolicy.visualEnvelopeDiameter
        )
        #expect(
            MiniWidgetAudioGlowPolicy.visualEnvelopeDiameter
                <= FloatingWidgetWindowPolicy.miniMicrophoneWidth
        )
        #expect(
            MiniWidgetAudioGlowPolicy.meterArcFraction(level: quiet)
                < MiniWidgetAudioGlowPolicy.meterArcFraction(level: loud)
        )
        #expect(
            MiniWidgetAudioGlowPolicy.meterArcFraction(level: 0) == 0
        )
        #expect(
            MiniWidgetAudioGlowPolicy.meterArcFraction(level: 1) == 1
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "VoiceWidgetSizeModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
