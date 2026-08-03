import CryptoKit
import Foundation
@preconcurrency import WhisperKit

public enum LocalWhisperModelState: String, Codable, Equatable, Sendable {
    case notInstalled
    case installing
    case available
    case corrupt
}

public struct LocalWhisperModelSnapshot: Codable, Equatable, Sendable {
    public let state: LocalWhisperModelState
    public let model: String
    public let sizeBytes: Int64?
    public let detail: String?

    public init(
        state: LocalWhisperModelState,
        model: String,
        sizeBytes: Int64? = nil,
        detail: String? = nil
    ) {
        self.state = state
        self.model = model
        self.sizeBytes = sizeBytes
        self.detail = detail
    }
}

public enum LocalWhisperModelError: LocalizedError, Sendable, Equatable {
    case unavailable
    case corrupt
    case installationInProgress
    case unsafeModelPath
    case emptyTranscript

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "The optional local Whisper recovery model is not installed."
        case .corrupt:
            "The local Whisper recovery model failed its integrity check. Delete and reinstall it in Settings."
        case .installationInProgress:
            "The local Whisper recovery model is still installing."
        case .unsafeModelPath:
            "The local Whisper model location is outside app-owned storage."
        case .emptyTranscript:
            "Local Whisper did not return any transcript text."
        }
    }
}

/// Produces deterministic, bounded decoder-conditioning tokens without ever
/// persisting or logging the vocabulary prompt itself.
public enum LocalWhisperPromptPolicy {
    public static let maximumTokenCount = 180

    public static func shouldRetryWithoutConditioning(
        transcript: String,
        forPromptTokens promptTokens: [Int]
    ) -> Bool {
        !promptTokens.isEmpty
            && transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func normalizedPrompt(_ prompt: String) -> String {
        let collapsed = prompt
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return "" }
        return " " + collapsed
    }

    public static func boundedTokens(
        for prompt: String,
        encode: (String) -> [Int]
    ) -> [Int] {
        let normalized = normalizedPrompt(prompt)
        guard !normalized.isEmpty else { return [] }
        return Array(encode(normalized).suffix(maximumTokenCount))
    }
}

private struct LocalWhisperModelManifest: Codable, Equatable, Sendable {
    struct FileEntry: Codable, Equatable, Sendable {
        let relativePath: String
        let sizeBytes: Int64
        let sha256: String
    }

    let schemaVersion: Int
    let runtimeVersion: String
    let model: String
    let modelRelativePath: String
    let installedAt: Date
    let files: [FileEntry]

    var sizeBytes: Int64 {
        files.reduce(0) { $0 + $1.sizeBytes }
    }
}

private final class LocalWhisperReadiness: @unchecked Sendable {
    private let lock = NSLock()
    private var prepared = false

    var isPrepared: Bool {
        lock.lock()
        defer { lock.unlock() }
        return prepared
    }

    func setPrepared(_ value: Bool) {
        lock.lock()
        prepared = value
        lock.unlock()
    }
}

