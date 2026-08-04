import CoreAudio
import AudioToolbox
import Foundation
import InterviewArcVoiceCore

@MainActor
final class SystemOutputVolumeController {
    private enum RestorationProgress: Equatable {
        case pending
        case baselineAtOriginalVolume
        case complete
    }

    private struct ActiveRoute {
        let device: AudioDeviceID
        let deviceUID: String
        let nominalSampleRate: Double
        let outputChannelCount: UInt32
        let isBluetooth: Bool
    }

    private static let snapshotKey = "voice.backgroundAudioSnapshot"

    private let defaults: UserDefaults
    private var restoreTask: Task<Void, Never>?
    private var routeSyncTasks: [Task<Void, Never>] = []
    private var recordingMode: BackgroundAudioRecordingMode = .unchanged
    private var recordingRelativeLevel = BackgroundAudioPolicy.defaultRelativeLevel
    private var baselineUsesBluetooth = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recoverInterruptedSessionIfNeeded() {
        guard loadSnapshot() != nil else { return }
        beginPendingRestoration()
    }

    /// Captures the route that must exist after recording, without changing its
    /// volume while Bluetooth is still negotiating the microphone profile.
    func prepareForRecording(
        mode: BackgroundAudioRecordingMode,
        relativeLevel: Double
    ) {
        restoreTask?.cancel()
        restoreTask = nil
        cancelRouteSyncTasks()

        recordingMode = mode
        recordingRelativeLevel = relativeLevel
        baselineUsesBluetooth = false
        let route = activeRoute()

        if let existing = loadSnapshot() {
            // A prior recording may still be waiting for the original stereo
            // profile. Reuse that durable baseline instead of replacing it
            // with the temporary hands-free route.
            let progress = restoreCurrentRouteIfPossible(existing)
            if progress == .baselineAtOriginalVolume || progress == .complete {
                clearSnapshot()
            } else {
                baselineUsesBluetooth = route?.isBluetooth ?? false
                if mode == .unchanged {
                    beginPendingRestoration()
                }
                return
            }
        }

        guard mode != .unchanged, let route,
              let current = volume(route.device),
              let target = BackgroundAudioPolicy.targetVolume(
                  currentVolume: current,
                  mode: mode,
                  relativeLevel: relativeLevel
              ) else {
            return
        }

        baselineUsesBluetooth = route.isBluetooth
        let baseline = BackgroundAudioVolumeSnapshot(
            deviceUID: route.deviceUID,
            nominalSampleRate: route.nominalSampleRate,
            outputChannelCount: route.outputChannelCount,
            originalVolume: current,
            appliedVolume: target
        )
        saveSnapshot(BackgroundAudioSessionSnapshot(baseline: baseline))
    }

