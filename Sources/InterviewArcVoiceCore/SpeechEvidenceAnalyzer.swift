@preconcurrency import AVFoundation
import Foundation
import libfvad

public struct SpeechIntervalEvidence: Equatable, Sendable {
    public let frameCount: Int
    public let speechLikeFrameCount: Int
    public let longestSpeechRunFrames: Int
    public let activeLevelRangeDecibels: Float
    public let peakFrameDecibels: Float

    public var speechLikeFraction: Double {
        guard frameCount > 0 else { return 0 }
        return Double(speechLikeFrameCount) / Double(frameCount)
    }

    public var hasSustainedSpeech: Bool {
        longestSpeechRunFrames >= 4
            && speechLikeFrameCount >= 4
            && activeLevelRangeDecibels >= 2.5
            && peakFrameDecibels >= -52
    }
}

public struct SpeechEvidenceResult: Equatable, Sendable {
    public let containsSpeech: Bool
    public let analyzedDurationSeconds: Double
    public let speechLikeFrameCount: Int
    public let longestSpeechRunFrames: Int
    public let noiseFloorDecibels: Float
    public let peakFrameDecibels: Float
    public let vadSpeechFrameCount: Int
    public let vadLongestSpeechRunFrames: Int
    public let frameDurationSeconds: Double
    public let speechLikeFrames: [Bool]
    public let frameDecibels: [Float]

    public init(
        containsSpeech: Bool,
        analyzedDurationSeconds: Double,
        speechLikeFrameCount: Int,
        longestSpeechRunFrames: Int,
        noiseFloorDecibels: Float,
        peakFrameDecibels: Float,
        vadSpeechFrameCount: Int = 0,
        vadLongestSpeechRunFrames: Int = 0,
        frameDurationSeconds: Double,
        speechLikeFrames: [Bool],
        frameDecibels: [Float]
    ) {
        self.containsSpeech = containsSpeech
        self.analyzedDurationSeconds = analyzedDurationSeconds
        self.speechLikeFrameCount = speechLikeFrameCount
        self.longestSpeechRunFrames = longestSpeechRunFrames
        self.noiseFloorDecibels = noiseFloorDecibels
        self.peakFrameDecibels = peakFrameDecibels
        self.vadSpeechFrameCount = vadSpeechFrameCount
        self.vadLongestSpeechRunFrames = vadLongestSpeechRunFrames
        self.frameDurationSeconds = frameDurationSeconds
        self.speechLikeFrames = speechLikeFrames
        self.frameDecibels = frameDecibels
    }

    public func evidence(from startSeconds: Double, to endSeconds: Double) -> SpeechIntervalEvidence {
        guard frameDurationSeconds > 0,
              endSeconds > startSeconds,
              !speechLikeFrames.isEmpty else {
            return SpeechIntervalEvidence(
                frameCount: 0,
                speechLikeFrameCount: 0,
                longestSpeechRunFrames: 0,
                activeLevelRangeDecibels: 0,
                peakFrameDecibels: -160
            )
        }
        let lower = max(
            0,
            min(
                speechLikeFrames.count,
                Int(floor(max(0, startSeconds) / frameDurationSeconds))
            )
        )
        let upper = max(
            lower,
            min(
                speechLikeFrames.count,
                Int(ceil(max(0, endSeconds) / frameDurationSeconds))
            )
        )
        var speechCount = 0
        var currentRun = 0
        var longestRun = 0
        var activeLevels: [Float] = []
        for index in lower..<upper {
            let isSpeechLike = speechLikeFrames[index]
            if isSpeechLike {
                speechCount += 1
                currentRun += 1
                longestRun = max(longestRun, currentRun)
                if frameDecibels.indices.contains(index) {
                    activeLevels.append(frameDecibels[index])
                }
            } else {
                currentRun = 0
            }
        }
        let activeRange: Float
        if let minimum = activeLevels.min(), let maximum = activeLevels.max() {
            activeRange = maximum - minimum
        } else {
            activeRange = 0
        }
        return SpeechIntervalEvidence(
            frameCount: upper - lower,
            speechLikeFrameCount: speechCount,
            longestSpeechRunFrames: longestRun,
            activeLevelRangeDecibels: activeRange,
            peakFrameDecibels:
                frameDecibels.indices.contains(lower)
                ? frameDecibels[lower..<upper].max() ?? -160
                : -160
        )
    }
}

