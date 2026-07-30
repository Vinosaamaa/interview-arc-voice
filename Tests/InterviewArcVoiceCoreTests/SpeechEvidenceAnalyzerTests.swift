import Foundation
import Testing
@testable import InterviewArcVoiceCore

private let testSampleRate = 16_000.0

@Test func digitalSilenceIsRejectedBeforeTranscription() {
    let result = LocalSpeechEvidenceAnalyzer.analyze(
        samples: Array(repeating: 0, count: Int(testSampleRate)),
        sampleRate: testSampleRate
    )

    #expect(!result.containsSpeech)
    #expect(result.speechLikeFrameCount == 0)
    #expect(result.vadSpeechFrameCount == 0)
    #expect(result.vadLongestSpeechRunFrames == 0)
}

@Test func steadyFanLikeHumIsNotMistakenForSpeech() {
    let samples = (0..<Int(testSampleRate * 1.5)).map { index -> Float in
        let time = Double(index) / testSampleRate
        return Float(0.008 * sin(2 * .pi * 110 * time))
    }

    let result = LocalSpeechEvidenceAnalyzer.analyze(
        samples: samples,
        sampleRate: testSampleRate
    )

    #expect(!result.containsSpeech)
    #expect(
        result.vadSpeechFrameCount < 12
            || result.vadLongestSpeechRunFrames < 12
    )
}

@Test func isolatedKeyboardLikeClicksAreRejected() {
    var samples = Array(repeating: Float.zero, count: Int(testSampleRate))
    for origin in [2_000, 6_500, 11_000] {
        for index in 0..<40 {
            samples[origin + index] = index.isMultiple(of: 2) ? 0.7 : -0.7
        }
    }

    let result = LocalSpeechEvidenceAnalyzer.analyze(
        samples: samples,
        sampleRate: testSampleRate
    )

    #expect(!result.containsSpeech)
    #expect(result.longestSpeechRunFrames < 4)
}

@Test func bluetoothProfileTransitionBurstIsRejectedBeforeTranscription() {
    let samples = (0..<Int(testSampleRate)).map { index -> Float in
        let time = Double(index) / testSampleRate
        guard time >= 0.18, time < 0.36 else { return 0 }
        let burstTime = time - 0.18
        let envelope = sin(.pi * burstTime / 0.18)
        let routeTone =
            sin(2 * .pi * (185 + 210 * burstTime) * burstTime)
            + 0.24 * sin(2 * .pi * 740 * burstTime)
        return Float(0.035 * envelope * routeTone)
    }

    let result = LocalSpeechEvidenceAnalyzer.analyze(
        samples: samples,
        sampleRate: testSampleRate
    )

    #expect(!result.containsSpeech)
    #expect(
        result.vadSpeechFrameCount < 12
            || result.vadLongestSpeechRunFrames < 12
    )
}

@Test func shortSoftSpeechShapedCaptureIsAccepted() {
    let samples = (0..<Int(testSampleRate * 0.55)).map { index -> Float in
        let time = Double(index) / testSampleRate
        let envelope = max(0, sin(.pi * time / 0.55))
        let syllables = 0.45 + 0.55 * abs(sin(2 * .pi * 4.2 * time))
        let voiced =
            sin(2 * .pi * 145 * time)
            + 0.38 * sin(2 * .pi * 290 * time)
            + 0.18 * sin(2 * .pi * 435 * time)
        return Float(0.012 * envelope * syllables * voiced)
    }

    let result = LocalSpeechEvidenceAnalyzer.analyze(
        samples: samples,
        sampleRate: testSampleRate
    )

    #expect(result.containsSpeech)
    #expect(result.longestSpeechRunFrames >= 4)
    #expect(result.vadSpeechFrameCount >= 12)
    #expect(result.vadLongestSpeechRunFrames >= 12)
}

@Test func validSpeechAtAirPodsFallbackRateIsAccepted() {
    let sampleRate = 24_000.0
    let samples = speechShapedSamples(
        duration: 0.8,
        sampleRate: sampleRate
    )

    let result = LocalSpeechEvidenceAnalyzer.analyze(
        samples: samples,
        sampleRate: sampleRate
    )

    #expect(result.containsSpeech)
    #expect(result.vadSpeechFrameCount >= 14)
    #expect(result.vadLongestSpeechRunFrames >= 12)
}

@Test func validRecordingRetainsSegmentLocalSpeechEvidence() {
    let firstSpeech = speechShapedSamples(duration: 1.0)
    let thinkingPause = Array(repeating: Float.zero, count: Int(testSampleRate * 2.0))
    let closingSpeech = speechShapedSamples(duration: 1.0)

    let result = LocalSpeechEvidenceAnalyzer.analyze(
        samples: firstSpeech + thinkingPause + closingSpeech,
        sampleRate: testSampleRate
    )

    #expect(result.containsSpeech)
    #expect(result.evidence(from: 0.1, to: 0.9).hasSustainedSpeech)
    #expect(!result.evidence(from: 1.2, to: 2.8).hasSustainedSpeech)
    #expect(result.evidence(from: 3.1, to: 3.9).hasSustainedSpeech)
}

private func speechShapedSamples(
    duration: Double,
    sampleRate: Double = testSampleRate
) -> [Float] {
    (0..<Int(sampleRate * duration)).map { index -> Float in
        let time = Double(index) / sampleRate
        let envelope = max(0, sin(.pi * time / duration))
        let syllables = 0.45 + 0.55 * abs(sin(2 * .pi * 4.2 * time))
        let voiced =
            sin(2 * .pi * 145 * time)
            + 0.38 * sin(2 * .pi * 290 * time)
            + 0.18 * sin(2 * .pi * 435 * time)
        return Float(0.012 * envelope * syllables * voiced)
    }
}
