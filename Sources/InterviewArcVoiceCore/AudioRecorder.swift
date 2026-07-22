import AVFoundation
import Foundation

@MainActor
public final class AnswerRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published public private(set) var isRecording = false
    @Published public private(set) var elapsedSeconds: TimeInterval = 0
    @Published public private(set) var averagePower: Float = -60

    private var recorder: AVAudioRecorder?
    private var ticker: Timer?
    private var startedAt: Date?

    public override init() {}

    public func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default: return false
        }
    }

    public func start(at url: URL) async throws {
        guard await requestPermission() else { throw VoiceBridgeError.microphoneDenied }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 48_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            throw VoiceBridgeError.recordingUnavailable
        }
        self.recorder = recorder
        startedAt = Date()
        elapsedSeconds = 0
        averagePower = -60
        isRecording = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt, let recorder = self.recorder else { return }
                self.elapsedSeconds = Date().timeIntervalSince(startedAt)
                recorder.updateMeters()
                self.averagePower = recorder.averagePower(forChannel: 0)
            }
        }
    }

    public func stop() throws -> (url: URL, duration: TimeInterval) {
        guard let recorder else { throw VoiceBridgeError.recordingUnavailable }
        recorder.stop()
        ticker?.invalidate()
        ticker = nil
        let duration = max(elapsedSeconds, recorder.currentTime)
        let url = recorder.url
        self.recorder = nil
        startedAt = nil
        isRecording = false
        averagePower = -60
        elapsedSeconds = duration
        return (url, duration)
    }
}
