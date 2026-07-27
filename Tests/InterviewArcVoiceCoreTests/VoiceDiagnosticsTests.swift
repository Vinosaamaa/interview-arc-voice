import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func diagnosticsStoreRetainsOnlyRecentPrivacySafeTimings() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "InterviewArcVoiceDiagnostics-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try VoiceDiagnosticsStore(
        directory: root,
        retentionLimit: 2
    )

    for index in 0..<3 {
        try await store.append(
            VoiceDiagnosticRecord(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: Double(index)),
                recordingDurationSeconds: 60,
                fileFinalizationSeconds: 0.04,
                integrityInspectionSeconds: 0.02,
                localSpeechScanSeconds: 0.08,
                providerWaitSeconds: 2.4,
                responseProcessingSeconds: 0.01,
                segmentValidationSeconds: 0.002,
                insertionSeconds: 0.03,
                totalSeconds: 2.58,
                protectionMode: .enhanced,
                omittedUnsupportedSegmentCount: index,
                outcome: .delivered
            )
        )
    }

    let records = try await store.records()
    let rawFile = try String(contentsOf: store.fileURL, encoding: .utf8)
    let attributes = try FileManager.default.attributesOfItem(
        atPath: store.fileURL.path
    )
    let permissions = attributes[.posixPermissions] as? NSNumber

    #expect(records.map(\.omittedUnsupportedSegmentCount) == [2, 1])
    #expect(permissions?.intValue == 0o600)
    #expect(!rawFile.localizedCaseInsensitiveContains("transcript"))
    #expect(!rawFile.localizedCaseInsensitiveContains("apiKey"))
    #expect(!rawFile.localizedCaseInsensitiveContains("token"))
    #expect(!rawFile.localizedCaseInsensitiveContains(".m4a"))
}

@Test func diagnosticsStoreCanBeCleared() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "InterviewArcVoiceDiagnostics-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try VoiceDiagnosticsStore(directory: root)
    try await store.append(.fixture)

    try await store.clear()

    let records = try await store.records()
    #expect(records.isEmpty)
}

private extension VoiceDiagnosticRecord {
    static let fixture = VoiceDiagnosticRecord(
        id: UUID(),
        createdAt: Date(),
        recordingDurationSeconds: 5,
        fileFinalizationSeconds: 0.01,
        integrityInspectionSeconds: 0.01,
        localSpeechScanSeconds: 0.01,
        providerWaitSeconds: 0.5,
        responseProcessingSeconds: 0.01,
        segmentValidationSeconds: 0.001,
        insertionSeconds: 0.01,
        totalSeconds: 0.55,
        protectionMode: .basic,
        omittedUnsupportedSegmentCount: 0,
        outcome: .delivered
    )
}
