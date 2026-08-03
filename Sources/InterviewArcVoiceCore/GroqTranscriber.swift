@preconcurrency import AVFoundation
import Foundation

public struct TranscriptWord: Codable, Equatable, Sendable {
    public let word: String
    public let start: Double
    public let end: Double
}

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double
    public let text: String
    public let averageLogProbability: Double?
    public let compressionRatio: Double?
    public let noSpeechProbability: Double?

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case text
        case averageLogProbability = "avg_logprob"
        case compressionRatio = "compression_ratio"
        case noSpeechProbability = "no_speech_prob"
    }

    public init(
        start: Double,
        end: Double,
        text: String,
        averageLogProbability: Double? = nil,
        compressionRatio: Double? = nil,
        noSpeechProbability: Double? = nil
    ) {
        self.start = start
        self.end = end
        self.text = text
        self.averageLogProbability = averageLogProbability
        self.compressionRatio = compressionRatio
        self.noSpeechProbability = noSpeechProbability
    }
}

public struct GroqTranscription: Codable, Equatable, Sendable {
    public let text: String
    public let language: String?
    public let duration: Double?
    public let words: [TranscriptWord]?
    public let segments: [TranscriptSegment]?
}

public struct TranscriptionTiming: Codable, Equatable, Sendable {
    public let chunkPreparationSeconds: Double
    public let providerWaitSeconds: Double
    public let responseProcessingSeconds: Double

    public init(
        chunkPreparationSeconds: Double,
        providerWaitSeconds: Double,
        responseProcessingSeconds: Double
    ) {
        self.chunkPreparationSeconds = chunkPreparationSeconds
        self.providerWaitSeconds = providerWaitSeconds
        self.responseProcessingSeconds = responseProcessingSeconds
    }
}

public struct TranscriptionResult: Codable, Equatable, Sendable {
    public let text: String
    public let words: [TranscriptWord]
    public let segments: [TranscriptSegment]?
    public let durationSeconds: Double
    public let chunkCount: Int
    public let timing: TranscriptionTiming?
    public let engine: String?
    public let model: String?
    public let localInferenceSeconds: Double?
    public let localPromptTokenCount: Int?

    public init(
        text: String,
        words: [TranscriptWord],
        segments: [TranscriptSegment]? = nil,
        durationSeconds: Double,
        chunkCount: Int,
        timing: TranscriptionTiming? = nil,
        engine: String? = nil,
        model: String? = nil,
        localInferenceSeconds: Double? = nil,
        localPromptTokenCount: Int? = nil
    ) {
        self.text = text
        self.words = words
        self.segments = segments
        self.durationSeconds = durationSeconds
        self.chunkCount = chunkCount
        self.timing = timing
        self.engine = engine
        self.model = model
        self.localInferenceSeconds = localInferenceSeconds
        self.localPromptTokenCount = localPromptTokenCount
    }
}

public typealias ArcTranscriptionResult = TranscriptionResult

public enum GroqProviderFailurePolicy {
    private struct FailureEnvelope: Decodable {
        struct Failure: Decodable {
            let type: String?
            let code: String?
        }

        let error: Failure?
    }

    public static func error(
        statusCode: Int,
        responseData: Data
    ) -> VoiceBridgeError {
        if statusCode == 401 {
            return .invalidProviderCredential
        }
        if statusCode == 403 {
            let failure = try? JSONDecoder().decode(
                FailureEnvelope.self,
                from: responseData
            ).error
            return .providerPermissionDenied(
                safeIdentifier(failure?.code ?? failure?.type)
            )
        }
        return .invalidResponse(statusCode, "Groq transcription failed")
    }

    private static func safeIdentifier(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        var result = ""
        for scalar in rawValue.unicodeScalars {
            let value = scalar.value
            let isASCIIAlphaNumeric = (48...57).contains(value)
                || (65...90).contains(value)
                || (97...122).contains(value)
            let isSafeSeparator = value == 45 || value == 46 || value == 95
            guard isASCIIAlphaNumeric || isSafeSeparator else { continue }
            result.unicodeScalars.append(scalar)
            if result.count == 80 { break }
        }
        return result.isEmpty ? nil : result
    }
}

public protocol SpeechTranscribing: Sendable {
    var diagnosticEngine: String { get }
    var diagnosticModel: String? { get }
    var isReadyForImmediateTranscription: Bool { get }
    func transcribe(fileURL: URL, prompt: String, temporaryDirectory: URL) async throws -> TranscriptionResult
    func transcribeCoverageRecovery(
        fileURL: URL,
        temporaryDirectory: URL
    ) async throws -> TranscriptionResult
}

