import Foundation
import CryptoKit
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
            for: VoiceBridgeError.providerPermissionDenied(
                "model_access_denied"
            )
        ) == .reviewProviderPermission
    )
    #expect(
        TranscriptionFailurePolicy.disposition(
            for: VoiceBridgeError.invalidResponse(503, "Unavailable")
        ) == .retryTranscription
    )
}

@Test func providerRejectionOffersOneShotManualRecoveryForPreservedAudio() {
    let expected: [VoiceFailureAction] = [
        .retryTranscription,
        .openSettings,
        .playRecording,
        .saveRecording,
    ]

    #expect(
        ProviderFailureRecoveryPolicy.actions(
            for: .replaceCredential,
            hasRecoverableAudio: true
        ) == expected
    )
    #expect(
        ProviderFailureRecoveryPolicy.actions(
            for: .reviewProviderPermission,
            hasRecoverableAudio: true
        ) == expected
    )
    #expect(
        ProviderFailureRecoveryPolicy.actions(
            for: .replaceCredential,
            hasRecoverableAudio: false
        ) == [.openSettings]
    )
}

@Test func groqHTTP401RequiresCredentialReplacement() {
    let error = GroqProviderFailurePolicy.error(
        statusCode: 401,
        responseData: Data(
            #"{"error":{"message":"Invalid API Key","type":"invalid_request_error","code":"invalid_api_key"}}"#.utf8
        )
    )

    #expect(
        TranscriptionFailurePolicy.disposition(for: error)
            == .replaceCredential
    )
    #expect(error.providerHTTPStatus == 401)
    #expect(error.providerErrorCode == "invalid_authentication")
}

@Test func groqHTTP403RequiresPermissionReviewWithoutRejectingTheKey() {
    let error = GroqProviderFailurePolicy.error(
        statusCode: 403,
        responseData: Data(
            #"{"error":{"message":"Model blocked","type":"permission_error","code":"model_access_denied"}}"#.utf8
        )
    )

    guard case let VoiceBridgeError.providerPermissionDenied(code) = error else {
        Issue.record("Expected a permission-denied provider error")
        return
    }
    #expect(code == "model_access_denied")
    #expect(error.providerHTTPStatus == 403)
    #expect(error.providerErrorCode == "model_access_denied")
    #expect(
        TranscriptionFailurePolicy.disposition(for: error)
            == .reviewProviderPermission
    )
}

@Test func groqRateLimitsAndServerFailuresRemainRetryableAndPrivacySafe() {
    for statusCode in [429, 503] {
        let error = GroqProviderFailurePolicy.error(
            statusCode: statusCode,
            responseData: Data(
                #"{"error":{"message":"secret provider detail"}}"#.utf8
            )
        )
        #expect(
            TranscriptionFailurePolicy.disposition(for: error)
                == .retryTranscription
        )
        #expect(error.providerHTTPStatus == statusCode)
        #expect(!error.localizedDescription.contains("secret provider detail"))
    }
}

@Test func genericHTTPFailuresAreNotReportedAsGroqFailures() {
    let error = VoiceBridgeError.invalidResponse(503, "Interview Arc failed")

    #expect(error.providerHTTPStatus == nil)
    #expect(error.providerErrorCode == nil)
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

@Test func uncertainTranscriptPromotionRequiresRetainedAudioAndNoActivePromotion() {
    #expect(
        RecoveryTranscriptPromotionPolicy.canUse(
            recoveryStatus: .coverageUncertain,
            hasRetainedAudio: true,
            promotionInFlight: false
        )
    )
    #expect(
        !RecoveryTranscriptPromotionPolicy.canUse(
            recoveryStatus: .coverageUncertain,
            hasRetainedAudio: false,
            promotionInFlight: false
        )
    )
    #expect(
        !RecoveryTranscriptPromotionPolicy.canUse(
            recoveryStatus: .coverageUncertain,
            hasRetainedAudio: true,
            promotionInFlight: true
        )
    )
    #expect(
        !RecoveryTranscriptPromotionPolicy.canUse(
            recoveryStatus: nil,
            hasRetainedAudio: true,
            promotionInFlight: false
        )
    )
}

