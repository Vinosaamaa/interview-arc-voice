import Foundation

public enum SpeechProtectionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case off
    case basic
    case enhanced

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .basic: "Basic"
        case .enhanced: "Enhanced — Experimental"
        }
    }

    public static let defaultsKey = "voice.speechProtectionMode"

    public static func load(from defaults: UserDefaults = .standard) -> SpeechProtectionMode {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let mode = SpeechProtectionMode(rawValue: rawValue) else {
            return .basic
        }
        return mode
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

public struct SpeechProtectedTranscription: Equatable, Sendable {
    public let transcription: TranscriptionResult
    public let omittedUnsupportedSegmentCount: Int
}

public enum SegmentLocalTranscriptValidator {
    private static let segmentPaddingSeconds = 0.15
    private static let maximumLocalSpeechFraction = 0.01
    private static let providerNoSpeechThreshold = 0.60
    private static let providerLogProbabilityThreshold = -1.0

    public static func apply(
        _ transcription: TranscriptionResult,
        speechEvidence: SpeechEvidenceResult,
        mode: SpeechProtectionMode
    ) -> SpeechProtectedTranscription {
        guard mode == .enhanced,
              let segments = transcription.segments,
              !segments.isEmpty,
              segmentsRepresentCompleteTranscript(
                  segments,
                  transcript: transcription.text
              ) else {
            return SpeechProtectedTranscription(
                transcription: transcription,
                omittedUnsupportedSegmentCount: 0
            )
        }

        let rejected = segments.filter { segment in
            isUnsupported(segment, speechEvidence: speechEvidence)
        }
        guard !rejected.isEmpty else {
            return SpeechProtectedTranscription(
                transcription: transcription,
                omittedUnsupportedSegmentCount: 0
            )
        }

        let retainedSegments = segments.filter { candidate in
            !rejected.contains(candidate)
        }
        let retainedWords = transcription.words.filter { word in
            !rejected.contains { segment in
                word.end > segment.start && word.start < segment.end
            }
        }
        let retainedText = retainedSegments
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return SpeechProtectedTranscription(
            transcription: TranscriptionResult(
                text: retainedText,
                words: retainedWords,
                segments: retainedSegments,
                durationSeconds: transcription.durationSeconds,
                chunkCount: transcription.chunkCount,
                timing: transcription.timing
            ),
            omittedUnsupportedSegmentCount: rejected.count
        )
    }

    private static func isUnsupported(
        _ segment: TranscriptSegment,
        speechEvidence: SpeechEvidenceResult
    ) -> Bool {
        guard segment.end > segment.start,
              let noSpeechProbability = segment.noSpeechProbability,
              let averageLogProbability = segment.averageLogProbability,
              noSpeechProbability >= providerNoSpeechThreshold,
              averageLogProbability <= providerLogProbabilityThreshold else {
            return false
        }
        let local = speechEvidence.evidence(
            from: max(0, segment.start - segmentPaddingSeconds),
            to: segment.end + segmentPaddingSeconds
        )
        return !local.hasSustainedSpeech
            && local.speechLikeFraction <= maximumLocalSpeechFraction
    }

    private static func segmentsRepresentCompleteTranscript(
        _ segments: [TranscriptSegment],
        transcript: String
    ) -> Bool {
        normalizedTokens(
            segments.map(\.text).joined(separator: " ")
        ) == normalizedTokens(transcript)
    }

    private static func normalizedTokens(_ value: String) -> [String] {
        value.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