public extension SpeechTranscribing {
    var diagnosticEngine: String { "unknown" }
    var diagnosticModel: String? { nil }
    var isReadyForImmediateTranscription: Bool { true }

    func transcribeCoverageRecovery(
        fileURL: URL,
        temporaryDirectory: URL
    ) async throws -> TranscriptionResult {
        try await transcribe(
            fileURL: fileURL,
            prompt: "",
            temporaryDirectory: temporaryDirectory
        )
    }
}

public actor GroqTranscriber: SpeechTranscribing {
    public nonisolated let diagnosticEngine = "groq"
    public nonisolated let diagnosticModel: String?
    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let chunker = AudioChunker()

    public init(apiKey: String, model: String = "whisper-large-v3", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        diagnosticModel = model
        self.session = session
    }

    public func transcribe(fileURL: URL, prompt: String, temporaryDirectory: URL) async throws -> TranscriptionResult {
        try await transcribe(
            fileURL: fileURL,
            prompt: prompt,
            temporaryDirectory: temporaryDirectory,
            chunkingPolicy: .providerLimit
        )
    }

    public func transcribeCoverageRecovery(
        fileURL: URL,
        temporaryDirectory: URL
    ) async throws -> TranscriptionResult {
        try await transcribe(
            fileURL: fileURL,
            prompt: "",
            temporaryDirectory: temporaryDirectory,
            chunkingPolicy: .coverageRecovery
        )
    }

    private func transcribe(
        fileURL: URL,
        prompt: String,
        temporaryDirectory: URL,
        chunkingPolicy: AudioChunkingPolicy
    ) async throws -> TranscriptionResult {
        let chunkPreparationStartedAt = Date()
        let chunks = try await chunker.chunks(
            for: fileURL,
            temporaryDirectory: temporaryDirectory,
            policy: chunkingPolicy
        )
        let chunkPreparationSeconds = Date().timeIntervalSince(chunkPreparationStartedAt)
        defer {
            for chunk in chunks where chunk.isTemporary {
                try? FileManager.default.removeItem(at: chunk.url)
            }
        }

        let apiKey = self.apiKey
        let model = self.model
        let session = self.session
        let providerStartedAt = Date()
        var responses = try await withThrowingTaskGroup(
            of: (AudioChunk, GroqTranscription).self
        ) { group in
            let maximumConcurrentRequests = min(
                chunkingPolicy.maximumConcurrentRequests,
                chunks.count
            )
            for chunk in chunks.prefix(maximumConcurrentRequests) {
                group.addTask {
                    let response = try await Self.transcribeChunk(
                        chunk,
                        prompt: prompt,
                        apiKey: apiKey,
                        model: model,
                        session: session,
                        timeoutInterval:
                            chunkingPolicy.requestTimeoutInterval
                    )
                    return (chunk, response)
                }
            }

            var nextChunkIndex = maximumConcurrentRequests
            var result: [(AudioChunk, GroqTranscription)] = []
            while let response = try await group.next() {
                result.append(response)
                if nextChunkIndex < chunks.count {
                    let chunk = chunks[nextChunkIndex]
                    nextChunkIndex += 1
                    group.addTask {
                        let response = try await Self.transcribeChunk(
                            chunk,
                            prompt: prompt,
                            apiKey: apiKey,
                            model: model,
                            session: session,
                            timeoutInterval:
                                chunkingPolicy.requestTimeoutInterval
                        )
                        return (chunk, response)
                    }
                }
            }
            return result
        }
        responses.sort { $0.0.offsetSeconds < $1.0.offsetSeconds }
        let providerWaitSeconds = Date().timeIntervalSince(providerStartedAt)

        let responseProcessingStartedAt = Date()
        let assembled = TranscriptAssembler.assemble(responses)
        guard !assembled.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceBridgeError.emptyTranscript
        }
        let responseProcessingSeconds = Date().timeIntervalSince(responseProcessingStartedAt)
        return TranscriptionResult(
            text: assembled.text,
            words: assembled.words,
            segments: assembled.segments,
            durationSeconds: responses.last.map { $0.0.offsetSeconds + ($0.1.duration ?? $0.0.durationSeconds) } ?? 0,
            chunkCount: chunks.count,
            timing: TranscriptionTiming(
                chunkPreparationSeconds: chunkPreparationSeconds,
                providerWaitSeconds: providerWaitSeconds,
                responseProcessingSeconds: responseProcessingSeconds
            ),
            engine: "groq",
            model: model
        )
    }

    private static func transcribeChunk(
        _ chunk: AudioChunk,
        prompt: String,
        apiKey: String,
        model: String,
        session: URLSession,
        timeoutInterval: TimeInterval
    ) async throws -> GroqTranscription {
        let boundary = "InterviewArcGroq-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeoutInterval

        var body = Data()
        body.appendGroqField("model", model, boundary: boundary)
        body.appendGroqField("language", "en", boundary: boundary)
        body.appendGroqField("temperature", "0", boundary: boundary)
        body.appendGroqField("response_format", "verbose_json", boundary: boundary)
        body.appendGroqField("timestamp_granularities[]", "word", boundary: boundary)
        body.appendGroqField("timestamp_granularities[]", "segment", boundary: boundary)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            body.appendGroqField("prompt", trimmedPrompt, boundary: boundary)
        }
        body.appendGroqFile(
            filename: chunk.url.lastPathComponent,
            mimeType: "audio/mp4",
            data: try Data(contentsOf: chunk.url, options: .mappedIfSafe),
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (data, response) = try await session.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw GroqProviderFailurePolicy.error(
                statusCode: status,
                responseData: data
            )
        }
        return try JSONDecoder().decode(GroqTranscription.self, from: data)
    }

}

