import AVFoundation
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
}

public struct GroqTranscription: Codable, Equatable, Sendable {
    public let text: String
    public let language: String?
    public let duration: Double?
    public let words: [TranscriptWord]?
    public let segments: [TranscriptSegment]?
}

public struct TranscriptionResult: Codable, Equatable, Sendable {
    public let text: String
    public let words: [TranscriptWord]
    public let durationSeconds: Double
    public let chunkCount: Int
}

public protocol SpeechTranscribing: Sendable {
    func transcribe(fileURL: URL, prompt: String, temporaryDirectory: URL) async throws -> TranscriptionResult
}

public actor GroqTranscriber: SpeechTranscribing {
    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let chunker = AudioChunker()

    public init(apiKey: String, model: String = "whisper-large-v3", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func transcribe(fileURL: URL, prompt: String, temporaryDirectory: URL) async throws -> TranscriptionResult {
        let chunks = try await chunker.chunks(for: fileURL, temporaryDirectory: temporaryDirectory)
        defer {
            for chunk in chunks where chunk.isTemporary {
                try? FileManager.default.removeItem(at: chunk.url)
            }
        }

        let apiKey = self.apiKey
        let model = self.model
        let session = self.session
        let responses = try await withThrowingTaskGroup(of: (AudioChunk, GroqTranscription).self) { group in
            for chunk in chunks {
                group.addTask {
                    let response = try await Self.transcribeChunk(
                        chunk,
                        prompt: prompt,
                        apiKey: apiKey,
                        model: model,
                        session: session
                    )
                    return (chunk, response)
                }
            }
            var result: [(AudioChunk, GroqTranscription)] = []
            for try await response in group { result.append(response) }
            return result.sorted { $0.0.offsetSeconds < $1.0.offsetSeconds }
        }

        let assembled = TranscriptAssembler.assemble(responses)
        guard !assembled.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceBridgeError.emptyTranscript
        }
        return TranscriptionResult(
            text: assembled.text,
            words: assembled.words,
            durationSeconds: responses.last.map { $0.0.offsetSeconds + ($0.1.duration ?? $0.0.durationSeconds) } ?? 0,
            chunkCount: chunks.count
        )
    }

    private static func transcribeChunk(
        _ chunk: AudioChunk,
        prompt: String,
        apiKey: String,
        model: String,
        session: URLSession
    ) async throws -> GroqTranscription {
        let boundary = "InterviewArcGroq-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        var body = Data()
        body.appendGroqField("model", model, boundary: boundary)
        body.appendGroqField("language", "en", boundary: boundary)
        body.appendGroqField("temperature", "0", boundary: boundary)
        body.appendGroqField("response_format", "verbose_json", boundary: boundary)
        body.appendGroqField("timestamp_granularities[]", "word", boundary: boundary)
        body.appendGroqField("timestamp_granularities[]", "segment", boundary: boundary)
        body.appendGroqField("prompt", prompt, boundary: boundary)
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
            throw VoiceBridgeError.invalidResponse(status, String(data: data, encoding: .utf8) ?? "Groq transcription failed")
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

public actor AudioChunker {
    private let directUploadBytes = 23 * 1024 * 1024
    private let overlapSeconds = 1.5

    public init() {}

    public func chunks(for source: URL, temporaryDirectory: URL) async throws -> [AudioChunk] {
        let resource = try source.resourceValues(forKeys: [.fileSizeKey])
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard (resource.fileSize ?? 0) > directUploadBytes else {
            return [AudioChunk(url: source, offsetSeconds: 0, durationSeconds: duration, isTemporary: false)]
        }

        let bytesPerSecond = Double(resource.fileSize ?? directUploadBytes) / max(duration, 1)
        let targetSeconds = min(1_800, max(300, Double(20 * 1024 * 1024) / max(bytesPerSecond, 1)))
        var chunks: [AudioChunk] = []
        var start = 0.0
        var index = 0
        while start < duration {
            let chunkDuration = min(targetSeconds, duration - start)
            let output = temporaryDirectory.appending(path: "\(source.deletingPathExtension().lastPathComponent)-chunk-\(index).m4a")
            try? FileManager.default.removeItem(at: output)
            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw VoiceBridgeError.recordingUnavailable
            }
            export.outputURL = output
            export.outputFileType = .m4a
            export.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                duration: CMTime(seconds: chunkDuration, preferredTimescale: 600)
            )
            try await export.exportInterviewArcChunk()
            chunks.append(AudioChunk(url: output, offsetSeconds: start, durationSeconds: chunkDuration, isTemporary: true))
            if start + chunkDuration >= duration { break }
            start += max(1, chunkDuration - overlapSeconds)
            index += 1
        }
        return chunks
    }
}

private extension AVAssetExportSession {
    func exportInterviewArcChunk() async throws {
        try await withCheckedThrowingContinuation { continuation in
            exportAsynchronously {
                switch self.status {
                case .completed: continuation.resume()
                case .failed: continuation.resume(throwing: self.error ?? VoiceBridgeError.recordingUnavailable)
                case .cancelled: continuation.resume(throwing: CancellationError())
                default: continuation.resume(throwing: self.error ?? VoiceBridgeError.recordingUnavailable)
                }
            }
        }
    }
}

public enum TranscriptAssembler {
    public static func assemble(_ responses: [(AudioChunk, GroqTranscription)]) -> (text: String, words: [TranscriptWord]) {
        var assembledWords: [TranscriptWord] = []
        for (chunk, response) in responses {
            for word in response.words ?? [] {
                let adjusted = TranscriptWord(
                    word: word.word,
                    start: word.start + chunk.offsetSeconds,
                    end: word.end + chunk.offsetSeconds
                )
                if let last = assembledWords.last, adjusted.end <= last.end + 0.2 { continue }
                assembledWords.append(adjusted)
            }
        }
        if !assembledWords.isEmpty {
            let text = assembleWordText(assembledWords.map(\.word))
            return (text, assembledWords)
        }
        var text = ""
        for (_, response) in responses {
            text = appendRemovingOverlap(text, response.text)
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), [])
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

    private static func assembleWordText(_ words: [String]) -> String {
        var result = ""
        let closingPunctuation = CharacterSet(charactersIn: ".,!?;:%)]}\u{2019}\u{201D}")
        let openingPunctuation = CharacterSet(charactersIn: "([{‘}“")

        for rawWord in words {
            let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            guard !result.isEmpty else {
                result = word
                continue
            }

            let firstScalar = word.unicodeScalars.first
            let lastScalar = result.unicodeScalars.last
            let attachesToPrevious = firstScalar.map(closingPunctuation.contains) ?? false
            let previousOpens = lastScalar.map(openingPunctuation.contains) ?? false
            result += attachesToPrevious || previousOpens ? word : " \(word)"
        }
        return result
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
