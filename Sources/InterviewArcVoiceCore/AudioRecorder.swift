import AVFoundation
import Foundation

private final class VoiceProcessedAudioTap: @unchecked Sendable {
    private let file: AVAudioFile
    private let reportPower: @Sendable (Float) -> Void
    let writeState: AudioWriteState

    init(
        file: AVAudioFile,
        writeState: AudioWriteState,
        reportPower: @escaping @Sendable (Float) -> Void
    ) {
        self.file = file
        self.writeState = writeState
        self.reportPower = reportPower
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        do {
            try file.write(from: buffer)
            writeState.recordFrames(Int64(buffer.frameLength))
        } catch {
            writeState.recordError(error)
        }
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

private final class AudioWriteState: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: Int64 = 0
    private var errorDescription: String?

    func recordFrames(_ count: Int64) {
        lock.lock()
        frames += count
        lock.unlock()
    }

    func recordError(_ error: Error) {
        lock.lock()
        if errorDescription == nil { errorDescription = error.localizedDescription }
        lock.unlock()
    }

    func snapshot() -> (frames: Int64, errorDescription: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (frames, errorDescription)
    }
}

public struct RecordedCapture: Sendable {
    public let url: URL
    public let duration: TimeInterval
    public let writtenFrameCount: Int64
    public let writeErrorDescription: String?

    public init(
        url: URL,
        duration: TimeInterval,
        writtenFrameCount: Int64,
        writeErrorDescription: String?
    ) {
        self.url = url
        self.duration = duration
        self.writtenFrameCount = writtenFrameCount
        self.writeErrorDescription = writeErrorDescription
    }
}

@MainActor
public final class AnswerRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published public private(set) var isRecording = false
    @Published public private(set) var elapsedSeconds: TimeInterval = 0
    @Published public private(set) var averagePower: Float = -60
    @Published public private(set) var signalHealth: MicrophoneSignalHealth = .warmingUp
    @Published public private(set) var inputDeviceName = "Default microphone"

    private var recorder: AVAudioRecorder?
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var destinationURL: URL?
    private var audioWriteState: AudioWriteState?
    private var ticker: Timer?
    private var startedAt: Date?
    private var peakPower: Float = -160
    private let signalPolicy = MicrophoneSignalPolicy()
    private var recorderErrorDescription: String?

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
        inputDeviceName = AVCaptureDevice.default(for: .audio)?.localizedName
            ?? "Default microphone"
        recorderErrorDescription = nil
        // AVAudioRecorder owns file finalization and has proven reliable across
        // signed app replacements. The prior voice-processing tap could start
        // successfully while never delivering writable frames, leaving a
        // header-only M4A that looked like a provider failure.
        try startRecorderFallback(at: url)
        startedAt = Date()
        elapsedSeconds = 0
        averagePower = -60
        peakPower = -160
        signalHealth = .warmingUp
        isRecording = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedSeconds = Date().timeIntervalSince(startedAt)
                if let recorder = self.recorder {
                    recorder.updateMeters()
                    self.averagePower = recorder.averagePower(forChannel: 0)
                    self.peakPower = max(self.peakPower, self.averagePower)
                    self.signalHealth = self.signalPolicy.health(
                        elapsedSeconds: self.elapsedSeconds,
                        peakPowerDecibels: self.peakPower
                    )
                }
            }
        }
    }

    public func stop() throws -> RecordedCapture {
        guard isRecording, let url = destinationURL else {
            throw VoiceBridgeError.recordingUnavailable
        }
        let duration = max(0, elapsedSeconds)
        let fallbackFrames: Int64 = 0
        if let recorder {
            let recorderDuration = recorder.currentTime
            recorder.stop()
            elapsedSeconds = max(duration, recorderDuration)
            self.recorder = nil
        } else {
            stopVoiceProcessedCapture()
        }
        let writeSnapshot = audioWriteState?.snapshot()
            ?? (frames: fallbackFrames, errorDescription: recorderErrorDescription)
        audioWriteState = nil
        recorderErrorDescription = nil
        ticker?.invalidate()
        ticker = nil
        startedAt = nil
        destinationURL = nil
        isRecording = false
        averagePower = -60
        return RecordedCapture(
            url: url,
            duration: max(duration, elapsedSeconds),
            writtenFrameCount: writeSnapshot.frames,
            writeErrorDescription: writeSnapshot.errorDescription
        )
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
        let writeState = AudioWriteState()
        let tap = VoiceProcessedAudioTap(file: file, writeState: writeState) { [weak self] power in
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
        audioWriteState = writeState
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
        audioWriteState = nil
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

    public nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: Error?
    ) {
        let description = error?.localizedDescription
            ?? "The system audio recorder reported an encoding failure."
        Task { @MainActor [weak self] in
            self?.recorderErrorDescription = description
        }
    }

    public nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        guard !flag else { return }
        Task { @MainActor [weak self] in
            if self?.recorderErrorDescription == nil {
                self?.recorderErrorDescription =
                    "The system audio recorder did not finalize successfully."
            }
        }
    }

}
