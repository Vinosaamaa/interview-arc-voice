import Foundation

public struct RecordingStore: Sendable {
    public let recordingsDirectory: URL
    public let temporaryDirectory: URL
    public let queueDirectory: URL

    public init(fileManager: FileManager = .default) throws {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support.appending(path: "InterviewArcVoice", directoryHint: .isDirectory)
        recordingsDirectory = root.appending(path: "Recordings", directoryHint: .isDirectory)
        temporaryDirectory = root.appending(path: "Transcription", directoryHint: .isDirectory)
        queueDirectory = root.appending(path: "RetryQueue", directoryHint: .isDirectory)
        for directory in [recordingsDirectory, temporaryDirectory, queueDirectory] {
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
}
