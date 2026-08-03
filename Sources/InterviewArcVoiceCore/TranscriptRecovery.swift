import Foundation

public enum TranscriptionFailureDisposition: Equatable, Sendable {
    case replaceCredential
    case reviewProviderPermission
    case retryTranscription
}

public enum TranscriptionFailurePolicy {
    public static func disposition(
        for error: Error
    ) -> TranscriptionFailureDisposition {
        switch error {
        case VoiceBridgeError.invalidProviderCredential:
            return .replaceCredential
        case VoiceBridgeError.providerPermissionDenied:
            return .reviewProviderPermission
        default:
            return .retryTranscription
        }
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

public enum RecoveryTranscriptPromotionPolicy {
    public static func canUse(
        recoveryStatus: LocalTranscriptRecoveryStatus?,
        hasRetainedAudio: Bool,
        promotionInFlight: Bool
    ) -> Bool {
        recoveryStatus == .coverageUncertain
            && hasRetainedAudio
            && !promotionInFlight
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

public struct LocalTranscriptAudioReference:
    Codable,
    Equatable,
    Sendable
{
    public let storageName: String

    public init(storageName: String) {
        self.storageName = storageName
    }
}

public enum LocalTranscriptRecoveryStatus:
    String,
    Codable,
    Equatable,
    Sendable
{
    case coverageUncertain
}

public struct LinkedTranscriptRecoveryContext: Codable, Equatable, Sendable {
    public let captureID: String
    public let turnID: String
    public let clipID: String
    public let checksum: String
    public let activity: FocusedVoiceActivity
    public let transcription: TranscriptionResult
    public let occurredAt: Date

    public init(
        captureID: String,
        turnID: String,
        clipID: String,
        checksum: String,
        activity: FocusedVoiceActivity,
        transcription: TranscriptionResult,
        occurredAt: Date
    ) {
        self.captureID = captureID
        self.turnID = turnID
        self.clipID = clipID
        self.checksum = checksum
        self.activity = activity
        self.transcription = transcription
        self.occurredAt = occurredAt
    }
}

public struct LocalTranscriptRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let transcript: String
    public let editorText: String
    public let durationSeconds: Double
    public let activityTitle: String?
    public let captureID: String?
    public let recoveryStatus: LocalTranscriptRecoveryStatus?
    public let linkedRecoveryContext: LinkedTranscriptRecoveryContext?
    public var lifecycleProtected: Bool?
    public var audioReference: LocalTranscriptAudioReference?

    public var isLifecycleProtected: Bool {
        lifecycleProtected == true
            || (recoveryStatus == .coverageUncertain
                && linkedRecoveryContext != nil)
    }

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        transcript: String,
        editorText: String,
        durationSeconds: Double,
        activityTitle: String? = nil,
        captureID: String? = nil,
        recoveryStatus: LocalTranscriptRecoveryStatus? = nil,
        linkedRecoveryContext: LinkedTranscriptRecoveryContext? = nil,
        lifecycleProtected: Bool? = nil,
        audioReference: LocalTranscriptAudioReference? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.transcript = transcript
        self.editorText = editorText
        self.durationSeconds = durationSeconds
        self.activityTitle = activityTitle
        self.captureID = captureID
        self.recoveryStatus = recoveryStatus
        self.linkedRecoveryContext = linkedRecoveryContext
        self.lifecycleProtected = lifecycleProtected
        self.audioReference = audioReference
    }

    public var wordCount: Int {
        transcript.split(whereSeparator: \.isWhitespace).count
    }
}

public actor LocalTranscriptHistoryStore {
    public nonisolated let fileURL: URL
    public nonisolated let audioDirectory: URL

    private let retentionDuration: TimeInterval
    private let retentionLimit: Int
    private let diskBudgetBytes: Int64
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        directory: URL,
        audioDirectory: URL? = nil,
        retentionDuration: TimeInterval = 24 * 60 * 60,
        retentionLimit: Int = 20,
        diskBudgetBytes: Int64 = 512 * 1_024 * 1_024,
        fileManager: FileManager = .default
    ) throws {
        self.retentionDuration = max(1, retentionDuration)
        self.retentionLimit = max(1, retentionLimit)
        self.diskBudgetBytes = max(1, diskBudgetBytes)
        self.fileManager = fileManager
        fileURL = directory.appending(path: "transcript-history.json")
        self.audioDirectory = audioDirectory
            ?? directory.appending(path: "RecentHistory", directoryHint: .isDirectory)
        for protectedDirectory in [directory, self.audioDirectory] {
            try fileManager.createDirectory(
                at: protectedDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: protectedDirectory.path
            )
        }
        if !fileManager.fileExists(atPath: fileURL.path) {
            try Data("[]".utf8).write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        }
    }

    @discardableResult
    public func append(
        _ record: LocalTranscriptRecord,
        recordingURL: URL? = nil,
        now: Date = Date()
    ) throws -> LocalTranscriptRecord {
        var current = try readRecords()
        let replaced = current.filter {
            $0.id == record.id
                || ($0.transcript == record.transcript
                    && $0.editorText == record.editorText)
        }
        let destination = archivedAudioURL(recordID: record.id)
        let reusesArchivedAudio = recordingURL?.standardizedFileURL
            == destination.standardizedFileURL
            && Self.isNonemptyFile(destination, fileManager: fileManager)
        current.removeAll { candidate in replaced.contains { $0.id == candidate.id } }
        for replacedRecord in replaced where !reusesArchivedAudio {
            try removeAudio(for: replacedRecord)
        }
        var archived = record
        if reusesArchivedAudio {
            archived.audioReference = LocalTranscriptAudioReference(
                storageName: destination.lastPathComponent
            )
        } else if let recordingURL {
            archived.audioReference = try archive(
                recordingURL: recordingURL,
                recordID: record.id
            )
        }
        current.insert(archived, at: 0)
        try write(pruned(current, now: now))
        return archived
    }

    public func records(now: Date = Date()) throws -> [LocalTranscriptRecord] {
        let current = try readRecords()
        let visible = visibleRecords(current, now: now)
        do {
            let retained = try pruned(current, now: now)
            if retained != current {
                try write(retained)
            }
            return retained
        } catch {
            // Cleanup is best-effort for presentation. A transient directory,
            // audio-file, or atomic-write failure must not turn a valid
            // Recent Transcripts file into an empty card. The next refresh
            // retries cleanup while the bounded, non-expired records remain
            // visible now.
            return visible
        }
    }

    @discardableResult
    public func replaceTranscript(
        id: UUID,
        transcript: String,
        editorText: String,
        captureID: String? = nil,
        lifecycleProtected: Bool? = nil,
        now: Date = Date()
    ) throws -> LocalTranscriptRecord? {
        var current = try readRecords()
        guard let index = current.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let previous = current[index]
        let replacement = LocalTranscriptRecord(
            id: previous.id,
            createdAt: previous.createdAt,
            transcript: transcript,
            editorText: editorText,
            durationSeconds: previous.durationSeconds,
            activityTitle: previous.activityTitle,
            captureID: captureID ?? previous.captureID,
            recoveryStatus: nil,
            linkedRecoveryContext: previous.linkedRecoveryContext,
            lifecycleProtected: lifecycleProtected
                ?? previous.lifecycleProtected
                ?? (previous.isLifecycleProtected
                    || (captureID != nil && previous.audioReference != nil)),
            audioReference: previous.audioReference
        )
        current[index] = replacement
        try write(pruned(current, now: now))
        return replacement
    }

    public func audioURL(
        for record: LocalTranscriptRecord
    ) -> URL? {
        guard let reference = record.audioReference,
              Self.isSafeStorageName(reference.storageName) else {
            return nil
        }
        let url = audioDirectory
            .appending(path: reference.storageName)
            .standardizedFileURL
        guard url.deletingLastPathComponent() == audioDirectory.standardizedFileURL,
              Self.isNonemptyFile(url, fileManager: fileManager) else {
            return nil
        }
        return url
    }

    @discardableResult
    public func adoptLinkedAudio(
        captureID: String,
        recordingURL: URL,
        now: Date = Date()
    ) throws -> Bool {
        var current = try pruned(readRecords(), now: now)
        guard let index = current.firstIndex(where: {
            $0.captureID == captureID
        }) else {
            try write(current)
            return false
        }
        let destination = archivedAudioURL(recordID: current[index].id)
        if recordingURL.standardizedFileURL == destination.standardizedFileURL,
           Self.isNonemptyFile(destination, fileManager: fileManager) {
            current[index].audioReference = LocalTranscriptAudioReference(
                storageName: destination.lastPathComponent
            )
            current[index].lifecycleProtected = false
            try write(try pruned(current, now: now))
            return true
        }
        let sourceExists = Self.isNonemptyFile(
            recordingURL,
            fileManager: fileManager
        )
        let destinationExists = Self.isNonemptyFile(
            destination,
            fileManager: fileManager
        )
        if sourceExists && !destinationExists {
            try fileManager.moveItem(at: recordingURL, to: destination)
        } else if sourceExists && destinationExists {
            // Both files still exist, so the interrupted operation is
            // ambiguous. Preserve the lifecycle-protected source and let a
            // future reconciliation retry after the conflict is inspected.
            return false
        } else if !destinationExists {
            return false
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
        current[index].audioReference = LocalTranscriptAudioReference(
            storageName: destination.lastPathComponent
        )
        current[index].lifecycleProtected = false
        try write(try pruned(current, now: now))
        return true
    }

    public func delete(id: UUID) throws {
        var current = try readRecords()
        guard let removed = current.first(where: { $0.id == id }) else {
            return
        }
        guard !removed.isLifecycleProtected else { return }
        current.removeAll { $0.id == id }
        try removeAudio(for: removed)
        try write(current)
    }

    public func discardRecovery(id: UUID) throws {
        var current = try readRecords()
        guard let removed = current.first(where: { $0.id == id }),
              removed.recoveryStatus == .coverageUncertain else {
            return
        }
        current.removeAll { $0.id == id }
        try removeAudio(for: removed)
        try write(current)
    }

    public func clear() throws {
        let current = try readRecords()
        let retained = current.filter(\.isLifecycleProtected)
        for record in current where !record.isLifecycleProtected {
            try removeAudio(for: record)
        }
        try write(retained)
    }

    public func nextExpiryDate(now: Date = Date()) throws -> Date? {
        try records(now: now)
            .filter { !$0.isLifecycleProtected }
            .map { $0.createdAt.addingTimeInterval(retentionDuration) }
            .filter { $0 > now }
            .min()
    }

    private func readRecords() throws -> [LocalTranscriptRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try decoder.decode([LocalTranscriptRecord].self, from: data)
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func pruned(
        _ records: [LocalTranscriptRecord],
        now: Date
    ) throws -> [LocalTranscriptRecord] {
        let ordered = records.sorted { $0.createdAt > $1.createdAt }
        var retained = visibleRecords(ordered, now: now)
        for index in retained.indices
            where retained[index].audioReference != nil
                && audioURL(for: retained[index]) == nil {
            retained[index].audioReference = nil
        }
        let retainedIDs = Set(retained.map(\.id))
        for evicted in ordered where !retainedIDs.contains(evicted.id) {
            try removeAudio(for: evicted)
        }

        var total = retained.reduce(into: Int64(0)) { result, record in
            result += audioByteCount(for: record)
        }
        while total > diskBudgetBytes,
              let oldestAudioIndex = retained.lastIndex(where: {
                  $0.audioReference != nil && !$0.isLifecycleProtected
              }) {
            let evicted = retained.remove(at: oldestAudioIndex)
            total -= audioByteCount(for: evicted)
            try removeAudio(for: evicted)
        }
        return retained
    }

    private func visibleRecords(
        _ records: [LocalTranscriptRecord],
        now: Date
    ) -> [LocalTranscriptRecord] {
        let ordered = records.sorted { $0.createdAt > $1.createdAt }
        var boundedCount = 0
        var visible: [LocalTranscriptRecord] = []
        visible.reserveCapacity(min(ordered.count, retentionLimit))
        for record in ordered {
            if record.isLifecycleProtected {
                visible.append(record)
            } else if boundedCount < retentionLimit,
                      now.timeIntervalSince(record.createdAt) < retentionDuration {
                visible.append(record)
                boundedCount += 1
            }
        }
        for index in visible.indices
            where visible[index].audioReference != nil
                && audioURL(for: visible[index]) == nil {
            visible[index].audioReference = nil
        }
        return visible
    }

    private func write(_ records: [LocalTranscriptRecord]) throws {
        try encoder.encode(records).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private func archive(
        recordingURL: URL,
        recordID: UUID
    ) throws -> LocalTranscriptAudioReference {
        guard Self.isNonemptyFile(recordingURL, fileManager: fileManager) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let destination = archivedAudioURL(recordID: recordID)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: recordingURL, to: destination)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
        return LocalTranscriptAudioReference(
            storageName: destination.lastPathComponent
        )
    }

    private func archivedAudioURL(recordID: UUID) -> URL {
        audioDirectory.appending(
            path: "\(recordID.uuidString.lowercased()).m4a"
        )
    }

    private func removeAudio(for record: LocalTranscriptRecord) throws {
        guard let url = audioURL(for: record),
              fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func audioByteCount(for record: LocalTranscriptRecord) -> Int64 {
        guard let url = audioURL(for: record),
              let attributes = try? fileManager.attributesOfItem(
                  atPath: url.path
              ),
              let number = attributes[.size] as? NSNumber else {
            return 0
        }
        return number.int64Value
    }

    private static func isSafeStorageName(_ name: String) -> Bool {
        let url = URL(fileURLWithPath: name)
        return !name.isEmpty
            && name == url.lastPathComponent
            && url.pathExtension.localizedCaseInsensitiveCompare("m4a")
                == .orderedSame
    }

    private static func isNonemptyFile(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: url.path
        ),
        let type = attributes[.type] as? FileAttributeType,
        type == .typeRegular,
        let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
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
