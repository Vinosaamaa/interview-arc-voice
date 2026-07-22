import Foundation

public struct VoiceRetryItem: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case capturePersistence
        case specialistDelivery
        case audioUpload
        case deliveryCoach
    }

    public let id: String
    public let kind: Kind
    public let createdAt: Date
    public let occurredAt: Date?
    public let activity: FocusedVoiceActivity
    public let specialist: SpecialistRoute?
    public let turnID: String
    public let transcript: String
    public let audioURL: URL
    public let durationSeconds: Double
    public let transcription: TranscriptionResult
    public let clipID: String?
    public let analysisID: String?
    public let lastError: String
}

public actor VoiceRetryQueue {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func enqueue(_ item: VoiceRetryItem) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let destination = directory.appending(path: "\(item.id).json")
        try encoder.encode(item).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }

    public func items() throws -> [VoiceRetryItem] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { try? decoder.decode(VoiceRetryItem.self, from: Data(contentsOf: $0)) }
        .sorted { $0.createdAt < $1.createdAt }
    }

    public func remove(id: String) throws {
        let destination = directory.appending(path: "\(id).json")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
    }
}
