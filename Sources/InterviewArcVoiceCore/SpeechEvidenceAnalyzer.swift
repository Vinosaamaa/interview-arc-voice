@preconcurrency import AVFoundation
import Foundation

public struct SpeechEvidenceResult: Equatable, Sendable {
    public let containsSpeech: Bool
    public let analyzedDurationSeconds: Double
    public let speechLikeFrameCount: Int
    public let longestSpeechRunFrames: Int
    public let noiseFloorDecibels: Float
    public let peakFrameDecibels: Float

    public init(
        containsSpeech: Bool,
        analyzedDurationSeconds: Double,
        speechLikeFrameCount: Int,
        longestSpeechRunFrames: Int,
        noiseFloorDecibels: Float,
        peakFrameDecibels: Float
    ) {
        self.containsSpeech = containsSpeech
        self.analyzedDurationSeconds = analyzedDurationSeconds
        self.speechLikeFrameCount = speechLikeFrameCount
        self.longestSpeechRunFrames = longestSpeechRunFrames
        self.noiseFloorDecibels = noiseFloorDecibels
        self.peakFrameDecibels = peakFrameDecibels
    }
}

public enum LocalSpeechEvidenceAnalyzer {
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
        for frame in frames {
            let isSpeechLike =
                frame.decibels >= activeThreshold
                && frame.zeroCrossingRate >= 0.006
                && frame.zeroCrossingRate <= 0.34
                && frame.crestFactor <= 11
            if isSpeechLike {
                speechLikeCount += 1
                currentRun += 1
                longestRun = max(longestRun, currentRun)
                activeLevels.append(frame.decibels)
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
        let minimumSpeechFrames = duration < 0.75 ? 5 : 7
        let containsSpeech =
            longestRun >= 4
            && speechLikeCount >= minimumSpeechFrames
            && activeRange >= 2.5
            && peak >= -52

        return SpeechEvidenceResult(
            containsSpeech: containsSpeech,
            analyzedDurationSeconds: duration,
            speechLikeFrameCount: speechLikeCount,
            longestSpeechRunFrames: longestRun,
            noiseFloorDecibels: noiseFloor,
            peakFrameDecibels: peak
        )
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
        peakFrameDecibels: -160
    )
}
