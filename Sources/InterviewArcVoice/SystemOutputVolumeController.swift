import CoreAudio
import AudioToolbox
import Foundation
import InterviewArcVoiceCore

@MainActor
final class SystemOutputVolumeController {
    private static let snapshotKey = "voice.backgroundAudioSnapshot"

    private let defaults: UserDefaults
    private var restoreTask: Task<Void, Never>?
    private var routeSyncTasks: [Task<Void, Never>] = []
    private var recordingMode: BackgroundAudioRecordingMode = .unchanged
    private var recordingRelativeLevel = BackgroundAudioPolicy.defaultRelativeLevel

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recoverInterruptedSessionIfNeeded() {
        guard let session = loadSnapshot() else { return }
        defer { clearSnapshot() }
        for snapshot in session.routes {
            restore(snapshot)
        }
    }

    func lowerForRecording(
        mode: BackgroundAudioRecordingMode,
        relativeLevel: Double
    ) {
        restoreTask?.cancel()
        restoreTask = nil
        cancelRouteSyncTasks()

        // If a new capture begins before a deferred restoration completes,
        // finish the prior session first so reductions never compound.
        if loadSnapshot() != nil {
            restoreNow()
        }

        recordingMode = mode
        recordingRelativeLevel = relativeLevel
        applyRecordingLevelToCurrentRoute()

        // Bluetooth microphone acquisition can replace the audible output
        // route after AVAudioRecorder starts. Reconcile the active route at
        // short bounded intervals so the recording route—not the route that
        // returns after Stop—receives the reduced level.
        for delay in [80, 220, 500] {
            let task = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                self?.applyRecordingLevelToCurrentRoute()
            }
            routeSyncTasks.append(task)
        }
    }

    func restoreAfterRouteSettles() {
        cancelRouteSyncTasks()
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.restoreNow()
        }
    }

    func restoreNow() {
        cancelRouteSyncTasks()
        restoreTask?.cancel()
        restoreTask = nil
        guard let session = loadSnapshot() else { return }
        defer { clearSnapshot() }
        for snapshot in session.routes {
            restore(snapshot)
        }
    }

    private func applyRecordingLevelToCurrentRoute() {
        guard recordingMode != .unchanged,
              let device = defaultOutputDevice(),
              let uid = deviceUID(device),
              let current = volume(device) else {
            return
        }

        var session = loadSnapshot() ?? BackgroundAudioSessionSnapshot()
        if let existing = session.route(deviceUID: uid) {
            guard BackgroundAudioPolicy.shouldReapplyAfterRouteChange(
                currentVolume: current,
                snapshot: existing
            ) else {
                return
            }
            _ = setVolume(existing.appliedVolume, device: device)
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
            deviceUID: uid,
            originalVolume: current,
            appliedVolume: target
        )
        guard setVolume(target, device: device) else { return }
        session.remember(snapshot)
        saveSnapshot(session)
    }

    private func restore(_ snapshot: BackgroundAudioVolumeSnapshot) {
        guard let device = audioDevice(withUID: snapshot.deviceUID),
              let current = volume(device),
              BackgroundAudioPolicy.shouldRestore(
                currentVolume: current,
                snapshot: snapshot
              ) else {
            // A missing route or deliberate user volume change wins.
            return
        }
        _ = setVolume(snapshot.originalVolume, device: device)
    }

    private func cancelRouteSyncTasks() {
        routeSyncTasks.forEach { $0.cancel() }
        routeSyncTasks.removeAll()
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

    private func audioDevice(withUID uid: String) -> AudioDeviceID? {
        var size: UInt32 = 0
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return nil
        }
        var devices = Array(
            repeating: AudioDeviceID(0),
            count: Int(size) / MemoryLayout<AudioDeviceID>.size
        )
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        ) == noErr else {
            return nil
        }
        return devices.first { deviceUID($0) == uid }
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
