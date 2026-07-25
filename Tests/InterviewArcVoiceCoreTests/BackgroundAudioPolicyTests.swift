import Testing
@testable import InterviewArcVoiceCore

@Test func lowerModeUsesARelativeFractionOfTheCurrentVolume() {
    let target = BackgroundAudioPolicy.targetVolume(
        currentVolume: 0.5,
        mode: .lower,
        relativeLevel: 0.20
    )

    #expect(target == 0.1)
}

@Test func unchangedModeNeverMutatesSystemVolume() {
    #expect(
        BackgroundAudioPolicy.targetVolume(
            currentVolume: 0.6,
            mode: .unchanged,
            relativeLevel: 0.2
        ) == nil
    )
}

@Test func restorationRespectsAManualVolumeOverride() {
    let snapshot = BackgroundAudioVolumeSnapshot(
        deviceUID: "headphones",
        originalVolume: 0.5,
        appliedVolume: 0.1
    )

    #expect(
        BackgroundAudioPolicy.shouldRestore(
            currentVolume: 0.101,
            snapshot: snapshot
        )
    )
    #expect(
        !BackgroundAudioPolicy.shouldRestore(
            currentVolume: 0.3,
            snapshot: snapshot
        )
    )
}
