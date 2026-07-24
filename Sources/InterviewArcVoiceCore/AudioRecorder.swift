import AVFoundation
import Foundation

private final class VoiceProcessedAudioTap: @unchecked Sendable {
    private let file: AVAudioFile
    private let reportPower: @Sendable (Float) -> Void

    init(
        file: AVAudioFile,
        reportPower: @escaping @Sendable (Float) -> Void
    ) {
        self.file = file
        self.reportPower = reportPower
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        try? file.write(from: buffer)
        reportPower(Self.powerDecibels(buffer))
    }

    private static func powerDecibels(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData,
              buffer.frameLength > 0 else { return -60 }
        let sampleCount = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<sampleCount {
            let value = channels[0][index]
            sum += value * value
        }
        let rootMeanSquare = sqrt(sum / Float(sampleCount))
        return max(-60, 20 * log10(max(rootMeanSquare, 0.000_001)))
    }
}

@MainActor
public final class AnswerRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published public private(set) var isRecording = false
    @Published public private(set) var elapsedSeconds: TimeInterval = 0
    @Published public private(set) var averagePower: Float = -60

    private var recorder: AVAudioRecorder?
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var destinationURL: URL?
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
        destinationURL = url
        do {
            try startVoiceProcessedCapture(at: url)
        } catch {
            stopVoiceProcessedCapture()
            try startRecorderFallback(at: url)
        }
        startedAt = Date()
        elapsedSeconds = 0
        averagePower = -60
        isRecording = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedSeconds = Date().timeIntervalSince(startedAt)
                if let recorder = self.recorder {
                    recorder.updateMeters()
                    self.averagePower = recorder.averagePower(forChannel: 0)
                }
            }
        }
    }

    public func stop() throws -> (url: URL, duration: TimeInterval) {
        guard isRecording, let url = destinationURL else {
            throw VoiceBridgeError.recordingUnavailable
        }
        let duration = max(0, elapsedSeconds)
        if let recorder {
            let recorderDuration = recorder.currentTime
            recorder.stop()
            elapsedSeconds = max(duration, recorderDuration)
            self.recorder = nil
        } else {
            stopVoiceProcessedCapture()
        }
        ticker?.invalidate()
        ticker = nil
        startedAt = nil
        destinationURL = nil
        isRecording = false
        averagePower = -60
        return (url, max(duration, elapsedSeconds))
    }

    private func startVoiceProcessedCapture(at url: URL) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode

        // Voice Processing I/O provides the echo cancellation and noise
        // suppression expected from a dictation tool. Without it, speaker
        // audio and room noise can be transcribed as unrelated speech.
        try input.setVoiceProcessingEnabled(true)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw VoiceBridgeError.recordingUnavailable
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: Int(inputFormat.channelCount),
            AVEncoderBitRateKey: 48_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let tap = VoiceProcessedAudioTap(file: file) { [weak self] power in
            Task { @MainActor [weak self] in
                self?.averagePower = power
            }
        }
        input.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: inputFormat
        ) { @Sendable buffer, _ in
            tap.consume(buffer)
        }
        engine.prepare()
        try engine.start()
        audioFile = file
        audioEngine = engine
    }

    private func startRecorderFallback(at url: URL) throws {
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
    }

    private func stopVoiceProcessedCapture() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
        audioFile = nil
        audioEngine = nil
    }

}
