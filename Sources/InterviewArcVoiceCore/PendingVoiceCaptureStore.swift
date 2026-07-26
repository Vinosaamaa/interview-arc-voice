import Foundation

public struct PendingVoiceCapture: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let turnID: String
    public let clipID: String
    public let checksum: String
    public let activity: FocusedVoiceActivity
    public let transcript: String
    public let audioURL: URL
    public let durationSeconds: Double
    public let occurredAt: Date
    public let transcription: TranscriptionResult
    public let createdAt: Date
}

public actor PendingVoiceCaptureStore {
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

    public func save(_ capture: PendingVoiceCapture) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let url = directory.appending(path: "\(capture.id).json")
        try encoder.encode(capture).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func items() throws -> [PendingVoiceCapture] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .compactMap { try? decoder.decode(PendingVoiceCapture.self, from: Data(contentsOf: $0)) }
        .sorted { $0.createdAt < $1.createdAt }
    }

    public func remove(id: String, deleteAudio: Bool) throws {
        if deleteAudio,
           let capture = try items().first(where: { $0.id == id }),
           FileManager.default.fileExists(atPath: capture.audioURL.path) {
            try FileManager.default.removeItem(at: capture.audioURL)
        }
        let url = directory.appending(path: "\(id).json")
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
