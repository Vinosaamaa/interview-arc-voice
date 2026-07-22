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
            prompt: "Verbatim general dictation. Preserve punctuation, names, acronyms, and technical terminology.",
            temporaryDirectory: temporaryDirectory
        )
    }
}