public struct AudioChunk: Equatable, Sendable {
    public let url: URL
    public let offsetSeconds: Double
    public let durationSeconds: Double
    public let isTemporary: Bool
}

struct AudioChunkWindow: Equatable, Sendable {
    let startSeconds: Double
    let durationSeconds: Double

    init(startSeconds: Double, durationSeconds: Double) {
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
    }
}

public enum AudioChunkingPolicy: Sendable {
    case providerLimit
    case coverageRecovery

    var maximumConcurrentRequests: Int {
        switch self {
        case .providerLimit: 1
        case .coverageRecovery: 4
        }
    }

    var requestTimeoutInterval: TimeInterval {
        switch self {
        case .providerLimit: 20
        case .coverageRecovery: 8
        }
    }
}

enum AudioChunkPlan {
    private static let directUploadBytes = 23 * 1024 * 1024
    private static let targetUploadBytes = 20 * 1024 * 1024
    private static let overlapSeconds = 1.5

    static func windows(
        durationSeconds: Double,
        fileSizeBytes: Int
    ) -> [AudioChunkWindow] {
        guard durationSeconds > 0 else { return [] }

        // Groq accepts the complete recording and Whisper handles its own
        // acoustic context internally. Splitting every recording at 30 seconds
        // creates unnecessary provider calls and can silently lose an ending
        // when one otherwise-successful chunk returns incomplete text.
        // Only split when the encoded file approaches the upload limit.
        if fileSizeBytes <= directUploadBytes {
            return [
                AudioChunkWindow(
                    startSeconds: 0,
                    durationSeconds: durationSeconds
                ),
            ]
        }

        let bytesPerSecond = Double(fileSizeBytes) / max(durationSeconds, 1)
        let sizeBoundSeconds = Double(targetUploadBytes) / max(bytesPerSecond, 1)
        let maximumChunkSeconds = max(
            overlapSeconds + 1,
            sizeBoundSeconds
        )
        let strideSeconds = maximumChunkSeconds - overlapSeconds
        let chunkCount = max(
            2,
            Int(ceil((durationSeconds - overlapSeconds) / strideSeconds))
        )
        let balancedChunkSeconds =
            (durationSeconds + overlapSeconds * Double(chunkCount - 1))
            / Double(chunkCount)
        let balancedStrideSeconds = balancedChunkSeconds - overlapSeconds

        return (0..<chunkCount).map { index in
            AudioChunkWindow(
                startSeconds: Double(index) * balancedStrideSeconds,
                durationSeconds: balancedChunkSeconds
            )
        }
    }

    static func coverageRecoveryWindows(
        durationSeconds: Double
    ) -> [AudioChunkWindow] {
        guard durationSeconds > 0 else { return [] }
        let targetSeconds = 30.0
        let strideSeconds = targetSeconds - overlapSeconds
        var windows: [AudioChunkWindow] = []
        var start = 0.0
        while start < durationSeconds {
            let duration = min(targetSeconds, durationSeconds - start)
            windows.append(AudioChunkWindow(
                startSeconds: start,
                durationSeconds: duration
            ))
            guard start + duration < durationSeconds else { break }
            start += strideSeconds
        }
        return windows
    }
}

