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
                hasSessionTimer: true
            ) == .microphoneOnly
        )
        #expect(
            MiniWidgetPresentationPolicy.layout(
                linkEnabled: true,
                hasActivityTimer: false,
                hasSessionTimer: false
            ) == .microphoneOnly
        )
        #expect(
            MiniWidgetPresentationPolicy.layout(
                linkEnabled: true,
                hasActivityTimer: true,
                hasSessionTimer: false
            ) == .timer
        )
        #expect(
            MiniWidgetPresentationPolicy.layout(
                linkEnabled: true,
                hasActivityTimer: false,
                hasSessionTimer: true
            ) == .timer
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
            MiniWidgetPresentationPolicy.width(for: .timer)
                == FloatingWidgetWindowPolicy.miniTimerWidth
        )
        #expect(
            FloatingWidgetWindowPolicy.miniMicrophoneWidth
                < FloatingWidgetWindowPolicy.miniTimerWidth
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
        let loud = MiniWidgetAudioGlowPolicy.normalizedLevel(decibels: -12)
        #expect(loud > quiet)

        let smoothed = MiniWidgetAudioGlowPolicy.smoothedLevel(
            previous: 0.2,
            current: 1
        )
        #expect(smoothed > 0.2)
        #expect(smoothed < 1)
        #expect(
            MiniWidgetAudioGlowPolicy.pulseDuration(level: loud)
                < MiniWidgetAudioGlowPolicy.pulseDuration(level: quiet)
        )

        let quietDiameter = MiniWidgetAudioGlowPolicy.ringDiameter(
            level: quiet,
            pulse: 0.25
        )
        let loudDiameter = MiniWidgetAudioGlowPolicy.ringDiameter(
            level: loud,
            pulse: 0.75
        )
        #expect(loudDiameter > quietDiameter)
        #expect(
            quietDiameter >= MiniWidgetAudioGlowPolicy.minimumRingDiameter
        )
        #expect(
            loudDiameter <= MiniWidgetAudioGlowPolicy.maximumRingDiameter
        )
        #expect(
            MiniWidgetAudioGlowPolicy.ringOpacity(level: loud, pulse: 1)
                > MiniWidgetAudioGlowPolicy.ringOpacity(level: quiet, pulse: 0)
        )
        #expect(
            MiniWidgetAudioGlowPolicy.ringLineWidth(level: loud)
                > MiniWidgetAudioGlowPolicy.ringLineWidth(level: quiet)
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "VoiceWidgetSizeModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