public actor LocalWhisperModelManager {
    public static let defaultModel = "base.en"
    public static let runtimeVersion = "argmax-oss-swift-1.0.0"

    private let rootDirectory: URL
    private let manifestURL: URL
    private let model: String
    private let fileManager: FileManager
    private var installationInProgress = false
    private var verifiedManifest: LocalWhisperModelManifest?
    private var engine: WhisperKit?
    private var modelGeneration: UInt64 = 0
    private var preparation: (
        generation: UInt64,
        task: Task<WhisperKit, Error>
    )?
    private nonisolated let readiness = LocalWhisperReadiness()

    public nonisolated var isPreparedForRecovery: Bool {
        readiness.isPrepared
    }

    public init(
        rootDirectory: URL,
        model: String = LocalWhisperModelManager.defaultModel,
        fileManager: FileManager = .default
    ) throws {
        self.rootDirectory = rootDirectory.standardizedFileURL
        manifestURL = rootDirectory.appending(path: "manifest.json")
        self.model = model
        self.fileManager = fileManager
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: rootDirectory.path
        )
    }

    public func snapshot() -> LocalWhisperModelSnapshot {
        if installationInProgress {
            return .init(state: .installing, model: model)
        }
        do {
            let manifest = try verifiedModelManifest()
            return .init(
                state: .available,
                model: manifest.model,
                sizeBytes: manifest.sizeBytes
            )
        } catch LocalWhisperModelError.unavailable {
            return .init(state: .notInstalled, model: model)
        } catch {
            return .init(
                state: .corrupt,
                model: model,
                detail: error.localizedDescription
            )
        }
    }

    @discardableResult
    public func install() async throws -> LocalWhisperModelSnapshot {
        if installationInProgress {
            throw LocalWhisperModelError.installationInProgress
        }
        if let manifest = try? verifiedModelManifest() {
            return .init(
                state: .available,
                model: manifest.model,
                sizeBytes: manifest.sizeBytes
            )
        }
        installationInProgress = true
        defer { installationInProgress = false }
        try Task.checkCancellation()
        let modelFolder = try await WhisperKit.download(
            variant: model,
            downloadBase: rootDirectory,
            useBackgroundSession: false
        )
        try Task.checkCancellation()
        return try registerExistingModel(at: modelFolder)
    }

    @discardableResult
    public func registerExistingModel(
        at modelFolder: URL
    ) throws -> LocalWhisperModelSnapshot {
        let relativePath = try safeRelativePath(for: modelFolder)
        let files = try Self.manifestEntries(
            in: modelFolder,
            fileManager: fileManager
        )
        guard !files.isEmpty else { throw LocalWhisperModelError.corrupt }
        let manifest = LocalWhisperModelManifest(
            schemaVersion: 1,
            runtimeVersion: Self.runtimeVersion,
            model: model,
            modelRelativePath: relativePath,
            installedAt: Date(),
            files: files
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: manifestURL.path
        )
        verifiedManifest = manifest
        invalidatePreparedEngine()
        return .init(
            state: .available,
            model: model,
            sizeBytes: manifest.sizeBytes
        )
    }

    public func deleteModel() throws {
        if installationInProgress {
            throw LocalWhisperModelError.installationInProgress
        }
        invalidatePreparedEngine()
        verifiedManifest = nil
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
        let children = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        )
        for child in children {
            guard try safeRelativePath(for: child).isEmpty == false else {
                throw LocalWhisperModelError.unsafeModelPath
            }
            try fileManager.removeItem(at: child)
        }
    }

    public func transcribe(
        fileURL: URL,
        prompt: String = ""
    ) async throws -> ArcTranscriptionResult {
        try Task.checkCancellation()
        let manifest = try verifiedModelManifest()
        let whisper = try await preparedEngine(for: manifest)
        try Task.checkCancellation()
        let promptTokens = whisper.tokenizer.map {
            LocalWhisperPromptPolicy.boundedTokens(
                for: prompt,
                encode: $0.encode(text:)
            )
        } ?? []
        func decodingOptions(for tokens: [Int]) -> DecodingOptions {
            DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: "en",
                temperature: 0,
                usePrefillPrompt: true,
                wordTimestamps: true,
                promptTokens: tokens.isEmpty ? nil : tokens,
                chunkingStrategy: .vad
            )
        }
        let startedAt = Date()
        var effectivePromptTokens = promptTokens
        var localResults = try await whisper.transcribe(
            audioPath: fileURL.path,
            decodeOptions: decodingOptions(for: effectivePromptTokens)
        )
        var text = localResults.map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if LocalWhisperPromptPolicy.shouldRetryWithoutConditioning(
            transcript: text,
            forPromptTokens: effectivePromptTokens
        ) {
            effectivePromptTokens = []
            localResults = try await whisper.transcribe(
                audioPath: fileURL.path,
                decodeOptions: decodingOptions(for: effectivePromptTokens)
            )
            text = localResults.map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let inferenceSeconds = Date().timeIntervalSince(startedAt)
        try Task.checkCancellation()
        let whisperSegments = localResults.flatMap(\.segments)
        guard !text.isEmpty else { throw LocalWhisperModelError.emptyTranscript }
        let words = whisperSegments
            .flatMap { $0.words ?? [] }
            .map {
                TranscriptWord(
                    word: $0.word,
                    start: Double($0.start),
                    end: Double($0.end)
                )
            }
        let segments = whisperSegments.map {
            TranscriptSegment(
                start: Double($0.start),
                end: Double($0.end),
                text: $0.text,
                averageLogProbability: Double($0.avgLogprob),
                compressionRatio: Double($0.compressionRatio),
                noSpeechProbability: Double($0.noSpeechProb)
            )
        }
        return ArcTranscriptionResult(
            text: text,
            words: words,
            segments: segments,
            durationSeconds: segments.map(\.end).max()
                ?? words.map(\.end).max()
                ?? 0,
            chunkCount: 1,
            timing: .init(
                chunkPreparationSeconds: 0,
                providerWaitSeconds: 0,
                responseProcessingSeconds: 0
            ),
            engine: "whisperkit",
            model: manifest.model,
            localInferenceSeconds: inferenceSeconds,
            localPromptTokenCount: effectivePromptTokens.count
        )
    }

    /// Loads and prewarms an already-installed model outside the foreground
    /// transcription path. Failure is intentionally nonfatal: the provider
    /// candidate remains available and recovery simply skips local inference.
    @discardableResult
    public func prepareForRecoveryIfInstalled() async -> Bool {
        do {
            let manifest = try verifiedModelManifest()
            _ = try await preparedEngine(for: manifest)
            return true
        } catch {
            readiness.setPrepared(false)
            return false
        }
    }

    private func preparedEngine(
        for manifest: LocalWhisperModelManifest
    ) async throws -> WhisperKit {
        if let engine {
            readiness.setPrepared(true)
            return engine
        }
        try Task.checkCancellation()
        let generation = modelGeneration
        if let preparation,
           preparation.generation == generation {
            let prepared = try await preparation.task.value
            try Task.checkCancellation()
            guard modelGeneration == generation,
                  verifiedManifest == manifest else {
                throw CancellationError()
            }
            engine = prepared
            self.preparation = nil
            readiness.setPrepared(true)
            return prepared
        }
        let modelFolder = try safeModelFolder(for: manifest)
        let config = WhisperKitConfig(
            model: manifest.model,
            downloadBase: rootDirectory,
            modelFolder: modelFolder.path,
            verbose: false,
            prewarm: true,
            load: true,
            download: false,
            useBackgroundDownloadSession: false
        )
        let task = Task { try await WhisperKit(config) }
        preparation = (generation, task)
        do {
            let prepared = try await task.value
            try Task.checkCancellation()
            guard modelGeneration == generation,
                  verifiedManifest == manifest else {
                throw CancellationError()
            }
            engine = prepared
            preparation = nil
            readiness.setPrepared(true)
            return prepared
        } catch {
            if modelGeneration == generation {
                preparation = nil
                readiness.setPrepared(false)
            }
            throw error
        }
    }

    private func invalidatePreparedEngine() {
        modelGeneration &+= 1
        preparation?.task.cancel()
        preparation = nil
        engine = nil
        readiness.setPrepared(false)
    }

    private func verifiedModelManifest() throws -> LocalWhisperModelManifest {
        if let verifiedManifest { return verifiedManifest }
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw LocalWhisperModelError.unavailable
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(
            LocalWhisperModelManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.schemaVersion == 1,
              manifest.runtimeVersion == Self.runtimeVersion,
              manifest.model == model else {
            throw LocalWhisperModelError.corrupt
        }
        let folder = try safeModelFolder(for: manifest)
        let current = try Self.manifestEntries(
            in: folder,
            fileManager: fileManager
        )
        guard current == manifest.files else {
            throw LocalWhisperModelError.corrupt
        }
        verifiedManifest = manifest
        return manifest
    }

    private func safeModelFolder(
        for manifest: LocalWhisperModelManifest
    ) throws -> URL {
        let folder = rootDirectory.appending(
            path: manifest.modelRelativePath,
            directoryHint: .isDirectory
        ).standardizedFileURL
        _ = try safeRelativePath(for: folder)
        return folder
    }

    private func safeRelativePath(for url: URL) throws -> String {
        let rootPath = rootDirectory.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path
        guard candidatePath.hasPrefix(rootPath + "/") else {
            throw LocalWhisperModelError.unsafeModelPath
        }
        return String(candidatePath.dropFirst(rootPath.count + 1))
    }

    private static func manifestEntries(
        in folder: URL,
        fileManager: FileManager
    ) throws -> [LocalWhisperModelManifest.FileEntry] {
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            throw LocalWhisperModelError.corrupt
        }
        var entries: [LocalWhisperModelManifest.FileEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ])
            if values.isSymbolicLink == true {
                throw LocalWhisperModelError.corrupt
            }
            guard values.isRegularFile == true else { continue }
            let relativePath = String(
                url.standardizedFileURL.path.dropFirst(
                    folder.standardizedFileURL.path.count + 1
                )
            )
            entries.append(.init(
                relativePath: relativePath,
                sizeBytes: Int64(values.fileSize ?? 0),
                sha256: try sha256(of: url)
            ))
        }
        return entries.sorted { $0.relativePath < $1.relativePath }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public actor ManagedLocalWhisperTranscriber: SpeechTranscribing {
    public nonisolated let diagnosticEngine = "whisperkit"
    public nonisolated let diagnosticModel: String? =
        LocalWhisperModelManager.defaultModel
    private let manager: LocalWhisperModelManager

    public init(manager: LocalWhisperModelManager) {
        self.manager = manager
    }

    public nonisolated var isReadyForImmediateTranscription: Bool {
        manager.isPreparedForRecovery
    }

    public func transcribe(
        fileURL: URL,
        prompt: String,
        temporaryDirectory: URL
    ) async throws -> ArcTranscriptionResult {
        try await manager.transcribe(fileURL: fileURL, prompt: prompt)
    }
}
