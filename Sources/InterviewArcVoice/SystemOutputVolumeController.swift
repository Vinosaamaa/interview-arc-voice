import CoreAudio
import AudioToolbox
import Foundation
import InterviewArcVoiceCore

@MainActor
final class SystemOutputVolumeController {
    private static let snapshotKey = "voice.backgroundAudioSnapshot"

    private let defaults: UserDefaults
    private var restoreTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recoverInterruptedSessionIfNeeded() {
        guard let snapshot = loadSnapshot() else { return }
        defer { clearSnapshot() }
        guard let device = defaultOutputDevice(),
              deviceUID(device) == snapshot.deviceUID,
              let current = volume(device),
              BackgroundAudioPolicy.shouldRestore(
                currentVolume: current,
                snapshot: snapshot
              ) else {
            return
        }
        _ = setVolume(snapshot.originalVolume, device: device)
    }

    func lowerForRecording(
        mode: BackgroundAudioRecordingMode,
        relativeLevel: Double
    ) {
        restoreTask?.cancel()
        restoreTask = nil
        guard let device = defaultOutputDevice(),
              let uid = deviceUID(device),
              let current = volume(device),
              let target = BackgroundAudioPolicy.targetVolume(
                currentVolume: current,
                mode: mode,
                relativeLevel: relativeLevel
              ),
              abs(current - target) > 0.005 else {
            return
        }
        let snapshot = BackgroundAudioVolumeSnapshot(
            deviceUID: uid,
            originalVolume: current,
            appliedVolume: target
        )
        saveSnapshot(snapshot)
        if !setVolume(target, device: device) {
            clearSnapshot()
        }
    }

    func restoreAfterRouteSettles() {
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.restoreNow()
        }
    }

    func restoreNow() {
        restoreTask?.cancel()
        restoreTask = nil
        guard let snapshot = loadSnapshot() else { return }
        defer { clearSnapshot() }
        guard let device = defaultOutputDevice(),
              deviceUID(device) == snapshot.deviceUID,
              let current = volume(device),
              BackgroundAudioPolicy.shouldRestore(
                currentVolume: current,
                snapshot: snapshot
              ) else {
            // A different device or a user volume change wins. Never surprise
            // the user by overwriting a manual adjustment.
            return
        }
        _ = setVolume(snapshot.originalVolume, device: device)
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

    private func saveSnapshot(_ snapshot: BackgroundAudioVolumeSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.snapshotKey)
        }
    }

    private func loadSnapshot() -> BackgroundAudioVolumeSnapshot? {
        guard let data = defaults.data(forKey: Self.snapshotKey) else {
            return nil
        }
        return try? JSONDecoder().decode(
            BackgroundAudioVolumeSnapshot.self,
            from: data
        )
    }

    private func clearSnapshot() {
        defaults.removeObject(forKey: Self.snapshotKey)
    }
}
