import Foundation

public actor GeneralDictationPipeline {
    private let transcriber: any SpeechTranscribing
    private let temporaryDirectory: URL
    private let fileManager: FileManager

    public init(
        transcriber: any SpeechTranscribing,
        temporaryDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.transcriber = transcriber
        self.temporaryDirectory = temporaryDirectory
        self.fileManager = fileManager
    }

    public func process(recordingURL: URL) async throws -> TranscriptionResult {
        defer { try? fileManager.removeItem(at: recordingURL) }
        return try await transcriber.transcribe(
            fileURL: recordingURL,
            // Whisper's `prompt` is prior transcript context, not an
            // instruction channel. Supplying prose instructions here caused
            // those instructions to leak into user transcripts.
            prompt: "",
            temporaryDirectory: temporaryDirectory
        )
    }
}
