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
    public let peakPowerDecibels: Float?

    public init(
        url: URL,
        duration: TimeInterval,
        writtenFrameCount: Int64,
        writeErrorDescription: String?,
        peakPowerDecibels: Float? = nil
    ) {
        self.url = url
        self.duration = duration
        self.writtenFrameCount = writtenFrameCount
        self.writeErrorDescription = writeErrorDescription
        self.peakPowerDecibels = peakPowerDecibels
    }
}

@MainActor
public final class AnswerRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published public private(set) var isRecording = false
    @Published public private(set) var elapsedSeconds: TimeInterval = 0
    @Published public private(set) var averagePower: Float = -60
    @Published public private(set) var powerHistory: [Float] = []
    @Published public private(set) var signalHealth: MicrophoneSignalHealth = .warmingUp
    @Published public private(set) var inputDeviceName = "Default microphone"
    @Published public private(set) var automaticRecoveryCount = 0
    @Published public private(set) var isRecoveringSignal = false
    public var onUnexpectedTermination: (@MainActor () -> Void)?

    private var recorder: AVAudioRecorder?
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var destinationURL: URL?
    private var audioWriteState: AudioWriteState?
    private var ticker: Timer?
    private var startedAt: Date?
    private var signalAttemptStartedAt: Date?
    private var peakPower: Float = -160
    private let signalPolicy = MicrophoneSignalPolicy()
    private let streamRecoveryPolicy = MicrophoneStreamRecoveryPolicy()
    private var recorderErrorDescription: String?
    private var expectedRecorderCompletion: AVAudioRecorder?
    private var unexpectedTerminationReported = false
    private let startupReadinessPolicy = MicrophoneStartupReadinessPolicy()
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

    public func start(
        at url: URL,
        captureBackendDidStart: @escaping @MainActor () -> Void = {}
    ) async throws {
        guard await requestPermission() else { throw VoiceBridgeError.microphoneDenied }
        destinationURL = url
        inputDeviceName = AVCaptureDevice.default(for: .audio)?.localizedName
            ?? "Default microphone"
        recorderErrorDescription = nil
        elapsedSeconds = 0
        averagePower = -60
        powerHistory = []
        peakPower = -160
        signalHealth = .warmingUp
        automaticRecoveryCount = 0
        isRecoveringSignal = false
        expectedRecorderCompletion = nil
        unexpectedTerminationReported = false
        do {
            // Begin writing into the final capture before advertising a live
            // recording. Bluetooth may still be negotiating its hands-free
            // input route even though AVAudioRecorder.record() returned true.
            try startRecorderFallback(at: url)
            captureBackendDidStart()
            try await awaitOperationalInput(isUsingFallback: false)
        } catch {
            cancelPreparedCapture()
            throw error
        }
        startedAt = Date()
        signalAttemptStartedAt = startedAt
        isRecording = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let startedAt = self.startedAt,
                      let signalAttemptStartedAt = self.signalAttemptStartedAt else { return }
                self.elapsedSeconds = Date().timeIntervalSince(startedAt)
                if let recorder = self.recorder {
                    recorder.updateMeters()
                    self.recordPower(recorder.averagePower(forChannel: 0))
                }
                self.signalHealth = self.signalPolicy.health(
                    elapsedSeconds: Date().timeIntervalSince(signalAttemptStartedAt),
                    peakPowerDecibels: self.peakPower
                )
                if self.recorder != nil,
                   self.streamRecoveryPolicy.shouldRestart(
                       health: self.signalHealth,
                       completedRestarts: self.automaticRecoveryCount
                   ) {
                    self.restartSilentInputStream()
                }
            }
        }
    }

    private func awaitOperationalInput(
        isUsingFallback: Bool
    ) async throws {
        let attemptStartedAt = Date()
        while true {
            let captureBackendIsAdvancing: Bool
            if isUsingFallback {
                captureBackendIsAdvancing =
                    (audioWriteState?.snapshot().frames ?? 0) > 0
            } else if let recorder {
                // Do not block capture on an output-route signature or on
                // speech volume. AirPods can keep the same logical output
                // identity while their microphone is already usable, and a
                // quiet user should not have to speak to unlock recording.
                captureBackendIsAdvancing = recorder.currentTime > 0.03
            } else {
                captureBackendIsAdvancing = false
            }

            switch startupReadinessPolicy.decision(
                elapsedSeconds: Date().timeIntervalSince(attemptStartedAt),
                captureBackendIsAdvancing: captureBackendIsAdvancing,
                isUsingFallback: isUsingFallback
            ) {
            case .wait:
                try await Task.sleep(for: .milliseconds(50))
            case .ready:
                return
            case .startFallback:
                try switchToEngineRecoveryCapture()
                try await awaitOperationalInput(isUsingFallback: true)
                return
            case .fail:
                throw VoiceBridgeError.recordingUnavailable
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
            expectedRecorderCompletion = recorder
            recorder.stop()
            elapsedSeconds = max(duration, recorderDuration)
            self.recorder = nil
        } else {
            stopVoiceProcessedCapture()
        }
        let writeSnapshot = audioWriteState?.snapshot()
            ?? (frames: fallbackFrames, errorDescription: recorderErrorDescription)
        let recordedPeakPower = peakPower
        audioWriteState = nil
        recorderErrorDescription = nil
        ticker?.invalidate()
        ticker = nil
        startedAt = nil
        signalAttemptStartedAt = nil
        destinationURL = nil
        isRecording = false
        averagePower = -60
        peakPower = -160
        isRecoveringSignal = false
        return RecordedCapture(
            url: url,
            duration: max(duration, elapsedSeconds),
            writtenFrameCount: writeSnapshot.frames,
            writeErrorDescription: writeSnapshot.errorDescription,
            peakPowerDecibels: recordedPeakPower
        )
    }

    private func restartSilentInputStream() {
        do {
            try switchToEngineRecoveryCapture()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(800))
                self?.isRecoveringSignal = false
            }
        } catch {
            recorderErrorDescription =
                "The microphone stream stayed silent and the independent capture fallback could not start: \(error.localizedDescription)"
            signalHealth = .absent
            isRecoveringSignal = false
        }
    }

    private func switchToEngineRecoveryCapture() throws {
        guard let url = destinationURL else {
            throw VoiceBridgeError.recordingUnavailable
        }
        automaticRecoveryCount += 1
        isRecoveringSignal = true
        let recoveredURL = url.deletingLastPathComponent().appending(
            path: "\(url.deletingPathExtension().lastPathComponent)-recovered-\(UUID().uuidString.lowercased()).m4a"
        )
        do {
            inputDeviceName = AVCaptureDevice.default(for: .audio)?.localizedName
                ?? "Default microphone"
            // Start an independent capture backend before releasing the
            // stalled AVAudioRecorder. Reopening the same recorder immediately
            // can reacquire the same silent Bluetooth/default-input stream.
            try startEngineRecoveryCapture(at: recoveredURL)
            expectedRecorderCompletion = recorder
            recorder?.stop()
            recorder = nil
            try? FileManager.default.removeItem(at: url)
            destinationURL = recoveredURL
            signalAttemptStartedAt = Date()
            averagePower = -60
            powerHistory = []
            peakPower = -160
            signalHealth = .warmingUp
        } catch {
            try? FileManager.default.removeItem(at: recoveredURL)
            throw error
        }
    }

    private func startEngineRecoveryCapture(at url: URL) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode

        // Deliberately do not enable Voice Processing I/O here. This is an
        // independent recovery backend, and the voice-processing input unit
        // previously started without delivering writable frames on affected
        // Bluetooth routes.
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
                self?.recordPower(power)
            }
        }
        input.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: inputFormat
        ) { @Sendable buffer, _ in
            tap.consume(buffer)
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
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
        }
        audioFile = nil
        audioEngine = nil
    }

    private func cancelPreparedCapture() {
        if let recorder {
            expectedRecorderCompletion = recorder
            recorder.stop()
            self.recorder = nil
        }
        stopVoiceProcessedCapture()
        if let destinationURL {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        audioWriteState = nil
        audioFile = nil
        destinationURL = nil
        startedAt = nil
        signalAttemptStartedAt = nil
        isRecoveringSignal = false
    }

    private func recordPower(_ power: Float) {
        averagePower = power
        powerHistory.append(power)
        if powerHistory.count > 72 {
            powerHistory.removeFirst(powerHistory.count - 72)
        }
        peakPower = max(peakPower, power)
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            let completionWasExpected = self.expectedRecorderCompletion === recorder
            if completionWasExpected {
                self.expectedRecorderCompletion = nil
            }
            guard RecordingTerminationPolicy.shouldSurfaceUnexpectedTermination(
                isCaptureActive: self.isRecording,
                completionWasExpected: completionWasExpected,
                alreadyReported: self.unexpectedTerminationReported
            ) else {
                return
            }
            self.unexpectedTerminationReported = true
            if self.recorderErrorDescription == nil {
                self.recorderErrorDescription = flag
                    ? "The system audio recorder ended the active capture unexpectedly."
                    : "The system audio recorder did not finalize successfully."
            }
            self.onUnexpectedTermination?()
        }
    }

}
