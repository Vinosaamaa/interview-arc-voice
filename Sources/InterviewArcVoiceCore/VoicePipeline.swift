import CryptoKit
import Foundation

private enum LocalAudioSourceLoss: Error {
    case missing
    case unreadable

    var serverReason: String {
        switch self {
        case .missing: "local_source_missing"
        case .unreadable: "local_source_unreadable"
        }
    }
}

enum RecoveryPendingCaptureFactory {
    static func make(
        record: LocalTranscriptRecord,
        context: LinkedTranscriptRecoveryContext,
        audioURL: URL
    ) -> PendingVoiceCapture {
        let text = record.transcript
        let checksum = SHA256.hash(data: Data(text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let original = context.transcription
        let transcription = original.text == text
            ? original
            : TranscriptionResult(
                text: text,
                words: [],
                segments: nil,
                durationSeconds: record.durationSeconds,
                chunkCount: original.chunkCount,
                timing: original.timing,
                engine: original.engine,
                model: original.model,
                localInferenceSeconds: original.localInferenceSeconds,
                localPromptTokenCount: original.localPromptTokenCount
            )
        return PendingVoiceCapture(
            id: context.captureID,
            turnID: context.turnID,
            clipID: context.clipID,
            checksum: checksum,
            activity: context.activity,
            transcript: text,
            audioURL: audioURL,
            durationSeconds: record.durationSeconds,
            occurredAt: context.occurredAt,
            transcription: transcription,
            createdAt: record.createdAt,
            localState: .insertedRegistrationPending
        )
    }
}

public enum VoiceDeliveryComponent: String, CaseIterable, Sendable {
    case insertion
    case transcript
    case audio
    case coach
}

public enum VoiceDeliveryComponentState: Equatable, Sendable {
    case working
    case complete
    case queued
    case needsAttention
}

public struct VoicePipelineUpdate: Equatable, Sendable {
    public let component: VoiceDeliveryComponent
    public let state: VoiceDeliveryComponentState

    public init(component: VoiceDeliveryComponent, state: VoiceDeliveryComponentState) {
        self.component = component
        self.state = state
    }
}

public struct VoicePipelineResult: Equatable, Sendable {
    public let captureID: String
    public let turnID: String
    public let transcript: String
    public let clipID: String?
    public let capturePersisted: Bool
    public let audioUploaded: Bool
    public let deliveryCoachQueued: Bool
    public let transcriptionChunkCount: Int
    public let omittedUnsupportedSegmentCount: Int
    public let omittedUnsupportedWordCount: Int
    public let wordAlignmentComplete: Bool
    public let evaluatedSegmentCount: Int
    public let wordTimestampCount: Int
    public let segmentValidationSeconds: Double
    public let transcriptionWasRetried: Bool
    public let providerLexicalCoverageEndSeconds: Double?
    public let trailingSpeechLikeFrameCount: Int?
    public let trailingSpeechLikeFraction: Double?
    public let transcriptionTiming: TranscriptionTiming?
    public let transcriptionEngine: String?
    public let transcriptionModel: String?
    public let localInferenceSeconds: Double?
    public let localPromptTokenCount: Int?
    public let coverageUncertain: Bool

    public var hasQueuedRetry: Bool {
        !capturePersisted || !audioUploaded || !deliveryCoachQueued
    }
}

public actor VoicePipeline {
    private let api: InterviewArcAPIClient
    private let transcriber: any SpeechTranscribing
    private let reliableTranscriber: ReliableSpeechTranscriber
    private let codex: CodexBridge
    private let vocabularyResolver: VocabularyResolver
    private let retryQueue: VoiceRetryQueue
    private let pendingCaptureStore: PendingVoiceCaptureStore
    private let transcriptHistoryStore: LocalTranscriptHistoryStore?
    private let temporaryDirectory: URL
    private let workspaceURL: URL
    private let interviewArcToken: String

    public init(
        api: InterviewArcAPIClient,
        transcriber: any SpeechTranscribing,
        codex: CodexBridge,
        vocabularyResolver: VocabularyResolver,
        retryQueue: VoiceRetryQueue,
        pendingCaptureStore: PendingVoiceCaptureStore,
        transcriptHistoryStore: LocalTranscriptHistoryStore? = nil,
        temporaryDirectory: URL,
        workspaceURL: URL,
        interviewArcToken: String
    ) {
        self.api = api
        self.transcriber = transcriber
        reliableTranscriber = ReliableSpeechTranscriber(base: transcriber)
        self.codex = codex
        self.vocabularyResolver = vocabularyResolver
        self.retryQueue = retryQueue
        self.pendingCaptureStore = pendingCaptureStore
        self.transcriptHistoryStore = transcriptHistoryStore
        self.temporaryDirectory = temporaryDirectory
        self.workspaceURL = workspaceURL
        self.interviewArcToken = interviewArcToken
    }

    public func process(
        recordingURL: URL,
        durationSeconds: Double,
        activity: FocusedVoiceActivity,
        occurredAt: Date = Date(),
        speechEvidence: SpeechEvidenceResult? = nil,
        protectionMode: SpeechProtectionMode = .basic,
        transcriptReady: @escaping @Sendable (VoiceCaptureEnvelope) async -> Void = { _ in },
        progress: @escaping @Sendable (VoicePipelineUpdate) async -> Void = { _ in }
    ) async throws -> VoicePipelineResult {
        await progress(.init(component: .transcript, state: .working))
        let vocabulary = vocabularyResolver.resolve(activity.vocabularyContext)
        let reliable = try await reliableTranscriber.transcribe(
            fileURL: recordingURL,
            prompt: vocabulary.prompt,
            temporaryDirectory: temporaryDirectory,
            audioDurationSeconds: durationSeconds,
            speechEvidence: speechEvidence,
            protectionMode: protectionMode
        )
        let transcription = reliable.transcription
        let captureID = "capture-\(UUID().uuidString.lowercased())"
        let turnID = "voice-\(UUID().uuidString.lowercased())"
        let requestedClipID = "clip-\(UUID().uuidString.lowercased())"
        let checksum = SHA256.hash(data: Data(transcription.text.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let pending = PendingVoiceCapture(
            id: captureID,
            turnID: turnID,
            clipID: requestedClipID,
            checksum: checksum,
            activity: activity,
            transcript: transcription.text,
            audioURL: recordingURL,
            durationSeconds: durationSeconds,
            occurredAt: occurredAt,
            transcription: transcription,
            createdAt: Date(),
            localState: .insertedRegistrationPending
        )
        try await pendingCaptureStore.save(pending)
        await progress(.init(component: .transcript, state: .complete))
        await transcriptReady(VoiceCaptureEnvelope(
            captureID: captureID,
            activityID: activity.activityId,
            turnID: turnID,
            transcript: transcription.text
        ))
        try? await pendingCaptureStore.update(id: captureID) {
            $0.transcriptInsertedAt = Date()
        }
        // Registration is deliberately outside the foreground insertion
        // boundary. Stable IDs and the permission-0600 record already make the
        // envelope recoverable; server synchronization continues single-flight.
        Task { await self.registerPendingCapture(captureID: captureID) }
        await progress(.init(component: .audio, state: .queued))
        await progress(.init(component: .coach, state: .queued))
        return VoicePipelineResult(
            captureID: captureID,
            turnID: turnID,
            transcript: transcription.text,
            clipID: nil,
            capturePersisted: true,
            audioUploaded: false,
            deliveryCoachQueued: false,
            transcriptionChunkCount: transcription.chunkCount,
            omittedUnsupportedSegmentCount: reliable.omittedUnsupportedSegmentCount,
            omittedUnsupportedWordCount: reliable.omittedUnsupportedWordCount,
            wordAlignmentComplete: reliable.wordAlignmentComplete,
            evaluatedSegmentCount: reliable.evaluatedSegmentCount,
            wordTimestampCount: reliable.wordTimestampCount,
            segmentValidationSeconds: reliable.segmentValidationSeconds,
            transcriptionWasRetried: reliable.wasRetried,
            providerLexicalCoverageEndSeconds:
                reliable.providerLexicalCoverageEndSeconds,
            trailingSpeechLikeFrameCount:
                reliable.trailingSpeechLikeFrameCount,
            trailingSpeechLikeFraction:
                reliable.trailingSpeechLikeFraction,
            transcriptionTiming: transcription.timing,
            transcriptionEngine: reliable.engine,
            transcriptionModel: reliable.model,
            localInferenceSeconds: reliable.localInferenceSeconds,
            localPromptTokenCount: reliable.localPromptTokenCount,
            coverageUncertain: reliable.coverageUncertain
        )
    }

    public func promoteRecoveryTranscript(
        record: LocalTranscriptRecord,
        audioURL: URL
    ) async throws -> VoiceCaptureEnvelope {
        guard let context = record.linkedRecoveryContext else {
            throw VoiceBridgeError.invalidResponse(0, "This recovery transcript is not linked to an activity.")
        }
        let pending = RecoveryPendingCaptureFactory.make(
            record: record,
            context: context,
            audioURL: audioURL
        )
        try await pendingCaptureStore.save(pending)
        Task { await self.registerPendingCapture(captureID: context.captureID) }
        return VoiceCaptureEnvelope(
            captureID: context.captureID,
            activityID: context.activity.activityId,
            turnID: context.turnID,
            transcript: record.transcript
        )
    }

    public func retryPending(
        force: Bool = true,
        activityID: String? = nil
    ) async -> Int {
        var completed = await reconcilePendingCaptures(
            force: force,
            activityID: activityID
        )
        guard let items = try? await retryQueue.items() else { return completed }
        for item in items where activityID == nil
            || item.activity.activityId == activityID {
            do {
                switch item.kind {
                case .capturePersistence:
                    _ = try await api.persistCapture(
                        activity: item.activity,
                        turnID: item.turnID,
                        transcript: item.transcript,
                        occurredAt: item.occurredAt ?? item.createdAt
                    )
                    do {
                        let upload = try await api.uploadAudio(
                            fileURL: item.audioURL,
                            clipID: item.clipID ?? "clip-\(UUID().uuidString.lowercased())",
                            activityID: item.activity.activityId,
                            turnID: item.turnID,
                            durationSeconds: item.durationSeconds
                        )
                        let analysisID = item.analysisID ?? "delivery-\(UUID().uuidString.lowercased())"
                        do {
                            try await queueAndRunDeliveryCoach(item: item, clipID: upload.clipId, analysisID: analysisID)
                        } catch {
                            try await enqueue(
                                kind: .deliveryCoach,
                                item: item,
                                clipID: upload.clipId,
                                analysisID: analysisID,
                                error: error
                            )
                        }
                    } catch {
                        try await enqueue(kind: .audioUpload, item: item, error: error)
                    }
                case .specialistDelivery:
                    // Version 0.2 and earlier queued hidden specialist delivery.
                    // Direct cursor insertion supersedes it; discard the legacy
                    // retry without sending a duplicate visible answer.
                    break
                case .audioUpload:
                    let upload = try await api.uploadAudio(
                        fileURL: item.audioURL,
                        clipID: item.clipID ?? "clip-\(UUID().uuidString.lowercased())",
                        activityID: item.activity.activityId,
                        turnID: item.turnID,
                        durationSeconds: item.durationSeconds
                    )
                    let analysisID = item.analysisID ?? "delivery-\(UUID().uuidString.lowercased())"
                    do {
                        try await queueAndRunDeliveryCoach(item: item, clipID: upload.clipId, analysisID: analysisID)
                    } catch {
                        try await enqueue(
                            kind: .deliveryCoach,
                            item: item,
                            clipID: upload.clipId,
                            analysisID: analysisID,
                            error: error
                        )
                    }
                case .deliveryCoach:
                    guard let clipID = item.clipID, let analysisID = item.analysisID else { continue }
                    try await codex.runDeliveryCoach(
                        analysisID: analysisID,
                        activity: item.activity,
                        clipID: clipID,
                        turnID: item.turnID,
                        transcript: item.transcript,
                        transcription: item.transcription,
                        audioURL: item.audioURL,
                        workspaceURL: workspaceURL,
                        interviewArcToken: interviewArcToken
                    )
                }
                try await retryQueue.remove(id: item.id)
                completed += 1
            } catch {
                // Keep the original durable retry item for the next attempt.
            }
        }
        return completed
    }

    public func pendingCaptures() async -> [PendingVoiceCapture] {
        (try? await pendingCaptureStore.items()) ?? []
    }

    public func removeSettledCaptures(
        outsideWorkbenchID currentWorkbenchID: String?
    ) async {
        guard let captures = try? await pendingCaptureStore.items() else {
            return
        }
        for capture in captures {
            guard VoiceCaptureLifecyclePolicy().canRemoveSettledMetadata(
                capture,
                currentWorkbenchID: currentWorkbenchID
            ) else {
                continue
            }
            try? await pendingCaptureStore.remove(
                id: capture.id,
                deleteAudio: false
            )
        }
    }

    public func localPendingCaptureCount() async -> Int {
        (try? await pendingCaptureStore.items().count) ?? 0
    }

    public func legacyVoiceOrphans() async -> [LegacyVoiceCapture] {
        (try? await api.legacyVoiceOrphans()) ?? []
    }

    public func deleteLegacyVoiceCapture(clipID: String) async throws {
        try await api.deleteLegacyCapture(clipID: clipID)
    }

    public func resolvePendingCapture(
        captureID: String,
        attach: Bool
    ) async throws {
        if attach {
            _ = try await api.decideIntent(
                captureID: captureID,
                decision: "activity_related",
                reason: "The user explicitly attached this pending capture."
            )
        } else {
            _ = try await api.decideIntent(
                captureID: captureID,
                decision: "unrelated",
                reason: "The user explicitly deleted this pending capture."
            )
            try await api.deleteCapture(captureID: captureID)
            try await pendingCaptureStore.remove(id: captureID, deleteAudio: true)
        }
    }

    public func acknowledgeAudioLoss(captureID: String) async throws {
        guard let capture = try await pendingCaptureStore.item(id: captureID) else {
            return
        }
        _ = try await api.acknowledgeAudioLoss(
            captureID: capture.id,
            clipID: capture.clipID
        )
        try await pendingCaptureStore.update(id: capture.id) {
            $0.localState = .audioLostAcknowledged
            $0.nextAttemptAt = nil
            $0.lastErrorCode = "audio_lost_acknowledged"
        }
    }

    private func reconcilePendingCaptures(
        force: Bool = false,
        activityID: String? = nil
    ) async -> Int {
        let now = Date()
        let retryPolicy = VoiceCaptureRetryPolicy()
        guard let allCaptures = try? await pendingCaptureStore.items() else { return 0 }
        let captures = allCaptures.filter {
            activityID == nil || $0.activity.activityId == activityID
        }
        guard !captures.isEmpty else { return 0 }
        var completed = 0
        guard var intents = try? await api.retainedIntents() else {
            return completed
        }
        let idsToRegister = PendingCaptureRegistrationPolicy().captureIDsToRegister(
            localCaptureIDs: captures.map(\.id),
            serverCaptureIDs: intents.map(\.captureId)
        )
        if !idsToRegister.isEmpty {
            let capturesByID = Dictionary(uniqueKeysWithValues: captures.map { ($0.id, $0) })
            for captureID in idsToRegister {
                guard let capture = capturesByID[captureID] else { continue }
                guard retryPolicy.isDue(capture, now: now) else { continue }
                do {
                    let registered = try await api.registerIntent(capture)
                    intents.removeAll { $0.captureId == captureID }
                    intents.append(registered.intent)
                    try? await pendingCaptureStore.update(id: captureID) {
                        $0.localState = .waitingForSpecialist
                        $0.retryAttempt = 0
                        $0.nextAttemptAt = nil
                        $0.lastErrorCode = nil
                        $0.registrationCompletedAt = now
                    }
                } catch let error as InterviewArcAPIError
                    where error.code == "voice_capture_identity_conflict" || !error.retryable {
                    try? await pendingCaptureStore.update(id: captureID) {
                        $0.localState = .quarantinedConflict
                        $0.nextAttemptAt = nil
                        $0.lastErrorCode = error.code ?? "permanent_registration_failure"
                    }
                } catch {
                    let attempt = (capture.retryAttempt ?? 0) + 1
                    try? await pendingCaptureStore.update(id: captureID) {
                        $0.localState = .insertedRegistrationPending
                        $0.retryAttempt = attempt
                        $0.nextAttemptAt = retryPolicy.nextAttempt(attempt: attempt, now: now)
                        $0.lastErrorCode = "transient_registration_failure"
                    }
                }
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: intents.map { ($0.captureId, $0) })
        let receiptStatuses = Set([
            "activity_related", "accepted",
        ])
        let receiptActivityIDs = Set(intents.compactMap { intent in
            receiptStatuses.contains(intent.status) ? intent.activityId : nil
        })
        var blockersByCapture: [String: VoiceDeliveryBlocker] = [:]
        var blockerErrorsByActivity: [String: InterviewArcAPIError] = [:]
        for activityID in receiptActivityIDs {
            do {
                let response = try await api.deliveryBlockers(activityID: activityID)
                for blocker in response.blockers {
                    blockersByCapture[blocker.captureId] = blocker
                }
            } catch let error as InterviewArcAPIError {
                blockerErrorsByActivity[activityID] = error
            } catch let error as URLError {
                blockerErrorsByActivity[activityID] = InterviewArcAPIError(
                    statusCode: 0,
                    message: error.localizedDescription,
                    code: "network_transport_failure",
                    retryable: true
                )
            } catch {
                blockerErrorsByActivity[activityID] = InterviewArcAPIError(
                    statusCode: 0,
                    message: error.localizedDescription,
                    code: "delivery_receipt_read_failed",
                    retryable: true
                )
            }
        }
        for capture in captures {
            if capture.localState == .complete
                || capture.localState == .audioLostAcknowledged
                || capture.localState == .audioLostNeedsAcknowledgement {
                continue
            }
            if capture.localState == .needsAttention
                && (!force || !VoiceLegacyDeliveryRecoveryPolicy().permitsForcedRetry(capture)) {
                continue
            }
            guard let intent = byID[capture.id] else { continue }
            if intent.status == "quarantined_conflict" {
                try? await pendingCaptureStore.update(id: capture.id) {
                    $0.localState = .quarantinedConflict
                    $0.nextAttemptAt = nil
                    $0.lastErrorCode = "voice_response_group_conflict"
                    $0.lastErrorRetryable = false
                }
                continue
            }
            if receiptStatuses.contains(intent.status),
               let receiptError = blockerErrorsByActivity[intent.activityId] {
                try? await recordDeliveryFailure(
                    receiptError,
                    capture: capture,
                    now: now,
                    manualAttempt: force
                )
                continue
            }
            do {
                switch VoiceCaptureLifecyclePolicy().expiryAction(
                    capture: capture,
                    serverStatus: intent.status,
                    now: now
                ) {
                    case .expirePendingOnServer:
                        _ = try await api.expireIntent(capture)
                        try await pendingCaptureStore.remove(
                            id: capture.id,
                            deleteAudio: true
                        )
                        completed += 1
                        continue
                    case .deleteExcludedOnServer:
                        try await api.deleteCapture(captureID: capture.id)
                        try await pendingCaptureStore.remove(
                            id: capture.id,
                            deleteAudio: true
                        )
                        completed += 1
                        continue
                    case .removeTerminalLocalEvidence:
                        try await pendingCaptureStore.remove(
                            id: capture.id,
                            deleteAudio: true
                        )
                        completed += 1
                        continue
                    case .none:
                        break
                }
                switch intent.status {
                case "pending":
                    try await pendingCaptureStore.update(id: capture.id) {
                        $0.localState = .waitingForSpecialist
                        $0.nextAttemptAt = nil
                        $0.lastErrorCode = nil
                    }
                case "uncertain":
                    try await pendingCaptureStore.update(id: capture.id) {
                        $0.localState = .needsDecision
                        $0.nextAttemptAt = nil
                    }
                case "activity_related":
                    if !force,
                       let nextAttemptAt = capture.nextAttemptAt,
                       nextAttemptAt > now {
                        continue
                    }
                    switch VoiceDeliveryReceiptPolicy().action(
                        for: blockersByCapture[capture.id]
                    ) {
                    case .quarantine(let responseGroupID, let responseGroupDigest):
                        try await pendingCaptureStore.update(id: capture.id) {
                            $0.localState = .quarantinedConflict
                            $0.nextAttemptAt = nil
                            $0.lastErrorCode = "voice_response_group_conflict"
                            $0.lastErrorRetryable = false
                            $0.responseGroupID = responseGroupID
                            $0.responseGroupDigest = responseGroupDigest
                        }
                        continue
                    case .resumeAfterTranscript(let responseGroupID, let responseGroupDigest):
                        try await pendingCaptureStore.update(id: capture.id) {
                            $0.localState = .acceptedDelivering
                            $0.deliveryStage = .transcriptCommitted
                            $0.transcriptCommittedAt = $0.transcriptCommittedAt ?? now
                            $0.responseGroupID = responseGroupID
                            $0.responseGroupDigest = responseGroupDigest
                            Self.clearDeliveryFailure(&$0)
                        }
                    case .deliverTranscript:
                        try await pendingCaptureStore.update(id: capture.id) {
                            $0.localState = .acceptedDelivering
                            $0.deliveryStage = .transcriptPending
                        }
                        _ = try await api.persistCapture(
                            activity: capture.activity,
                            turnID: capture.turnID,
                            transcript: capture.transcript,
                            occurredAt: capture.occurredAt,
                            captureID: capture.id,
                            checksum: capture.checksum
                        )
                        try await pendingCaptureStore.update(id: capture.id) {
                            $0.deliveryStage = .transcriptCommitted
                            $0.transcriptCommittedAt = $0.transcriptCommittedAt ?? now
                            Self.clearDeliveryFailure(&$0)
                        }
                    }
                    try await completeAcceptedCapture(capture)
                    completed += 1
                case "accepted":
                    if !force,
                       let nextAttemptAt = capture.nextAttemptAt,
                       nextAttemptAt > now {
                        continue
                    }
                    let receipt = blockersByCapture[capture.id]
                    try await pendingCaptureStore.update(id: capture.id) {
                        $0.deliveryStage = $0.deliveryStage ?? .transcriptCommitted
                        $0.transcriptCommittedAt = $0.transcriptCommittedAt ?? now
                        $0.responseGroupID = receipt?.responseTurnId ?? $0.responseGroupID
                        $0.responseGroupDigest = receipt?.groupDigest ?? $0.responseGroupDigest
                    }
                    try await completeAcceptedCapture(capture)
                    completed += 1
                case "unrelated":
                    try await pendingCaptureStore.update(id: capture.id) {
                        $0.localState = .excludedGracePeriod
                        $0.nextAttemptAt = nil
                    }
                case "deleting":
                    try await pendingCaptureStore.update(id: capture.id) {
                        $0.localState = .excludedGracePeriod
                        $0.nextAttemptAt = nil
                    }
                case "deleted":
                    try await pendingCaptureStore.remove(id: capture.id, deleteAudio: true)
                    completed += 1
                case "discarded_unclassified", "expired_unclassified":
                    try await pendingCaptureStore.remove(id: capture.id, deleteAudio: true)
                    completed += 1
                case "quarantined_conflict":
                    try await pendingCaptureStore.update(id: capture.id) {
                        $0.localState = .quarantinedConflict
                        $0.nextAttemptAt = nil
                        $0.lastErrorCode = "voice_response_group_conflict"
                        $0.lastErrorRetryable = false
                    }
                default:
                    break
                }
            } catch let error as InterviewArcAPIError {
                let latest = (try? await pendingCaptureStore.item(id: capture.id)) ?? capture
                try? await recordDeliveryFailure(
                    error,
                    capture: latest,
                    now: now,
                    manualAttempt: force
                )
            } catch let error as URLError {
                let latest = (try? await pendingCaptureStore.item(id: capture.id)) ?? capture
                try? await recordDeliveryFailure(
                    InterviewArcAPIError(
                        statusCode: 0,
                        message: error.localizedDescription,
                        code: "network_transport_failure",
                        retryable: true
                    ),
                    capture: latest,
                    now: now,
                    manualAttempt: force
                )
            } catch let error as VoiceBridgeError {
                let latest = (try? await pendingCaptureStore.item(id: capture.id)) ?? capture
                try? await recordDeliveryFailure(
                    InterviewArcAPIError(
                        statusCode: 0,
                        message: error.localizedDescription,
                        code: "codex_unavailable",
                        retryable: true
                    ),
                    capture: latest,
                    now: now,
                    manualAttempt: force
                )
            } catch {
                if let retryable = VoiceDeliveryErrorPolicy().retryableAPIError(for: error) {
                    let latest = (try? await pendingCaptureStore.item(id: capture.id)) ?? capture
                    try? await recordDeliveryFailure(
                        retryable,
                        capture: latest,
                        now: now,
                        manualAttempt: force
                    )
                } else {
                    try? await pendingCaptureStore.update(id: capture.id) {
                        $0.localState = .needsAttention
                        $0.nextAttemptAt = nil
                        $0.lastErrorCode = "terminal_delivery_validation_failure"
                        $0.lastErrorStatusCode = nil
                        $0.lastErrorMessage = error.localizedDescription
                        $0.lastErrorRetryable = false
                    }
                }
            }
        }
        return completed
    }

    private func registerPendingCapture(captureID: String) async {
        guard let captures = try? await pendingCaptureStore.items(),
              let capture = captures.first(where: { $0.id == captureID }) else {
            return
        }
        do {
            _ = try await api.registerIntent(capture)
            try await pendingCaptureStore.update(id: captureID) {
                $0.localState = .waitingForSpecialist
                $0.retryAttempt = 0
                $0.nextAttemptAt = nil
                $0.lastErrorCode = nil
                $0.registrationCompletedAt = Date()
            }
        } catch let error as InterviewArcAPIError
            where error.code == "voice_capture_identity_conflict" || !error.retryable {
            try? await pendingCaptureStore.update(id: captureID) {
                $0.localState = .quarantinedConflict
                $0.nextAttemptAt = nil
                $0.lastErrorCode = error.code ?? "permanent_registration_failure"
            }
        } catch {
            let retryPolicy = VoiceCaptureRetryPolicy()
            let attempt = (capture.retryAttempt ?? 0) + 1
            try? await pendingCaptureStore.update(id: captureID) {
                $0.localState = .insertedRegistrationPending
                $0.retryAttempt = attempt
                $0.nextAttemptAt = retryPolicy.nextAttempt(attempt: attempt)
                $0.lastErrorCode = "transient_registration_failure"
            }
        }
    }

    private func completeAcceptedCapture(
        _ capture: PendingVoiceCapture
    ) async throws {
        do {
            var current = (try await pendingCaptureStore.item(id: capture.id)) ?? capture
            let analysisID = "delivery-\(capture.id)"
            if current.audioAvailableAt == nil {
                if let loss = Self.localAudioSourceLoss(capture.audioURL) {
                    throw loss
                }
                try await pendingCaptureStore.update(id: capture.id) {
                    $0.deliveryStage = .audioPending
                }
                let upload = try await api.uploadAudio(
                    fileURL: capture.audioURL,
                    clipID: capture.clipID,
                    activityID: capture.activity.activityId,
                    turnID: capture.turnID,
                    durationSeconds: capture.durationSeconds,
                    captureID: capture.id
                )
                guard upload.clipId == capture.clipID else {
                    throw InterviewArcAPIError(
                        statusCode: 409,
                        message: "The audio acknowledgement changed the stable clip identity.",
                        code: "voice_capture_identity_conflict",
                        retryable: false
                    )
                }
                let completedAt = Date()
                try await pendingCaptureStore.update(id: capture.id) {
                    $0.deliveryStage = .audioAvailable
                    $0.audioAvailableAt = completedAt
                    Self.clearDeliveryFailure(&$0)
                }
                current.audioAvailableAt = completedAt
            }
            if current.coachQueuedAt == nil {
                try await pendingCaptureStore.update(id: capture.id) {
                    $0.deliveryStage = .coachPending
                }
                _ = try await api.queueDelivery(
                    analysisID: analysisID,
                    activity: capture.activity,
                    clipID: capture.clipID,
                    turnID: capture.turnID
                )
                let queuedAt = Date()
                try await pendingCaptureStore.update(id: capture.id) {
                    $0.deliveryStage = .coachQueued
                    $0.coachQueuedAt = queuedAt
                    Self.clearDeliveryFailure(&$0)
                }
                current.coachQueuedAt = queuedAt
            }
            if current.coachCompletedAt == nil {
                try await codex.runDeliveryCoach(
                    analysisID: analysisID,
                    activity: capture.activity,
                    clipID: capture.clipID,
                    turnID: capture.turnID,
                    transcript: capture.transcript,
                    transcription: capture.transcription,
                    audioURL: capture.audioURL,
                    workspaceURL: workspaceURL,
                    interviewArcToken: interviewArcToken
                )
                let completedAt = Date()
                try await pendingCaptureStore.update(id: capture.id) {
                    $0.coachCompletedAt = completedAt
                    Self.clearDeliveryFailure(&$0)
                }
            }
            let retainedInHistory = try await transcriptHistoryStore?
                .adoptLinkedAudio(
                    captureID: capture.id,
                    recordingURL: capture.audioURL
                ) ?? false
            if !retainedInHistory,
               FileManager.default.fileExists(atPath: capture.audioURL.path) {
                try FileManager.default.removeItem(at: capture.audioURL)
            }
            try await pendingCaptureStore.update(id: capture.id) {
                $0.localState = .complete
                $0.deliveryStage = .complete
                $0.retryAttempt = 0
                $0.retryStartedAt = nil
                $0.nextAttemptAt = nil
                $0.lastErrorCode = nil
                $0.lastErrorStatusCode = nil
                $0.lastErrorMessage = nil
                $0.lastErrorRetryable = nil
            }
        } catch let loss as LocalAudioSourceLoss {
            do {
                _ = try await api.reportAudioLoss(
                    captureID: capture.id,
                    clipID: capture.clipID,
                    reason: loss.serverReason
                )
                try await pendingCaptureStore.update(id: capture.id) {
                    $0.localState = .audioLostNeedsAcknowledgement
                    $0.nextAttemptAt = nil
                    $0.lastErrorCode = loss.serverReason
                }
            } catch let error as InterviewArcAPIError
                where error.code == "audio_already_available" {
                try await pendingCaptureStore.update(id: capture.id) {
                    $0.localState = .complete
                    $0.nextAttemptAt = nil
                    $0.lastErrorCode = nil
                }
            } catch {
                throw error
            }
        }
    }

    private func recordDeliveryFailure(
        _ error: InterviewArcAPIError,
        capture: PendingVoiceCapture,
        now: Date,
        manualAttempt: Bool
    ) async throws {
        let decision = VoiceDeliveryFailurePolicy().decision(
            error: error,
            capture: capture,
            now: now
        )
        try await pendingCaptureStore.update(id: capture.id) {
            switch decision {
            case .quarantine(let code, let statusCode, let message):
                $0.localState = .quarantinedConflict
                $0.nextAttemptAt = nil
                $0.lastErrorCode = code
                $0.lastErrorStatusCode = statusCode
                $0.lastErrorMessage = message
                $0.lastErrorRetryable = false
            case .needsAttention(let code, let statusCode, let message):
                $0.localState = .needsAttention
                $0.nextAttemptAt = nil
                $0.lastErrorCode = code
                $0.lastErrorStatusCode = statusCode
                $0.lastErrorMessage = message
                $0.lastErrorRetryable = true
            case .retry(
                let attempt,
                let retryStartedAt,
                let nextAttemptAt,
                let code,
                let statusCode,
                let message
            ):
                $0.localState = manualAttempt ? .needsAttention : .acceptedDelivering
                $0.retryAttempt = attempt
                $0.retryStartedAt = retryStartedAt
                $0.nextAttemptAt = manualAttempt ? nil : nextAttemptAt
                $0.lastErrorCode = code
                $0.lastErrorStatusCode = statusCode
                $0.lastErrorMessage = message
                $0.lastErrorRetryable = true
            }
        }
    }

    private static func clearDeliveryFailure(_ capture: inout PendingVoiceCapture) {
        capture.retryAttempt = 0
        capture.retryStartedAt = nil
        capture.nextAttemptAt = nil
        capture.lastErrorCode = nil
        capture.lastErrorStatusCode = nil
        capture.lastErrorMessage = nil
        capture.lastErrorRetryable = nil
    }

    private static func localAudioSourceLoss(
        _ url: URL
    ) -> LocalAudioSourceLoss? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }
        guard FileManager.default.isReadableFile(atPath: url.path),
              let attributes = try? FileManager.default.attributesOfItem(
                  atPath: url.path
              ),
              let type = attributes[.type] as? FileAttributeType,
              type == .typeRegular,
              let size = attributes[.size] as? NSNumber else {
            return .unreadable
        }
        return size.int64Value > 0 ? nil : .unreadable
    }

    private func enqueue(
        kind: VoiceRetryItem.Kind,
        activity: FocusedVoiceActivity,
        turnID: String,
        transcript: String,
        recordingURL: URL,
        durationSeconds: Double,
        transcription: TranscriptionResult,
        occurredAt: Date? = nil,
        clipID: String? = nil,
        analysisID: String? = nil,
        error: Error
    ) async throws {
        try await retryQueue.enqueue(VoiceRetryItem(
            id: "\(kind.rawValue)-\(UUID().uuidString.lowercased())",
            kind: kind,
            createdAt: Date(),
            occurredAt: occurredAt,
            activity: activity,
            specialist: nil,
            turnID: turnID,
            transcript: transcript,
            audioURL: recordingURL,
            durationSeconds: durationSeconds,
            transcription: transcription,
            clipID: clipID,
            analysisID: analysisID,
            lastError: error.localizedDescription
        ))
    }

    private func enqueue(
        kind: VoiceRetryItem.Kind,
        item: VoiceRetryItem,
        clipID: String? = nil,
        analysisID: String? = nil,
        error: Error
    ) async throws {
        try await enqueue(
            kind: kind,
            activity: item.activity,
            turnID: item.turnID,
            transcript: item.transcript,
            recordingURL: item.audioURL,
            durationSeconds: item.durationSeconds,
            transcription: item.transcription,
            occurredAt: item.occurredAt,
            clipID: clipID ?? item.clipID,
            analysisID: analysisID ?? item.analysisID,
            error: error
        )
    }

    private func queueAndRunDeliveryCoach(item: VoiceRetryItem, clipID: String, analysisID: String) async throws {
        _ = try await api.queueDelivery(
            analysisID: analysisID,
            activity: item.activity,
            clipID: clipID,
            turnID: item.turnID
        )
        try await codex.runDeliveryCoach(
            analysisID: analysisID,
            activity: item.activity,
            clipID: clipID,
            turnID: item.turnID,
            transcript: item.transcript,
            transcription: item.transcription,
            audioURL: item.audioURL,
            workspaceURL: workspaceURL,
            interviewArcToken: interviewArcToken
        )
    }
}