public enum LocalSpeechEvidenceAnalyzer {
    private struct VADEvidence {
        let speechFrameCount: Int
        let longestSpeechRunFrames: Int

        func containsSpeech(for duration: Double) -> Bool {
            let minimumSpeechFrames = duration < 0.75 ? 12 : 14
            return speechFrameCount >= minimumSpeechFrames
                && longestSpeechRunFrames >= 12
        }
    }

    private struct Frame {
        let decibels: Float
        let zeroCrossingRate: Float
        let crestFactor: Float
    }

    public static func inspect(_ url: URL) throws -> SpeechEvidenceResult {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0 else {
            return emptyResult
        }

        let capacity: AVAudioFrameCount = 8_192
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: capacity
        ) else {
            return emptyResult
        }
        var samples: [Float] = []
        samples.reserveCapacity(Int(file.length))
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: capacity)
            guard buffer.frameLength > 0,
                  let channels = buffer.floatChannelData else { break }
            let count = Int(buffer.frameLength)
            let channelCount = Int(format.channelCount)
            for index in 0..<count {
                var mixed: Float = 0
                for channel in 0..<channelCount {
                    mixed += channels[channel][index]
                }
                samples.append(mixed / Float(channelCount))
            }
        }
        return analyze(samples: samples, sampleRate: format.sampleRate)
    }

    public static func analyze(
        samples: [Float],
        sampleRate: Double
    ) -> SpeechEvidenceResult {
        guard sampleRate > 0, !samples.isEmpty else { return emptyResult }
        let frameSize = max(80, Int(sampleRate * 0.020))
        guard samples.count >= frameSize else { return emptyResult }

        var frames: [Frame] = []
        frames.reserveCapacity(samples.count / frameSize)
        var offset = 0
        while offset + frameSize <= samples.count {
            let slice = samples[offset..<(offset + frameSize)]
            frames.append(frame(for: slice))
            offset += frameSize
        }
        guard !frames.isEmpty else { return emptyResult }

        let levels = frames.map(\.decibels).sorted()
        let floorIndex = min(levels.count - 1, max(0, levels.count / 5))
        let noiseFloor = levels[floorIndex]
        let activeThreshold = max(-56, noiseFloor + 5.5)

        var speechLikeCount = 0
        var currentRun = 0
        var longestRun = 0
        var activeLevels: [Float] = []
        var speechLikeFrames: [Bool] = []
        var firstSpeechFrameIndex: Int?
        var lastSpeechFrameIndex: Int?
        speechLikeFrames.reserveCapacity(frames.count)
        for (index, frame) in frames.enumerated() {
            let isSpeechLike =
                frame.decibels >= activeThreshold
                && frame.zeroCrossingRate >= 0.006
                && frame.zeroCrossingRate <= 0.34
                && frame.crestFactor <= 11
            speechLikeFrames.append(isSpeechLike)
            if isSpeechLike {
                speechLikeCount += 1
                currentRun += 1
                longestRun = max(longestRun, currentRun)
                activeLevels.append(frame.decibels)
                if firstSpeechFrameIndex == nil {
                    firstSpeechFrameIndex = index
                }
                lastSpeechFrameIndex = index
            } else {
                currentRun = 0
            }
        }

        let activeRange: Float
        if let minimum = activeLevels.min(), let maximum = activeLevels.max() {
            activeRange = maximum - minimum
        } else {
            activeRange = 0
        }
        let peak = levels.last ?? -160
        let duration = Double(samples.count) / sampleRate
        let minimumSpeechFrames = duration < 0.75 ? 12 : 14
        let speechSpanSeconds: Double
        if let firstSpeechFrameIndex, let lastSpeechFrameIndex {
            speechSpanSeconds =
                Double(lastSpeechFrameIndex - firstSpeechFrameIndex + 1)
                * Double(frameSize) / sampleRate
        } else {
            speechSpanSeconds = 0
        }
        let heuristicContainsSpeech =
            longestRun >= 6
            && speechLikeCount >= minimumSpeechFrames
            && speechSpanSeconds >= 0.26
            && activeRange >= 2.5
            && peak >= -52
        let vadEvidence = webRTCEvidence(
            samples: samples,
            sampleRate: sampleRate
        )
        let containsSpeech =
            heuristicContainsSpeech
            && vadEvidence?.containsSpeech(for: duration) == true

        return SpeechEvidenceResult(
            containsSpeech: containsSpeech,
            analyzedDurationSeconds: duration,
            speechLikeFrameCount: speechLikeCount,
            longestSpeechRunFrames: longestRun,
            noiseFloorDecibels: noiseFloor,
            peakFrameDecibels: peak,
            vadSpeechFrameCount: vadEvidence?.speechFrameCount ?? 0,
            vadLongestSpeechRunFrames:
                vadEvidence?.longestSpeechRunFrames ?? 0,
            frameDurationSeconds: Double(frameSize) / sampleRate,
            speechLikeFrames: speechLikeFrames,
            frameDecibels: frames.map(\.decibels)
        )
    }

    private static func webRTCEvidence(
        samples: [Float],
        sampleRate: Double
    ) -> VADEvidence? {
        let targetSampleRate = 16_000
        let frameSize = 320
        let resampled = resample(
            samples,
            from: sampleRate,
            to: Double(targetSampleRate)
        )
        guard resampled.count >= frameSize else { return nil }

        let detector = VoiceActivityDetector()
        do {
            try detector.setSampleRate(sampleRate: targetSampleRate)
            try detector.setMode(mode: .veryAggressive)
        } catch {
            return nil
        }

        var speechFrameCount = 0
        var currentRun = 0
        var longestRun = 0
        var frame = Array(repeating: Int16.zero, count: frameSize)
        var origin = 0
        while origin + frameSize <= resampled.count {
            for offset in 0..<frameSize {
                let sample = max(-1, min(1, resampled[origin + offset]))
                frame[offset] = Int16(
                    (sample * Float(Int16.max)).rounded()
                )
            }
            let isActive: Bool
            do {
                isActive = try frame.withUnsafeBufferPointer { pointer in
                    guard let baseAddress = pointer.baseAddress else {
                        return false
                    }
                    return try detector.process(
                        frame: baseAddress,
                        length: frameSize
                    ) == .activeVoice
                }
            } catch {
                return nil
            }
            if isActive {
                speechFrameCount += 1
                currentRun += 1
                longestRun = max(longestRun, currentRun)
            } else {
                currentRun = 0
            }
            origin += frameSize
        }
        return VADEvidence(
            speechFrameCount: speechFrameCount,
            longestSpeechRunFrames: longestRun
        )
    }

    private static func resample(
        _ samples: [Float],
        from sourceRate: Double,
        to targetRate: Double
    ) -> [Float] {
        guard sourceRate > 0, targetRate > 0, !samples.isEmpty else {
            return []
        }
        if abs(sourceRate - targetRate) < 0.5 {
            return samples
        }
        let outputCount = max(
            1,
            Int((Double(samples.count) * targetRate / sourceRate).rounded())
        )
        guard outputCount > 1, samples.count > 1 else {
            return [samples[0]]
        }
        let sourceScale =
            Double(samples.count - 1) / Double(outputCount - 1)
        return (0..<outputCount).map { outputIndex in
            let sourcePosition = Double(outputIndex) * sourceScale
            let lower = min(samples.count - 1, Int(sourcePosition))
            let upper = min(samples.count - 1, lower + 1)
            let fraction = Float(sourcePosition - Double(lower))
            return samples[lower]
                + ((samples[upper] - samples[lower]) * fraction)
        }
    }

    private static func frame(
        for samples: ArraySlice<Float>
    ) -> Frame {
        var sumSquares: Float = 0
        var peak: Float = 0
        var crossings = 0
        var previous = samples.first ?? 0
        for sample in samples {
            sumSquares += sample * sample
            peak = max(peak, abs(sample))
            if (sample >= 0) != (previous >= 0) {
                crossings += 1
            }
            previous = sample
        }
        let rms = sqrt(sumSquares / Float(samples.count))
        let decibels = max(-160, 20 * log10(max(rms, 0.000_000_01)))
        return Frame(
            decibels: decibels,
            zeroCrossingRate: Float(crossings) / Float(max(1, samples.count - 1)),
            crestFactor: peak / max(rms, 0.000_000_01)
        )
    }

    private static let emptyResult = SpeechEvidenceResult(
        containsSpeech: false,
        analyzedDurationSeconds: 0,
        speechLikeFrameCount: 0,
        longestSpeechRunFrames: 0,
        noiseFloorDecibels: -160,
        peakFrameDecibels: -160,
        vadSpeechFrameCount: 0,
        vadLongestSpeechRunFrames: 0,
        frameDurationSeconds: 0.020,
        speechLikeFrames: [],
        frameDecibels: []
    )
}
