import Foundation
@preconcurrency import WhisperKit

public enum LocalWhisperPromptFileError: Error, Equatable, Sendable {
    case oversized
}

/// Reads at most one byte beyond the supported prompt limit so an arbitrary
/// local file cannot be fully allocated before it is rejected.
public func loadBoundedLocalWhisperPrompt(
    from url: URL,
    maximumByteCount: Int = 65_536
) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maximumByteCount + 1) ?? Data()
    guard data.count <= maximumByteCount else {
        throw LocalWhisperPromptFileError.oversized
    }
    return String(decoding: data, as: UTF8.self)
}

/// Stable, content-free categories for native replay failures.
public enum LocalWhisperVerificationFailureCode: String, Sendable {
    case modelUnavailable = "model-unavailable"
    case modelCorrupt = "model-corrupt"
    case installationInProgress = "installation-in-progress"
    case unsafeModelPath = "unsafe-model-path"
    case emptyTranscript = "empty-transcript"
    case tokenizerUnavailable = "tokenizer-unavailable"
    case modelsUnavailable = "models-unavailable"
    case audioProcessingFailed = "audio-processing-failed"
    case decodingLogitsFailed = "decoding-logits-failed"
    case segmentingFailed = "segmenting-failed"
    case loadAudioFailed = "load-audio-failed"
    case prepareDecoderInputsFailed = "prepare-decoder-inputs-failed"
    case transcriptionFailed = "transcription-failed"
    case decodingFailed = "decoding-failed"
    case microphoneUnavailable = "microphone-unavailable"
    case initializationFailed = "initialization-failed"
    case fileSystemFailed = "filesystem-failed"
    case unknown = "unknown"
}

/// Converts third-party/local errors into bounded categories without exposing
/// localized messages, filenames, prompts, or transcript content.
public func localWhisperVerificationFailureCode(
    for error: Error
) -> LocalWhisperVerificationFailureCode {
    if let local = error as? LocalWhisperModelError {
        switch local {
        case .unavailable: return .modelUnavailable
        case .corrupt: return .modelCorrupt
        case .installationInProgress: return .installationInProgress
        case .unsafeModelPath: return .unsafeModelPath
        case .emptyTranscript: return .emptyTranscript
        }
    }
    if let whisper = error as? WhisperError {
        switch whisper {
        case .tokenizerUnavailable: return .tokenizerUnavailable
        case .modelsUnavailable: return .modelsUnavailable
        case .audioProcessingFailed: return .audioProcessingFailed
        case .decodingLogitsFailed: return .decodingLogitsFailed
        case .segmentingFailed: return .segmentingFailed
        case .loadAudioFailed: return .loadAudioFailed
        case .prepareDecoderInputsFailed: return .prepareDecoderInputsFailed
        case .transcriptionFailed: return .transcriptionFailed
        case .decodingFailed: return .decodingFailed
        case .microphoneUnavailable: return .microphoneUnavailable
        case .initializationError: return .initializationFailed
        }
    }
    if error is CocoaError { return .fileSystemFailed }
    return .unknown
}

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
