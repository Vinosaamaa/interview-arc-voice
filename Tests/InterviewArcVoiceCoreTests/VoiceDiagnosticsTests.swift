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
                omittedUnsupportedWordCount: index + 1,
                wordAlignmentComplete: true,
                evaluatedSegmentCount: 3,
                wordTimestampCount: 12,
                microphoneRecoveryCount: 2,
                vadSpeechFrameCount: 18,
                vadLongestSpeechRunFrames: 15,
                providerRetryOccurred: true,
                lexicalCoverageEndSeconds: 58.4,
                trailingSpeechLikeFrameCount: 0,
                trailingSpeechLikeFraction: 0,
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
    #expect(records.map(\.omittedUnsupportedWordCount) == [3, 2])
    #expect(permissions?.intValue == 0o600)
    #expect(!rawFile.localizedCaseInsensitiveContains("transcript"))
    #expect(!rawFile.localizedCaseInsensitiveContains("apiKey"))
    #expect(!rawFile.localizedCaseInsensitiveContains("token"))
    #expect(!rawFile.localizedCaseInsensitiveContains(".m4a"))
}

@Test func diagnosticReportMakesSubmillisecondValidationObservable() {
    let record = VoiceDiagnosticRecord(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: 0),
        recordingDurationSeconds: 5,
        fileFinalizationSeconds: 0.01,
        integrityInspectionSeconds: 0.01,
        localSpeechScanSeconds: 0.01,
        providerWaitSeconds: 0.5,
        responseProcessingSeconds: 0.000_04,
        segmentValidationSeconds: 0.000_08,
        insertionSeconds: 0.01,
        totalSeconds: 0.55,
        protectionMode: .enhanced,
        omittedUnsupportedSegmentCount: 0,
        omittedUnsupportedWordCount: 2,
        wordAlignmentComplete: true,
        evaluatedSegmentCount: 2,
        wordTimestampCount: 8,
        microphoneRecoveryCount: 2,
        vadSpeechFrameCount: 18,
        vadLongestSpeechRunFrames: 15,
        providerRetryOccurred: true,
        lexicalCoverageEndSeconds: 4.8,
        trailingSpeechLikeFrameCount: 0,
        trailingSpeechLikeFraction: 0,
        integrityReasons: [.missingSpeechCoverage],
        outcome: .failed
    )

    #expect(record.report.contains("Response processing: <1 ms"))
    #expect(record.report.contains("Segment validation: <1 ms"))
    #expect(record.report.contains("Unsupported words omitted: 2"))
    #expect(record.report.contains("Word alignment complete: true"))
    #expect(record.report.contains("Microphone recovery attempts: 2"))
    #expect(record.report.contains("WebRTC VAD speech frames: 18"))
    #expect(record.report.contains("WebRTC VAD longest run: 15"))
    #expect(record.report.contains("Transcription retried: true"))
    #expect(record.report.contains("Provider lexical coverage end: 4.80 s"))
    #expect(record.report.contains("Trailing speech-like frames: 0"))
    #expect(record.report.contains("Trailing speech-like fraction: 0.000"))
    #expect(record.report.contains("Transcription integrity reasons: missingSpeechCoverage"))
}

@Test func diagnosticsDecodeRecordsWrittenBeforeWordLevelMetrics() throws {
    let json = """
    [{
      "id":"52D02F85-E51C-4FA4-A6ED-753D4379AEAE",
      "createdAt":0,
      "recordingDurationSeconds":5,
      "fileFinalizationSeconds":0.01,
      "integrityInspectionSeconds":0.01,
      "localSpeechScanSeconds":0.01,
      "providerWaitSeconds":0.5,
      "responseProcessingSeconds":0.01,
      "segmentValidationSeconds":0.001,
      "insertionSeconds":0.01,
      "totalSeconds":0.55,
      "protectionMode":"enhanced",
      "omittedUnsupportedSegmentCount":0,
      "outcome":"delivered"
    }]
    """

    let records = try JSONDecoder().decode(
        [VoiceDiagnosticRecord].self,
        from: Data(json.utf8)
    )

    #expect(records.count == 1)
    #expect(records[0].omittedUnsupportedWordCount == nil)
    #expect(records[0].wordAlignmentComplete == nil)
    #expect(records[0].evaluatedSegmentCount == nil)
    #expect(records[0].wordTimestampCount == nil)
    #expect(records[0].microphoneRecoveryCount == nil)
    #expect(records[0].vadSpeechFrameCount == nil)
    #expect(records[0].vadLongestSpeechRunFrames == nil)
    #expect(records[0].providerRetryOccurred == nil)
    #expect(records[0].lexicalCoverageEndSeconds == nil)
    #expect(records[0].trailingSpeechLikeFrameCount == nil)
    #expect(records[0].trailingSpeechLikeFraction == nil)
    #expect(records[0].integrityReasons == nil)
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
