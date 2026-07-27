import Foundation
import Testing
@testable import InterviewArcVoiceCore

private let protectionSampleRate = 16_000.0

@Test func enhancedProtectionOmitsProviderTextCorroboratedAsSilent() {
    let evidence = LocalSpeechEvidenceAnalyzer.analyze(
        samples:
            protectionSpeech(duration: 1)
            + Array(repeating: Float.zero, count: Int(protectionSampleRate * 2))
            + protectionSpeech(duration: 1),
        sampleRate: protectionSampleRate
    )
    let transcription = TranscriptionResult(
        text: "Opening observation. Thank you. Closing question.",
        words: [
            TranscriptWord(word: "Opening", start: 0.1, end: 0.4),
            TranscriptWord(word: "observation.", start: 0.45, end: 0.9),
            TranscriptWord(word: "Thank", start: 1.5, end: 1.8),
            TranscriptWord(word: "you.", start: 1.85, end: 2.1),
            TranscriptWord(word: "Closing", start: 3.1, end: 3.4),
            TranscriptWord(word: "question.", start: 3.45, end: 3.9),
        ],
        segments: [
            TranscriptSegment(
                start: 0.1,
                end: 0.9,
                text: "Opening observation.",
                averageLogProbability: -0.1,
                compressionRatio: 1.1,
                noSpeechProbability: 0.01
            ),
            TranscriptSegment(
                start: 1.5,
                end: 2.1,
                text: " Thank you.",
                averageLogProbability: -1.4,
                compressionRatio: 1.1,
                noSpeechProbability: 0.97
            ),
            TranscriptSegment(
                start: 3.1,
                end: 3.9,
                text: " Closing question.",
                averageLogProbability: -0.1,
                compressionRatio: 1.1,
                noSpeechProbability: 0.01
            ),
        ],
        durationSeconds: 4,
        chunkCount: 1
    )

    let protected = SegmentLocalTranscriptValidator.apply(
        transcription,
        speechEvidence: evidence,
        mode: .enhanced
    )

    #expect(protected.transcription.text == "Opening observation. Closing question.")
    #expect(protected.transcription.words.map(\.word) == [
        "Opening", "observation.", "Closing", "question.",
    ])
    #expect(protected.omittedUnsupportedSegmentCount == 1)
}

@Test func enhancedProtectionPreservesGenuinelySpokenThankYou() {
    let evidence = LocalSpeechEvidenceAnalyzer.analyze(
        samples: protectionSpeech(duration: 1),
        sampleRate: protectionSampleRate
    )
    let transcription = TranscriptionResult(
        text: "Thank you.",
        words: [
            TranscriptWord(word: "Thank", start: 0.1, end: 0.4),
            TranscriptWord(word: "you.", start: 0.45, end: 0.8),
        ],
        segments: [
            TranscriptSegment(
                start: 0.1,
                end: 0.8,
                text: "Thank you.",
                averageLogProbability: -1.4,
                compressionRatio: 1.1,
                noSpeechProbability: 0.97
            ),
        ],
        durationSeconds: 1,
        chunkCount: 1
    )

    let protected = SegmentLocalTranscriptValidator.apply(
        transcription,
        speechEvidence: evidence,
        mode: .enhanced
    )

    #expect(protected.transcription == transcription)
    #expect(protected.omittedUnsupportedSegmentCount == 0)
}

@Test func enhancedProtectionPreservesProviderConfidentTextAcrossLocalSilence() {
    let evidence = LocalSpeechEvidenceAnalyzer.analyze(
        samples:
            protectionSpeech(duration: 1)
            + Array(repeating: Float.zero, count: Int(protectionSampleRate)),
        sampleRate: protectionSampleRate
    )
    let transcription = TranscriptionResult(
        text: "Opening answer. Quietly transcribed phrase.",
        words: [],
        segments: [
            TranscriptSegment(
                start: 0.1,
                end: 0.8,
                text: "Opening answer.",
                averageLogProbability: -0.1,
                noSpeechProbability: 0.01
            ),
            TranscriptSegment(
                start: 1.2,
                end: 1.8,
                text: " Quietly transcribed phrase.",
                averageLogProbability: -0.2,
                noSpeechProbability: 0.05
            ),
        ],
        durationSeconds: 2,
        chunkCount: 1
    )

    let protected = SegmentLocalTranscriptValidator.apply(
        transcription,
        speechEvidence: evidence,
        mode: .enhanced
    )

    #expect(protected.transcription == transcription)
    #expect(protected.omittedUnsupportedSegmentCount == 0)
}