@Test func failureNoticePreservesItsExactRecoveryTranscriptIdentity() throws {
    let recordID = UUID()
    let notice = VoiceFailureNotice(
        kind: .transcription,
        title: "Transcription failed",
        message: "Recording preserved",
        detail: "Coverage was uncertain.",
        actions: [.retryTranscription, .playRecording, .saveRecording],
        recoveryTranscriptRecordID: recordID
    )

    let encoded = try JSONEncoder().encode(notice)
    let restored = try JSONDecoder().decode(
        VoiceFailureNotice.self,
        from: encoded
    )

    #expect(restored.recoveryTranscriptRecordID == recordID)
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

@Test func transcriptHistoryPersistsCoverageUncertainRecoveryStatus() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LocalTranscriptHistoryStore(directory: root)

    try await store.append(LocalTranscriptRecord(
        transcript: "Best available recovery text",
        editorText: "Best available recovery text",
        durationSeconds: 328,
        recoveryStatus: .coverageUncertain
    ))

    let records = try await store.records()
    #expect(records.first?.recoveryStatus == .coverageUncertain)
}

@Test func trustedRetryReplacesUncertainTextAndLinksTheCapture() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LocalTranscriptHistoryStore(directory: root)
    let recordID = UUID()

    try await store.append(LocalTranscriptRecord(
        id: recordID,
        transcript: "Partial recovery text",
        editorText: "Partial recovery text",
        durationSeconds: 328,
        recoveryStatus: .coverageUncertain
    ))
    _ = try await store.replaceTranscript(
        id: recordID,
        transcript: "Trusted complete retry",
        editorText: "Trusted complete retry with envelope",
        captureID: "capture-trusted"
    )

    let records = try await store.records()
    #expect(records.count == 1)
    #expect(records[0].transcript == "Trusted complete retry")
    #expect(records[0].editorText == "Trusted complete retry with envelope")
    #expect(records[0].captureID == "capture-trusted")
    #expect(records[0].recoveryStatus == nil)
}

@Test func linkedRecoveryKeepsStableVoiceIdentitiesAcrossRelaunchAndPromotion() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LocalTranscriptHistoryStore(directory: root)
    let context = LinkedTranscriptRecoveryContext(
        captureID: "capture-stable",
        turnID: "voice-stable",
        clipID: "clip-stable",
        checksum: String(repeating: "a", count: 64),
        activity: FocusedVoiceActivity(
            activityId: "activity-stable",
            questionId: "question-stable",
            specialty: .coding,
            interviewArcSpecialty: "leetcode",
            title: "Stable recovery",
            prompt: nil,
            topics: [],
            tags: [],
            companies: [],
            projects: [],
            vocabularyPackIds: [],
            speechTerms: []
        ),
        transcription: TranscriptionResult(
            text: "Recovered answer",
            words: [],
            durationSeconds: 4,
            chunkCount: 1
        ),
        occurredAt: Date(timeIntervalSince1970: 500)
    )
    let recordID = UUID()
    try await store.append(LocalTranscriptRecord(
        id: recordID,
        createdAt: Date(timeIntervalSince1970: 501),
        transcript: "Recovered answer",
        editorText: "Recovered answer",
        durationSeconds: 4,
        recoveryStatus: .coverageUncertain,
        linkedRecoveryContext: context
    ))

    let reloaded = try await store.records()
    #expect(reloaded.first?.linkedRecoveryContext == context)
    _ = try await store.replaceTranscript(
        id: recordID,
        transcript: "Recovered answer",
        editorText: "Recovered answer with stable envelope",
        captureID: context.captureID
    )
    let promoted = try await store.records()
    #expect(promoted.first?.captureID == "capture-stable")
    #expect(promoted.first?.recoveryStatus == nil)
    #expect(promoted.first?.linkedRecoveryContext == context)
}