public actor AudioChunker {
    public init() {}

    public func chunks(
        for source: URL,
        temporaryDirectory: URL,
        policy: AudioChunkingPolicy = .providerLimit
    ) async throws -> [AudioChunk] {
        let resource = try source.resourceValues(forKeys: [.fileSizeKey])
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let windows: [AudioChunkWindow]
        switch policy {
        case .providerLimit:
            windows = AudioChunkPlan.windows(
                durationSeconds: duration,
                fileSizeBytes: resource.fileSize ?? 0
            )
        case .coverageRecovery:
            windows = AudioChunkPlan.coverageRecoveryWindows(
                durationSeconds: duration
            )
        }
        guard windows.count > 1 else {
            return [AudioChunk(url: source, offsetSeconds: 0, durationSeconds: duration, isTemporary: false)]
        }

        var chunks: [AudioChunk] = []
        for (index, window) in windows.enumerated() {
            let output = temporaryDirectory.appending(path: "\(source.deletingPathExtension().lastPathComponent)-chunk-\(index).m4a")
            try? FileManager.default.removeItem(at: output)
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw VoiceBridgeError.recordingUnavailable
            }
            export.outputURL = output
            export.outputFileType = .m4a
            export.timeRange = CMTimeRange(
                start: CMTime(seconds: window.startSeconds, preferredTimescale: 600),
                duration: CMTime(seconds: window.durationSeconds, preferredTimescale: 600)
            )
            try await export.exportInterviewArcChunk()
            chunks.append(
                AudioChunk(
                    url: output,
                    offsetSeconds: window.startSeconds,
                    durationSeconds: window.durationSeconds,
                    isTemporary: true
                )
            )
        }
        return chunks
    }
}

private extension AVAssetExportSession {
    func exportInterviewArcChunk() async throws {
        let box = ExportSessionBox(self)
        try await withCheckedThrowingContinuation { continuation in
            box.session.exportAsynchronously {
                switch box.session.status {
                case .completed: continuation.resume()
                case .failed: continuation.resume(throwing: box.session.error ?? VoiceBridgeError.recordingUnavailable)
                case .cancelled: continuation.resume(throwing: CancellationError())
                default: continuation.resume(throwing: box.session.error ?? VoiceBridgeError.recordingUnavailable)
                }
            }
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

public enum TranscriptAssembler {
    public static func assemble(
        _ responses: [(AudioChunk, GroqTranscription)]
    ) -> (text: String, words: [TranscriptWord], segments: [TranscriptSegment]) {
        var assembledWords: [TranscriptWord] = []
        for (chunk, response) in responses {
            let previousChunkEnd = assembledWords.last?.end
            for word in response.words ?? [] {
                let adjusted = TranscriptWord(
                    word: word.word,
                    start: word.start + chunk.offsetSeconds,
                    end: word.end + chunk.offsetSeconds
                )
                if chunk.offsetSeconds > 0,
                   let previousChunkEnd,
                   adjusted.end <= previousChunkEnd + 0.2 {
                    continue
                }
                assembledWords.append(adjusted)
            }
        }

        var assembledSegments: [TranscriptSegment] = []
        for (chunk, response) in responses {
            let previousChunkEnd = assembledSegments.last?.end
            for segment in response.segments ?? [] {
                let adjusted = TranscriptSegment(
                    start: segment.start + chunk.offsetSeconds,
                    end: segment.end + chunk.offsetSeconds,
                    text: segment.text,
                    averageLogProbability: segment.averageLogProbability,
                    compressionRatio: segment.compressionRatio,
                    noSpeechProbability: segment.noSpeechProbability
                )
                if chunk.offsetSeconds > 0,
                   let previousChunkEnd,
                   adjusted.end <= previousChunkEnd + 0.2 {
                    continue
                }
                assembledSegments.append(adjusted)
            }
        }

        // Groq's top-level `text` is the canonical transcription. Word
        // timestamps are a separate alignment product and can be sparse near
        // pauses or at the end of a long recording. Rebuilding user-visible
        // prose from that alignment silently truncated otherwise complete
        // transcripts. Keep aligned words for delivery coaching, but assemble
        // the verbatim transcript from each chunk's complete text.
        var text = ""
        for (_, response) in responses {
            text = appendRemovingOverlap(text, response.text)
        }
        return (
            text.trimmingCharacters(in: .whitespacesAndNewlines),
            assembledWords,
            assembledSegments
        )
    }

    private static func appendRemovingOverlap(_ current: String, _ next: String) -> String {
        let left = current.split(separator: " ")
        let right = next.split(separator: " ")
        let limit = min(30, left.count, right.count)
        var overlap = 0
        if limit > 0 {
            for count in stride(from: limit, through: 1, by: -1) {
                let leftTail = left.suffix(count).map(normalize)
                let rightHead = right.prefix(count).map(normalize)
                if leftTail == rightHead { overlap = count; break }
            }
        }
        return (left + right.dropFirst(overlap)).joined(separator: " ")
    }

    private static func normalize(_ value: Substring) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

}

private extension Data {
    mutating func appendGroqField(_ name: String, _ value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendGroqFile(filename: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
