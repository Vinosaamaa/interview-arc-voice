import Foundation

public enum TranscriptionFailureDisposition: Equatable, Sendable {
    case replaceCredential
    case retryTranscription
}

public enum TranscriptionFailurePolicy {
    public static func disposition(
        for error: Error
    ) -> TranscriptionFailureDisposition {
        guard case VoiceBridgeError.invalidProviderCredential = error else {
            return .retryTranscription
        }
        return .replaceCredential
    }
}

public struct RejectedCredentialPolicy: Sendable {
    public init() {}

    public func canRetry(
        rejectedCredential: String?,
        submittedCredential: String
    ) -> Bool {
        let submitted = submittedCredential.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !submitted.isEmpty else { return false }
        guard let rejectedCredential else { return true }
        return submitted != rejectedCredential.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }
}

public enum RecoveryActionAvailabilityPolicy {
    public static func availableActions(
        from actions: [VoiceFailureAction],
        hasRecoverableAudio: Bool
    ) -> [VoiceFailureAction] {
        actions.filter { action in
            switch action {
            case .playRecording, .saveRecording:
                return hasRecoverableAudio
            default:
                return true
            }
        }
    }
}

public enum ManualInsertionSurface: Sendable {
    case floatingWidget
    case menuBar
}

public struct ManualInsertionTargetPolicy: Sendable {
    public init() {}

    public func targetPID(
        surface: ManualInsertionSurface,
        currentEligiblePID: pid_t?,
        rememberedEligiblePID: pid_t?
    ) -> pid_t? {
        switch surface {
        case .floatingWidget:
            return currentEligiblePID ?? rememberedEligiblePID
        case .menuBar:
            return rememberedEligiblePID ?? currentEligiblePID
        }
    }
}

public enum MenuInsertionDismissalPolicy {
    public static let pollingMilliseconds = 25
    public static let maximumChecks = 36

    public static func hasDismissed(
        windowIsVisible: Bool,
        windowIsKey: Bool
    ) -> Bool {
        _ = windowIsKey
        return !windowIsVisible
    }
}

public struct LocalTranscriptRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let transcript: String
    public let editorText: String
    public let durationSeconds: Double
    public let activityTitle: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        transcript: String,
        editorText: String,
        durationSeconds: Double,
        activityTitle: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.transcript = transcript
        self.editorText = editorText
        self.durationSeconds = durationSeconds
        self.activityTitle = activityTitle
    }

    public var wordCount: Int {
        transcript.split(whereSeparator: \.isWhitespace).count
    }
}

public actor LocalTranscriptHistoryStore {
    public nonisolated let fileURL: URL

    private let retentionDuration: TimeInterval
    private let retentionLimit: Int
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        directory: URL,
        retentionDuration: TimeInterval = 24 * 60 * 60,
        retentionLimit: Int = 20,
        fileManager: FileManager = .default
    ) throws {
        self.retentionDuration = max(1, retentionDuration)
        self.retentionLimit = max(1, retentionLimit)
        self.fileManager = fileManager
        fileURL = directory.appending(path: "transcript-history.json")
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        if !fileManager.fileExists(atPath: fileURL.path) {
            try Data("[]".utf8).write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        }
    }

    public func append(
        _ record: LocalTranscriptRecord,
        now: Date = Date()
    ) throws {
        var current = try readRecords()
        current.removeAll {
            $0.id == record.id
                || ($0.transcript == record.transcript
                    && $0.editorText == record.editorText)
        }
        current.insert(record, at: 0)
        try write(filtered(current, now: now))
    }

    public func records(now: Date = Date()) throws -> [LocalTranscriptRecord] {
        let current = try readRecords()
        let retained = filtered(current, now: now)
        if retained != current {
            try write(retained)
        }
        return retained
    }

    private func readRecords() throws -> [LocalTranscriptRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([LocalTranscriptRecord].self, from: data)
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func filtered(
        _ records: [LocalTranscriptRecord],
        now: Date
    ) -> [LocalTranscriptRecord] {
        Array(
            records
                .filter { now.timeIntervalSince($0.createdAt) < retentionDuration }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(retentionLimit)
        )
    }

    private func write(_ records: [LocalTranscriptRecord]) throws {
        try encoder.encode(records).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}

public struct LocalRecoverableRecordingReference:
    Codable,
    Equatable,
    Sendable
{
    public let audioPath: String
    public let durationSeconds: Double
    public let createdAt: Date
    public let activityTitle: String?

    public init(
        audioURL: URL,
        durationSeconds: Double,
        createdAt: Date = Date(),
        activityTitle: String? = nil
    ) {
        audioPath = audioURL.standardizedFileURL.path
        self.durationSeconds = max(0, durationSeconds)
        self.createdAt = createdAt
        self.activityTitle = activityTitle
    }

    public var audioURL: URL {
        URL(fileURLWithPath: audioPath).standardizedFileURL
    }
}

public final class LocalRecoverableRecordingStore: @unchecked Sendable {
    public let fileURL: URL

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        directory: URL,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        fileURL = directory.appending(path: "recoverable-recording.json")
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    public func save(_ reference: LocalRecoverableRecordingReference) throws {
        try encoder.encode(reference).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    public func load(
        allowedDirectories: [URL]
    ) throws -> LocalRecoverableRecordingReference? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let reference = try decoder.decode(
            LocalRecoverableRecordingReference.self,
            from: Data(contentsOf: fileURL)
        )
        guard Self.isAllowed(
            reference.audioURL,
            allowedDirectories: allowedDirectories
        ),
        Self.isNonemptyFile(reference.audioURL, fileManager: fileManager) else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        return reference
    }

    public func clear() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    public static func discoverNewestAudio(
        in directories: [URL],
        fileManager: FileManager = .default
    ) -> URL? {
        directories
            .flatMap { directory -> [(url: URL, modifiedAt: Date)] in
                guard let urls = try? fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [
                        .contentModificationDateKey,
                        .fileSizeKey,
                        .isRegularFileKey,
                    ],
                    options: [.skipsHiddenFiles]
                ) else {
                    return []
                }
                return urls.compactMap { url in
                    guard url.pathExtension.localizedCaseInsensitiveCompare("m4a")
                        == .orderedSame,
                    let values = try? url.resourceValues(forKeys: [
                        .contentModificationDateKey,
                        .fileSizeKey,
                        .isRegularFileKey,
                    ]),
                    values.isRegularFile == true,
                    (values.fileSize ?? 0) > 0 else {
                        return nil
                    }
                    return (url.standardizedFileURL, values.contentModificationDate ?? .distantPast)
                }
            }
            .max { $0.modifiedAt < $1.modifiedAt }?
            .url
    }

    private static func isAllowed(
        _ fileURL: URL,
        allowedDirectories: [URL]
    ) -> Bool {
        let filePath = fileURL.standardizedFileURL.path
        return allowedDirectories.contains { directory in
            let directoryPath = directory.standardizedFileURL.path
            return filePath.hasPrefix(
                directoryPath.hasSuffix("/")
                    ? directoryPath
                    : "\(directoryPath)/"
            )
        }
    }

    private static func isNonemptyFile(
        _ fileURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: fileURL.path
        ),
        let type = attributes[.type] as? FileAttributeType,
        type == .typeRegular,
        let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }
}