@Test func explicitDiscardRemovesProtectedLinkedRecoveryEvidence() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try LocalTranscriptHistoryStore(directory: root)
    let context = LinkedTranscriptRecoveryContext(
        captureID: "capture-discard",
        turnID: "voice-discard",
        clipID: "clip-discard",
        checksum: String(repeating: "b", count: 64),
        activity: FocusedVoiceActivity(
            activityId: "activity-discard",
            questionId: nil,
            specialty: .coding,
            interviewArcSpecialty: "leetcode",
            title: "Discard recovery",
            prompt: nil,
            topics: [],
            tags: [],
            companies: [],
            projects: [],
            vocabularyPackIds: [],
            speechTerms: []
        ),
        transcription: TranscriptionResult(
            text: "Discard me",
            words: [],
            durationSeconds: 2,
            chunkCount: 1
        ),
        occurredAt: Date(timeIntervalSince1970: 600)
    )
    let recordID = UUID()
    try await store.append(LocalTranscriptRecord(
        id: recordID,
        createdAt: Date(timeIntervalSince1970: 601),
        transcript: "Discard me",
        editorText: "Discard me",
        durationSeconds: 2,
        recoveryStatus: .coverageUncertain,
        linkedRecoveryContext: context
    ))

    #expect(try await store.records().count == 1)
    try await store.discardRecovery(id: recordID)
    #expect(try await store.records().isEmpty)
}

@Test func editedRecoveryPromotionRebuildsChecksumAndTranscriptMetadata() {
    let context = LinkedTranscriptRecoveryContext(
        captureID: "capture-edited",
        turnID: "voice-edited",
        clipID: "clip-edited",
        checksum: String(repeating: "c", count: 64),
        activity: FocusedVoiceActivity(
            activityId: "activity-edited",
            questionId: nil,
            specialty: .coding,
            interviewArcSpecialty: "leetcode",
            title: "Edited recovery",
            prompt: nil,
            topics: [],
            tags: [],
            companies: [],
            projects: [],
            vocabularyPackIds: [],
            speechTerms: []
        ),
        transcription: TranscriptionResult(
            text: "Original partial text",
            words: [TranscriptWord(word: "Original", start: 0, end: 1)],
            durationSeconds: 3,
            chunkCount: 1
        ),
        occurredAt: Date(timeIntervalSince1970: 700)
    )
    let record = LocalTranscriptRecord(
        createdAt: Date(timeIntervalSince1970: 701),
        transcript: "Reviewed replacement text",
        editorText: "Reviewed replacement text",
        durationSeconds: 3,
        recoveryStatus: .coverageUncertain,
        linkedRecoveryContext: context
    )
    let pending = RecoveryPendingCaptureFactory.make(
        record: record,
        context: context,
        audioURL: URL(fileURLWithPath: "/tmp/recovery.m4a")
    )
    let expectedChecksum = SHA256.hash(
        data: Data(record.transcript.utf8)
    ).map { String(format: "%02x", $0) }.joined()

    #expect(pending.checksum == expectedChecksum)
    #expect(pending.transcript == record.transcript)
    #expect(pending.transcription.text == record.transcript)
    #expect(pending.transcription.words.isEmpty)
}

