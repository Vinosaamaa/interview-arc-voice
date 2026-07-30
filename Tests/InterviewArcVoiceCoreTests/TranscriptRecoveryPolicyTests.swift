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

@Test func audioRecoveryActionsAppearOnlyAfterAudioHydration() {
    let actions: [VoiceFailureAction] = [
        .openSettings,
        .playRecording,
        .saveRecording,
    ]

    #expect(
        RecoveryActionAvailabilityPolicy.availableActions(
            from: actions,
            hasRecoverableAudio: false
        ) == [.openSettings]
    )
    #expect(
        RecoveryActionAvailabilityPolicy.availableActions(
            from: actions,
            hasRecoverableAudio: true
        ) == actions
    )
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

@Test func menuInsertionWaitsForTheMenuWindowToActuallyDismiss() {
    #expect(
        !MenuInsertionDismissalPolicy.hasDismissed(
            windowIsVisible: true,
            windowIsKey: true
        )
    )
    #expect(
        MenuInsertionDismissalPolicy.hasDismissed(
            windowIsVisible: false,
            windowIsKey: true
        )
    )
    #expect(
        !MenuInsertionDismissalPolicy.hasDismissed(
            windowIsVisible: true,
            windowIsKey: false
        )
    )
    #expect(MenuInsertionDismissalPolicy.maximumChecks > 0)
}

@Test func transcriptHistoryIsNewestFirstBoundedAndExpires() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    let now = Date(timeIntervalSince1970: 10_000_000)
    let store = try LocalTranscriptHistoryStore(
        directory: root,
        retentionDuration: 24 * 60 * 60
    )

    for offset in 0..<23 {
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

    let current = try await store.records(now: now.addingTimeInterval(23))
    #expect(current.count == 20)
    #expect(current.first?.transcript == "Transcript 22")
    #expect(current.last?.transcript == "Transcript 3")

    let expired = try await store.records(
        now: now.addingTimeInterval(24 * 60 * 60 + 23)
    )
    #expect(expired.isEmpty)

    let attributes = try FileManager.default.attributesOfItem(
        atPath: store.fileURL.path
    )
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func recoverableRecordingReferenceSurvivesRelaunchAndRejectsUnsafePaths() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let recordings = root.appending(path: "Recordings", directoryHint: .isDirectory)
    let recovery = root.appending(path: "Recovery", directoryHint: .isDirectory)
    let outside = FileManager.default.temporaryDirectory
        .appending(path: "\(UUID().uuidString).m4a")
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }

    try FileManager.default.createDirectory(
        at: recordings,
        withIntermediateDirectories: true
    )
    let audio = recordings.appending(path: "preserved.m4a")
    try Data([0, 1, 2, 3]).write(to: audio)
    try Data([9, 8, 7]).write(to: outside)

    let store = try LocalRecoverableRecordingStore(directory: recovery)
    let reference = LocalRecoverableRecordingReference(
        audioURL: audio,
        durationSeconds: 42,
        createdAt: Date(timeIntervalSince1970: 100),
        activityTitle: "Course Schedule"
    )
    try store.save(reference)

    #expect(
        try store.load(allowedDirectories: [recordings]) == reference
    )
    let attributes = try FileManager.default.attributesOfItem(
        atPath: store.fileURL.path
    )
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

    let unsafe = LocalRecoverableRecordingReference(
        audioURL: outside,
        durationSeconds: 10
    )
    try store.save(unsafe)
    #expect(try store.load(allowedDirectories: [recordings]) == nil)
}

@Test func recoverableRecordingMigrationUsesTheNewestNonemptyAudioFile() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let recordings = root.appending(path: "Recordings", directoryHint: .isDirectory)
    let transcription = root.appending(path: "Transcription", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }

    try FileManager.default.createDirectory(
        at: recordings,
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(
        at: transcription,
        withIntermediateDirectories: true
    )
    let older = recordings.appending(path: "older.m4a")
    let newest = transcription.appending(path: "newest.m4a")
    let empty = transcription.appending(path: "empty.m4a")
    try Data([1]).write(to: older)
    try Data([2]).write(to: newest)
    try Data().write(to: empty)
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 100)],
        ofItemAtPath: older.path
    )
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 200)],
        ofItemAtPath: newest.path
    )
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 300)],
        ofItemAtPath: empty.path
    )

    #expect(
        LocalRecoverableRecordingStore.discoverNewestAudio(
            in: [recordings, transcription]
        ) == newest
    )
}
