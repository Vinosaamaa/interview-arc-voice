import Foundation

public actor GeneralDictationPipeline {
    private let reliableTranscriber: ReliableSpeechTranscriber
    private let temporaryDirectory: URL
    private let fileManager: FileManager
    private let vocabularyPrompt: String

    public init(
        transcriber: any SpeechTranscribing,
        localFallback: (any SpeechTranscribing)? = nil,
        temporaryDirectory: URL,
        vocabularyPrompt: String = "",
        fileManager: FileManager = .default
    ) {
        reliableTranscriber = ReliableSpeechTranscriber(
            base: transcriber,
            localFallback: localFallback
        )
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
        // The caller owns the finalized recording lifecycle. Successful
        // General Dictation audio is atomically archived only after foreground
        // insertion settles; failures remain available to Recovery.
        return result
    }
}