@Test func enhancedProtectionOmitsMultipleUnsupportedPhrasesAcrossLongAnswerPauses() {
    let evidence = LocalSpeechEvidenceAnalyzer.analyze(
        samples:
            protectionSpeech(duration: 1)
            + Array(repeating: Float.zero, count: Int(protectionSampleRate))
            + protectionSpeech(duration: 1)
            + Array(repeating: Float.zero, count: Int(protectionSampleRate))
            + protectionSpeech(duration: 1),
        sampleRate: protectionSampleRate
    )
    let transcription = TranscriptionResult(
        text: "First point. Thank you. Second point. DynamoDB. Final point.",
        words: [],
        segments: [
            TranscriptSegment(
                start: 0.1,
                end: 0.8,
                text: "First point.",
                averageLogProbability: -0.1,
                noSpeechProbability: 0.01
            ),
            TranscriptSegment(
                start: 1.2,
                end: 1.8,
                text: " Thank you.",
                averageLogProbability: -1.5,
                noSpeechProbability: 0.98
            ),
            TranscriptSegment(
                start: 2.1,
                end: 2.8,
                text: " Second point.",
                averageLogProbability: -0.1,
                noSpeechProbability: 0.01
            ),
            TranscriptSegment(
                start: 3.2,
                end: 3.8,
                text: " DynamoDB.",
                averageLogProbability: -1.6,
                noSpeechProbability: 0.99
            ),
            TranscriptSegment(
                start: 4.1,
                end: 4.8,
                text: " Final point.",
                averageLogProbability: -0.1,
                noSpeechProbability: 0.01
            ),
        ],
        durationSeconds: 5,
        chunkCount: 1
    )

    let protected = SegmentLocalTranscriptValidator.apply(
        transcription,
        speechEvidence: evidence,
        mode: .enhanced
    )

    #expect(protected.transcription.text == "First point. Second point. Final point.")
    #expect(protected.omittedUnsupportedSegmentCount == 2)
}

@Test func steadyBackgroundAudioDoesNotIndependentlyAuthorizeInventedText() {
    let steadyBackground = (0..<Int(protectionSampleRate)).map { index -> Float in
        let time = Double(index) / protectionSampleRate
        return Float(0.008 * sin(2 * .pi * 110 * time))
    }
    let evidence = LocalSpeechEvidenceAnalyzer.analyze(
        samples:
            protectionSpeech(duration: 1)
            + steadyBackground
            + protectionSpeech(duration: 1),
        sampleRate: protectionSampleRate
    )
    let transcription = TranscriptionResult(
        text: "Opening. Thank you. Closing.",
        words: [],
        segments: [
            TranscriptSegment(
                start: 0.1,
                end: 0.8,
                text: "Opening.",
                averageLogProbability: -0.1,
                noSpeechProbability: 0.01
            ),
            TranscriptSegment(
                start: 1.2,
                end: 1.8,
                text: " Thank you.",
                averageLogProbability: -1.5,
                noSpeechProbability: 0.98
            ),
            TranscriptSegment(
                start: 2.1,
                end: 2.8,
                text: " Closing.",
                averageLogProbability: -0.1,
                noSpeechProbability: 0.01
            ),
        ],
        durationSeconds: 3,
        chunkCount: 1
    )

    let protected = SegmentLocalTranscriptValidator.apply(
        transcription,
        speechEvidence: evidence,
        mode: .enhanced
    )

    #expect(protected.transcription.text == "Opening. Closing.")
    #expect(protected.omittedUnsupportedSegmentCount == 1)
}

@Test func basicProtectionLeavesSegmentLocalProviderOutputUntouched() {
    let evidence = LocalSpeechEvidenceAnalyzer.analyze(
        samples: Array(repeating: Float.zero, count: Int(protectionSampleRate)),
        sampleRate: protectionSampleRate
    )
    let transcription = TranscriptionResult(
        text: "Thank you.",
        words: [],
        segments: [
            TranscriptSegment(
                start: 0,
                end: 1,
                text: "Thank you.",
                averageLogProbability: -2,
                noSpeechProbability: 0.99
            ),
        ],
        durationSeconds: 1,
        chunkCount: 1
    )

    let protected = SegmentLocalTranscriptValidator.apply(
        transcription,
        speechEvidence: evidence,
        mode: .basic
    )

    #expect(protected.transcription == transcription)
    #expect(protected.omittedUnsupportedSegmentCount == 0)
}

@Test func speechProtectionModeDefaultsToBasicAndPersistsEnhancedSelection() {
    let suiteName = "SpeechProtectionTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(SpeechProtectionMode.load(from: defaults) == .basic)

    SpeechProtectionMode.enhanced.save(to: defaults)

    #expect(SpeechProtectionMode.load(from: defaults) == .enhanced)
}

@Test func enhancedReliableTranscriptionUsesOneProviderCallAndReturnsProtectedText() async throws {
    let evidence = LocalSpeechEvidenceAnalyzer.analyze(
        samples:
            protectionSpeech(duration: 1)
            + Array(repeating: Float.zero, count: Int(protectionSampleRate)),
        sampleRate: protectionSampleRate
    )
    let provider = SpeechProtectionCountingTranscriber(
        result: TranscriptionResult(
            text: "Real answer. Thank you.",
            words: [],
            segments: [
                TranscriptSegment(
                    start: 0.1,
                    end: 0.8,
                    text: "Real answer.",
                    averageLogProbability: -0.1,
                    noSpeechProbability: 0.01
                ),
                TranscriptSegment(
                    start: 1.2,
                    end: 1.8,
                    text: " Thank you.",
                    averageLogProbability: -1.5,
                    noSpeechProbability: 0.98
                ),
            ],
            durationSeconds: 2,
            chunkCount: 1
        )
    )
    let reliable = ReliableSpeechTranscriber(base: provider)

    let result = try await reliable.transcribe(
        fileURL: URL(fileURLWithPath: "/tmp/answer.m4a"),
        prompt: "",
        temporaryDirectory: URL(fileURLWithPath: "/tmp"),
        audioDurationSeconds: 2,
        speechEvidence: evidence,
        protectionMode: .enhanced
    )

    #expect(result.transcription.text == "Real answer.")
    #expect(result.omittedUnsupportedSegmentCount == 1)
    #expect(result.segmentValidationSeconds >= 0)
    #expect(await provider.callCount == 1)
}

