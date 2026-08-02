import Foundation

/// Aggregate-only evidence from an explicit native WhisperKit replay.
///
/// This type deliberately cannot carry transcript text, audio bytes, prompt
/// text, or filesystem paths so local verification output stays public-safe.
public struct LocalWhisperVerificationReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let engine: String
    public let model: String
    public let audioDurationSeconds: Double
    public let transcriptWordCount: Int
    public let timestampWordCount: Int
    public let segmentCount: Int
    public let lexicalCoverageEndSeconds: Double
    public let localInferenceMilliseconds: Int
    public let promptConditioningUsed: Bool
    public let promptTokenCount: Int

    public init(
        result: ArcTranscriptionResult,
        audioDurationSeconds: Double
    ) {
        schemaVersion = 1
        engine = result.engine ?? "unknown"
        model = result.model ?? "unknown"
        self.audioDurationSeconds = max(0, audioDurationSeconds)
        transcriptWordCount = result.text.split(whereSeparator: { $0.isWhitespace }).count
        timestampWordCount = result.words.count
        segmentCount = result.segments?.count ?? 0
        lexicalCoverageEndSeconds = result.words
            .map(\.end)
            .filter { $0.isFinite && $0 >= 0 }
            .max() ?? 0
        localInferenceMilliseconds = max(
            0,
            Int(((result.localInferenceSeconds ?? 0) * 1_000).rounded())
        )
        promptTokenCount = max(0, result.localPromptTokenCount ?? 0)
        promptConditioningUsed = promptTokenCount > 0
    }
}
