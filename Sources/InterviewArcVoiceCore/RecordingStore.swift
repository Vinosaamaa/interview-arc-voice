import Foundation

public struct RecordingStore: Sendable {
    public let recordingsDirectory: URL
    public let temporaryDirectory: URL
    public let queueDirectory: URL
    public let pendingCapturesDirectory: URL
    public let diagnosticsDirectory: URL
    public let transcriptHistoryDirectory: URL
    public let recoveryDirectory: URL

    public init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        try self.init(
            rootDirectory: support.appending(path: "InterviewArcVoice", directoryHint: .isDirectory),
            fileManager: fileManager
        )
    }

    public init(
        rootDirectory root: URL,
        fileManager: FileManager = .default
    ) throws {
        recordingsDirectory = root.appending(path: "Recordings", directoryHint: .isDirectory)
        temporaryDirectory = root.appending(path: "Transcription", directoryHint: .isDirectory)
        queueDirectory = root.appending(path: "RetryQueue", directoryHint: .isDirectory)
        pendingCapturesDirectory = root.appending(path: "PendingCaptures", directoryHint: .isDirectory)
        diagnosticsDirectory = root.appending(path: "Diagnostics", directoryHint: .isDirectory)
        transcriptHistoryDirectory = root.appending(
            path: "TranscriptHistory",
            directoryHint: .isDirectory
        )
        recoveryDirectory = root.appending(
            path: "Recovery",
            directoryHint: .isDirectory
        )
        for directory in [
            recordingsDirectory,
            temporaryDirectory,
            queueDirectory,
            pendingCapturesDirectory,
            diagnosticsDirectory,
            transcriptHistoryDirectory,
            recoveryDirectory,
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }

    public func nextRecordingURL(activityID: String, now: Date = Date()) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        let safeActivity = activityID
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^a-zA-Z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return recordingsDirectory.appending(path: "\(timestamp)-\(safeActivity)-\(UUID().uuidString.lowercased()).m4a")
    }

    public func nextTemporaryRecordingURL(now: Date = Date()) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")
        return temporaryDirectory.appending(path: "\(timestamp)-general-dictation-\(UUID().uuidString.lowercased()).m4a")
    }

    public func promoteToLinkedRecording(
        _ recording: RecordedCapture,
        activityID: String,
        fileManager: FileManager = .default
    ) throws -> RecordedCapture {
        guard recording.url.deletingLastPathComponent().standardizedFileURL
                == temporaryDirectory.standardizedFileURL else {
            return recording
        }
        let destination = nextRecordingURL(activityID: activityID)
        try fileManager.moveItem(at: recording.url, to: destination)
        return RecordedCapture(
            url: destination,
            duration: recording.duration,
            writtenFrameCount: recording.writtenFrameCount,
            writeErrorDescription: recording.writeErrorDescription
        )
    }
}