@Test func enhancedProtectionDoesNotRewriteTranscriptFromIncompleteSegments() {
    let evidence = LocalSpeechEvidenceAnalyzer.analyze(
        samples:
            protectionSpeech(duration: 1)
            + Array(repeating: Float.zero, count: Int(protectionSampleRate)),
        sampleRate: protectionSampleRate
    )
    let transcription = TranscriptionResult(
        text: "Real answer. Thank you. Closing marker omega.",
        words: [],
        segments: [
            TranscriptSegment(
                start: 0.1,
                end: 0.8,
                text: "Real answer.",
                averageLogProbability: -0.1,
                noSpeechProbability: 0.01
            ),
            TranscriptSegment(
                start: 1.2,
                end: 1.8,
                text: " Thank you.",
                averageLogProbability: -1.5,
                noSpeechProbability: 0.98
            ),
        ],
        durationSeconds: 2,
        chunkCount: 1
    )

    let protected = SegmentLocalTranscriptValidator.apply(
        transcription,
        speechEvidence: evidence,
        mode: .enhanced
    )

    #expect(protected.transcription == transcription)
    #expect(protected.omittedUnsupportedSegmentCount == 0)
}

@Test func groqVerboseJSONRetainsSegmentSilenceAndConfidenceMetadata() throws {
    let payload = Data(
        """
        {
          "text": "Thank you.",
          "language": "en",
          "duration": 2.0,
          "words": [],
          "segments": [{
            "start": 0.5,
            "end": 1.4,
            "text": "Thank you.",
            "avg_logprob": -1.42,
            "compression_ratio": 1.08,
            "no_speech_prob": 0.96
          }]
        }
        """.utf8
    )

    let decoded = try JSONDecoder().decode(GroqTranscription.self, from: payload)
    let segment = try #require(decoded.segments?.first)

    #expect(segment.averageLogProbability == -1.42)
    #expect(segment.compressionRatio == 1.08)
    #expect(segment.noSpeechProbability == 0.96)
}

@Test func transcriptAssemblerOffsetsSegmentEvidenceWithItsAudioChunk() throws {
    let chunk = AudioChunk(
        url: URL(fileURLWithPath: "/tmp/chunk.m4a"),
        offsetSeconds: 30,
        durationSeconds: 10,
        isTemporary: true
    )
    let response = GroqTranscription(
        text: "Thank you.",
        language: "en",
        duration: 10,
        words: nil,
        segments: [
            TranscriptSegment(
                start: 2,
                end: 3,
                text: "Thank you.",
                averageLogProbability: -1.4,
                noSpeechProbability: 0.96
            ),
        ]
    )

    let assembled = TranscriptAssembler.assemble([(chunk, response)])
    let segment = try #require(assembled.segments.first)

    #expect(segment.start == 32)
    #expect(segment.end == 33)
    #expect(segment.noSpeechProbability == 0.96)
}

@Test func savedTranscriptionWithoutNewOptionalFieldsStillDecodes() throws {
    let payload = Data(
        """
        {
          "text": "Existing pending transcript.",
          "words": [],
          "durationSeconds": 4.0,
          "chunkCount": 1
        }
        """.utf8
    )

    let decoded = try JSONDecoder().decode(TranscriptionResult.self, from: payload)

    #expect(decoded.text == "Existing pending transcript.")
    #expect(decoded.segments == nil)
    #expect(decoded.timing == nil)
}

private func protectionSpeech(duration: Double) -> [Float] {
    (0..<Int(protectionSampleRate * duration)).map { index -> Float in
        let time = Double(index) / protectionSampleRate
        let envelope = max(0, sin(.pi * time / duration))
        let syllables = 0.45 + 0.55 * abs(sin(2 * .pi * 4.2 * time))
        let voiced =
            sin(2 * .pi * 145 * time)
            + 0.38 * sin(2 * .pi * 290 * time)
            + 0.18 * sin(2 * .pi * 435 * time)
        return Float(0.012 * envelope * syllables * voiced)
    }
}

private actor SpeechProtectionCountingTranscriber: SpeechTranscribing {
    private let result: TranscriptionResult
    private(set) var callCount = 0

    init(result: TranscriptionResult) {
        self.result = result
    }

    func transcribe(
        fileURL: URL,
        prompt: String,
        temporaryDirectory: URL
    ) async throws -> TranscriptionResult {
        callCount += 1
        return result
    }
}
