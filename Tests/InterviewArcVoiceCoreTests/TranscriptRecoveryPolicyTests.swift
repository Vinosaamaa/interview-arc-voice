import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func groqAuthenticationFailuresAreNotRetryable() {
    #expect(
        TranscriptionFailurePolicy.disposition(
            for: VoiceBridgeError.invalidProviderCredential
        ) == .replaceCredential
    )
    #expect(
        TranscriptionFailurePolicy.disposition(
            for: VoiceBridgeError.invalidResponse(503, "Unavailable")
        ) == .retryTranscription
    )
}

@Test func aRejectedCredentialMustChangeBeforeRetry() {
    let policy = RejectedCredentialPolicy()

    #expect(!policy.canRetry(
        rejectedCredential: "rejected-key",
        submittedCredential: "rejected-key"
    ))
    #expect(policy.canRetry(
        rejectedCredential: "rejected-key",
        submittedCredential: "replacement-key"
    ))
}

@Test func menuInsertionUsesTheRememberedExternalEditor() {
    let policy = ManualInsertionTargetPolicy()

    #expect(
        policy.targetPID(
            surface: .menuBar,
            currentEligiblePID: 101,
            rememberedEligiblePID: 202
        ) == 202
    )
    #expect(
        policy.targetPID(
            surface: .floatingWidget,
            currentEligiblePID: 101,
            rememberedEligiblePID: 202
        ) == 101
    )
    #expect(
        policy.targetPID(
            surface: .menuBar,
            currentEligiblePID: nil,
            rememberedEligiblePID: nil
        ) == nil
    )
}

@Test func transcriptHistoryIsNewestFirstBoundedAndExpires() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date(timeIntervalSince1970: 10_000_000)
    let store = try LocalTranscriptHistoryStore(
        directory: root,
        retentionDuration: 24 * 60 * 60,
        retentionLimit: 5
    )

    for offset in 0..<7 {
        try await store.append(
            LocalTranscriptRecord(
                id: UUID(),
                createdAt: now.addingTimeInterval(Double(offset)),
                transcript: "Transcript \(offset)",
                editorText: "Payload \(offset)",
                durationSeconds: Double(offset + 1)
            ),
            now: now.addingTimeInterval(Double(offset))
        )
    }

    let current = try await store.records(now: now.addingTimeInterval(7))
    #expect(current.count == 5)
    #expect(current.map(\.transcript) == [
        "Transcript 6",
        "Transcript 5",
        "Transcript 4",
        "Transcript 3",
        "Transcript 2",
    ])

    let expired = try await store.records(
        now: now.addingTimeInterval(24 * 60 * 60 + 7)
    )
    #expect(expired.isEmpty)

    let attributes = try FileManager.default.attributesOfItem(
        atPath: store.fileURL.path
    )
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}
