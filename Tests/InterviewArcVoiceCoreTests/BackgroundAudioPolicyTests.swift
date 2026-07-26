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

@Test func backgroundAudioSessionKeepsIndependentRouteBaselines() {
    var session = BackgroundAudioSessionSnapshot()
    let musicRoute = BackgroundAudioVolumeSnapshot(
        deviceUID: "airpods-music",
        nominalSampleRate: 48_000,
        outputChannelCount: 2,
        originalVolume: 0.5,
        appliedVolume: 0.1
    )
    let microphoneRoute = BackgroundAudioVolumeSnapshot(
        deviceUID: "airpods-handsfree",
        nominalSampleRate: 24_000,
        outputChannelCount: 1,
        originalVolume: 0.4,
        appliedVolume: 0.08
    )

    session.remember(musicRoute)
    session.remember(microphoneRoute)

    #expect(session.routes.count == 2)
    #expect(
        session.route(
            deviceUID: "airpods-music",
            nominalSampleRate: 48_000,
            outputChannelCount: 2
        ) == musicRoute
    )
    #expect(
        session.route(
            deviceUID: "airpods-handsfree",
            nominalSampleRate: 24_000,
            outputChannelCount: 1
        ) == microphoneRoute
    )
}

@Test func routeResetToOriginalLevelCanBeReappliedWithoutCompounding() {
    let snapshot = BackgroundAudioVolumeSnapshot(
        deviceUID: "airpods",
        originalVolume: 0.5,
        appliedVolume: 0.1
    )

    #expect(
        BackgroundAudioPolicy.shouldReapplyAfterRouteChange(
            currentVolume: 0.5,
            snapshot: snapshot
        )
    )
    #expect(
        !BackgroundAudioPolicy.shouldReapplyAfterRouteChange(
            currentVolume: 0.3,
            snapshot: snapshot
        )
    )
}

@Test func bluetoothProfilesWithTheSameUIDRemainDistinctRoutes() {
    var session = BackgroundAudioSessionSnapshot()
    let stereo = BackgroundAudioVolumeSnapshot(
        deviceUID: "airpods",
        nominalSampleRate: 48_000,
        outputChannelCount: 2,
        originalVolume: 0.5,
        appliedVolume: 0.1
    )
    let handsFree = BackgroundAudioVolumeSnapshot(
        deviceUID: "airpods",
        nominalSampleRate: 24_000,
        outputChannelCount: 1,
        originalVolume: 0.45,
        appliedVolume: 0.09
    )

    session.remember(stereo)
    session.remember(handsFree)

    #expect(session.routes.count == 2)
    #expect(
        session.route(
            deviceUID: "airpods",
            nominalSampleRate: 48_000,
            outputChannelCount: 2
        ) == stereo
    )
    #expect(
        session.route(
            deviceUID: "airpods",
            nominalSampleRate: 24_000,
            outputChannelCount: 1
        ) == handsFree
    )
}

@Test func baselineRestorationWaitsForTheOriginalBluetoothProfile() {
    let baseline = BackgroundAudioVolumeSnapshot(
        deviceUID: "airpods",
        nominalSampleRate: 48_000,
        outputChannelCount: 2,
        originalVolume: 0.5,
        appliedVolume: 0.1
    )

    #expect(
        !BackgroundAudioPolicy.shouldRestoreBaseline(
            currentDeviceUID: "airpods",
            currentNominalSampleRate: 24_000,
            currentOutputChannelCount: 1,
            baseline: baseline
        )
    )
    #expect(
        BackgroundAudioPolicy.shouldRestoreBaseline(
            currentDeviceUID: "airpods",
            currentNominalSampleRate: 48_000,
            currentOutputChannelCount: 2,
            baseline: baseline
        )
    )
}
