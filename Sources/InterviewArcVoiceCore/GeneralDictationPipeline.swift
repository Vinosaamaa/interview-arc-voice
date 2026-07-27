import Foundation

public actor GeneralDictationPipeline {
    private let reliableTranscriber: ReliableSpeechTranscriber
    private let temporaryDirectory: URL
    private let fileManager: FileManager
    private let vocabularyPrompt: String

    public init(
        transcriber: any SpeechTranscribing,
        temporaryDirectory: URL,
        vocabularyPrompt: String = "",
        fileManager: FileManager = .default
    ) {
        reliableTranscriber = ReliableSpeechTranscriber(base: transcriber)
        self.temporaryDirectory = temporaryDirectory
        self.vocabularyPrompt = vocabularyPrompt
        self.fileManager = fileManager
    }

    public func process(
        recordingURL: URL,
        durationSeconds: Double,
        speechEvidence: SpeechEvidenceResult? = nil,
        protectionMode: SpeechProtectionMode = .basic
    ) async throws -> ReliableTranscription {
        let result = try await reliableTranscriber.transcribe(
            fileURL: recordingURL,
            // Whisper's `prompt` is prior transcript context, not an
            // instruction channel. Supplying prose instructions here caused
            // those instructions to leak into user transcripts.
            prompt: vocabularyPrompt,
            temporaryDirectory: temporaryDirectory,
            audioDurationSeconds: durationSeconds,
            speechEvidence: speechEvidence,
            protectionMode: protectionMode
        )
        try? fileManager.removeItem(at: recordingURL)
        return result
    }
}