@Test func promotedLinkedRecoveryAudioCannotBePrunedOrClearedWhilePending() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let source = FileManager.default.temporaryDirectory
        .appending(path: "\(UUID().uuidString).m4a")
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: source)
    }
    try Data([1, 2, 3, 4]).write(to: source)
    let store = try LocalTranscriptHistoryStore(
        directory: root,
        retentionDuration: 10,
        retentionLimit: 1,
        diskBudgetBytes: 1
    )
    let createdAt = Date(timeIntervalSince1970: 100)
    let protected = try await store.append(
        LocalTranscriptRecord(
            createdAt: createdAt,
            transcript: "Protected linked recovery",
            editorText: "Protected linked recovery",
            durationSeconds: 4,
            captureID: "capture-protected",
            lifecycleProtected: true
        ),
        recordingURL: source,
        now: createdAt
    )
    let protectedAudio = await store.audioURL(for: protected)

    try await store.append(LocalTranscriptRecord(
        createdAt: createdAt.addingTimeInterval(20),
        transcript: "Newest ordinary transcript",
        editorText: "Newest ordinary transcript",
        durationSeconds: 1
    ), now: createdAt.addingTimeInterval(20))

    let retained = try await store.records(
        now: createdAt.addingTimeInterval(30)
    )
    #expect(retained.count == 1)
    #expect(retained.first?.captureID == "capture-protected")
    #expect(retained.first?.isLifecycleProtected == true)
    #expect(protectedAudio != nil)
    #expect(FileManager.default.fileExists(atPath: protectedAudio?.path ?? ""))

    try await store.delete(id: protected.id)
    try await store.clear()
    let afterClear = try await store.records(
        now: createdAt.addingTimeInterval(30)
    )
    #expect(afterClear.count == 1)
    #expect(FileManager.default.fileExists(atPath: protectedAudio?.path ?? ""))
}

@Test func retryingAnUncertainRecordReusesItsArchivedAudio() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let source = FileManager.default.temporaryDirectory
        .appending(path: "\(UUID().uuidString).m4a")
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: source)
    }
    try Data([4, 3, 2, 1]).write(to: source)
    let store = try LocalTranscriptHistoryStore(directory: root)
    let record = LocalTranscriptRecord(
        transcript: "Uncertain answer",
        editorText: "Uncertain answer",
        durationSeconds: 5,
        recoveryStatus: .coverageUncertain
    )
    let first = try await store.append(record, recordingURL: source)
    let archivedURL = await store.audioURL(for: first)
    #expect(archivedURL != nil)

    let replacement = LocalTranscriptRecord(
        id: first.id,
        createdAt: first.createdAt,
        transcript: "Uncertain answer after retry",
        editorText: "Uncertain answer after retry",
        durationSeconds: 5,
        recoveryStatus: .coverageUncertain,
        linkedRecoveryContext: first.linkedRecoveryContext
    )
    let retried = try await store.append(
        replacement,
        recordingURL: archivedURL
    )

    #expect(await store.audioURL(for: retried) == archivedURL)
    #expect(FileManager.default.fileExists(atPath: archivedURL?.path ?? ""))
    #expect(
        (try Data(contentsOf: archivedURL ?? URL(fileURLWithPath: "/missing")))
            == Data([4, 3, 2, 1])
    )
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
        activityTitle: "Course Schedule",
        retryDestination: .linked(
            activity: FocusedVoiceActivity(
                activityId: "activity-1",
                workbenchId: "workbench-1",
                questionId: "question-1",
                specialty: .coding,
                interviewArcSpecialty: "coding",
                title: "Course Schedule",
                prompt: nil,
                topics: [],
                tags: [],
                companies: [],
                projects: [],
                vocabularyPackIds: [],
                speechTerms: []
            ),
            startedAt: Date(timeIntervalSince1970: 90)
        )
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

@Test func recoverableRecordingReferenceDecodesBeforeRetryDestinationWasStored() throws {
    let json = """
    {
      "audioPath":"/tmp/preserved.m4a",
      "durationSeconds":42,
      "createdAt":100,
      "activityTitle":"Course Schedule"
    }
    """

    let reference = try JSONDecoder().decode(
        LocalRecoverableRecordingReference.self,
        from: Data(json.utf8)
    )

    #expect(reference.retryDestination == nil)
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