    /// Applies the configured reduction only after the recorder has acquired
    /// the microphone. Bluetooth commonly changes from stereo A2DP to a
    /// one-channel hands-free profile during this boundary.
    func recordingDidStart() {
        guard recordingMode != .unchanged else { return }
        cancelRouteSyncTasks()

        if !baselineUsesBluetooth {
            applyRecordingLevelToCurrentRoute(allowBaselineRoute: true)
        }

        for delay in [120, 300, 600, 1_000] {
            let task = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                self?.applyRecordingLevelToCurrentRoute(
                    allowBaselineRoute: delay >= 600
                )
            }
            routeSyncTasks.append(task)
        }
    }

    func restoreAfterRouteSettles() {
        cancelRouteSyncTasks()
        beginPendingRestoration()
    }

    /// Best-effort synchronous restoration for termination. If Bluetooth has
    /// not returned to the original profile, the persisted snapshot remains so
    /// the next launch can finish the restoration.
    func restoreNow() {
        cancelRouteSyncTasks()
        restoreTask?.cancel()
        restoreTask = nil
        guard let session = loadSnapshot() else { return }
        if restoreCurrentRouteIfPossible(session) == .complete {
            clearSnapshot()
        }
    }

    private func beginPendingRestoration() {
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            var attempt = 0
            var stability = BackgroundAudioBaselineStabilityTracker()
            while !Task.isCancelled {
                guard let self, let session = self.loadSnapshot() else { return }
                switch self.restoreCurrentRouteIfPossible(session) {
                case .complete:
                    self.clearSnapshot()
                    return
                case .baselineAtOriginalVolume:
                    if stability.observe(
                        baselineAtOriginalVolume: true,
                        now: Date().timeIntervalSinceReferenceDate
                    ) {
                        self.clearSnapshot()
                        return
                    }
                case .pending:
                    _ = stability.observe(
                        baselineAtOriginalVolume: false,
                        now: Date().timeIntervalSinceReferenceDate
                    )
                }

                attempt += 1
                let delay = stability.isTracking
                    ? 180
                    : (attempt < 8 ? 180 : 1_000)
                try? await Task.sleep(for: .milliseconds(delay))
            }
        }
    }

    /// Reports the original route separately from final completion so the
    /// caller can require a stable readback window before deleting recovery
    /// state. Adjusted temporary profiles may be repaired earlier.
    private func restoreCurrentRouteIfPossible(
        _ session: BackgroundAudioSessionSnapshot
    ) -> RestorationProgress {
        guard let route = activeRoute(), let current = volume(route.device) else {
            return .pending
        }

        if let baseline = session.baseline,
           BackgroundAudioPolicy.shouldRestoreBaseline(
               currentDeviceUID: route.deviceUID,
               currentNominalSampleRate: route.nominalSampleRate,
               currentOutputChannelCount: route.outputChannelCount,
               baseline: baseline
           ) {
            if abs(current - baseline.originalVolume) <= 0.005 {
                return .baselineAtOriginalVolume
            }
            _ = setVolume(baseline.originalVolume, device: route.device)
            return .pending
        }

        if BackgroundAudioPolicy.shouldRestoreTemporaryRoute(
            hasPendingBaseline: session.baseline != nil
        ), let adjusted = session.route(
            deviceUID: route.deviceUID,
            nominalSampleRate: route.nominalSampleRate,
            outputChannelCount: route.outputChannelCount
        ), BackgroundAudioPolicy.shouldRestore(
            currentVolume: current,
            snapshot: adjusted
        ) {
            _ = setVolume(adjusted.originalVolume, device: route.device)
        }

        // Legacy snapshots have no explicit baseline. Restoring the currently
        // matching route preserves the pre-profile-aware recovery behavior.
        if session.baseline == nil,
           let legacy = session.route(
               deviceUID: route.deviceUID,
               nominalSampleRate: route.nominalSampleRate,
               outputChannelCount: route.outputChannelCount
           ) {
            if BackgroundAudioPolicy.shouldRestore(
                currentVolume: current,
                snapshot: legacy
            ) {
                _ = setVolume(legacy.originalVolume, device: route.device)
            }
            return .complete
        }

        return .pending
    }

    private func applyRecordingLevelToCurrentRoute(
        allowBaselineRoute: Bool
    ) {
        guard recordingMode != .unchanged,
              let route = activeRoute(),
              let current = volume(route.device) else {
            return
        }

        var session = loadSnapshot() ?? BackgroundAudioSessionSnapshot()
        if !allowBaselineRoute, let baseline = session.baseline,
           BackgroundAudioPolicy.shouldRestoreBaseline(
               currentDeviceUID: route.deviceUID,
               currentNominalSampleRate: route.nominalSampleRate,
               currentOutputChannelCount: route.outputChannelCount,
               baseline: baseline
           ) {
            return
        }

        if let existing = session.route(
            deviceUID: route.deviceUID,
            nominalSampleRate: route.nominalSampleRate,
            outputChannelCount: route.outputChannelCount
        ) {
            guard BackgroundAudioPolicy.shouldReapplyAfterRouteChange(
                currentVolume: current,
                snapshot: existing
            ) else {
                return
            }
            _ = setVolume(existing.appliedVolume, device: route.device)
            return
        }

        guard let target = BackgroundAudioPolicy.targetVolume(
            currentVolume: current,
            mode: recordingMode,
            relativeLevel: recordingRelativeLevel
        ), abs(current - target) > 0.005 else {
            return
        }

        let snapshot = BackgroundAudioVolumeSnapshot(
            deviceUID: route.deviceUID,
            nominalSampleRate: route.nominalSampleRate,
            outputChannelCount: route.outputChannelCount,
            originalVolume: current,
            appliedVolume: target
        )
        guard setVolume(target, device: route.device) else { return }
        session.remember(snapshot)
        saveSnapshot(session)
    }

    private func cancelRouteSyncTasks() {
        routeSyncTasks.forEach { $0.cancel() }
        routeSyncTasks.removeAll()
    }

    private func activeRoute() -> ActiveRoute? {
        guard let device = defaultOutputDevice(),
              let uid = deviceUID(device),
              let rate = nominalSampleRate(device) else {
            return nil
        }
        return ActiveRoute(
            device: device,
            deviceUID: uid,
            nominalSampleRate: rate,
            outputChannelCount: outputChannelCount(device),
            isBluetooth: transportType(device) == kAudioDeviceTransportTypeBluetooth
        )
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        ) == noErr, device != 0 else {
            return nil
        }
        return device
    }

    private func nominalSampleRate(_ device: AudioDeviceID) -> Double? {
        var value = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr else {
            return nil
        }
        return value
    }

    private func outputChannelCount(_ device: AudioDeviceID) -> UInt32 {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(
            device,
            &address,
            0,
            nil,
            &size
        ) == noErr, size >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            raw
        ) == noErr else {
            return 0
        }
        let buffers = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self)
        )
        return buffers.reduce(0) { $0 + $1.mNumberChannels }
    }

    private func transportType(_ device: AudioDeviceID) -> UInt32? {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr else {
            return nil
        }
        return value
    }

    private func volume(_ device: AudioDeviceID) -> Float? {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(
                  device,
                  &address,
                  0,
                  nil,
                  &size,
                  &value
              ) == noErr else {
            return nil
        }
        return value
    }

    private func setVolume(_ value: Float, device: AudioDeviceID) -> Bool {
        var settable: DarwinBoolean = false
        var address = volumeAddress
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else {
            return false
        }
        var clamped = Float32(max(0, min(1, value)))
        return AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &clamped
        ) == noErr
    }

    private func deviceUID(_ device: AudioDeviceID) -> String? {
        var uid: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            &uid
        ) == noErr else {
            return nil
        }
        return uid as String?
    }

    private var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func saveSnapshot(_ snapshot: BackgroundAudioSessionSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.snapshotKey)
        }
    }

    private func loadSnapshot() -> BackgroundAudioSessionSnapshot? {
        guard let data = defaults.data(forKey: Self.snapshotKey) else {
            return nil
        }
        if let session = try? JSONDecoder().decode(
            BackgroundAudioSessionSnapshot.self,
            from: data
        ) {
            return session
        }
        if let legacy = try? JSONDecoder().decode(
            BackgroundAudioVolumeSnapshot.self,
            from: data
        ) {
            return BackgroundAudioSessionSnapshot(routes: [legacy])
        }
        return nil
    }

    private func clearSnapshot() {
        defaults.removeObject(forKey: Self.snapshotKey)
    }
}
