import CryptoKit
import Foundation

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
    public let turnID: String
    public let transcript: String
    public let clipID: String?
    public let capturePersisted: Bool
    public let audioUploaded: Bool
    public let deliveryCoachQueued: Bool
    public let transcriptionChunkCount: Int

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
        self.temporaryDirectory = temporaryDirectory
        self.workspaceURL = workspaceURL
        self.interviewArcToken = interviewArcToken
    }

    public func process(
        recordingURL: URL,
        durationSeconds: Double,
        activity: FocusedVoiceActivity,
        occurredAt: Date = Date(),
        transcriptReady: @escaping @Sendable (VoiceCaptureEnvelope) async -> Void = { _ in },
        progress: @escaping @Sendable (VoicePipelineUpdate) async -> Void = { _ in }
    ) async throws -> VoicePipelineResult {
        await progress(.init(component: .transcript, state: .working))
        let vocabulary = vocabularyResolver.resolve(activity.vocabularyContext)
        let reliable = try await reliableTranscriber.transcribe(
            fileURL: recordingURL,
            prompt: vocabulary.prompt,
            temporaryDirectory: temporaryDirectory,
            audioDurationSeconds: durationSeconds
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
            createdAt: Date()
        )
        try await pendingCaptureStore.save(pending)
        do {
            _ = try await api.registerIntent(pending)
            await progress(.init(component: .transcript, state: .complete))
        } catch {
            // The local pending record is the durable source until metadata can
            // be registered. Reconciliation retries without uploading content.
            await progress(.init(component: .transcript, state: .queued))
        }
        await transcriptReady(VoiceCaptureEnvelope(
            captureID: captureID,
            activityID: activity.activityId,
            turnID: turnID,
            transcript: transcription.text
        ))
        await progress(.init(component: .audio, state: .queued))
        await progress(.init(component: .coach, state: .queued))
        return VoicePipelineResult(
            turnID: turnID,
            transcript: transcription.text,
            clipID: nil,
            capturePersisted: false,
            audioUploaded: false,
            deliveryCoachQueued: false,
            transcriptionChunkCount: transcription.chunkCount
        )
    }

    public func retryPending() async -> Int {
        var completed = await reconcilePendingCaptures()
        guard let items = try? await retryQueue.items() else { return completed }
        for item in items {
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
        guard let captures = try? await pendingCaptureStore.items(), !captures.isEmpty else { return [] }
        guard let intents = try? await api.intents(captureIDs: captures.map(\.id)) else { return [] }
        let visible = Set(intents.filter { $0.status == "uncertain" }.map(\.captureId))
        return captures.filter { visible.contains($0.id) }
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

    private func reconcilePendingCaptures() async -> Int {
        guard let captures = try? await pendingCaptureStore.items(),
              !captures.isEmpty else { return 0 }
        for capture in captures {
            try? await api.registerIntent(capture)
        }
        guard let intents = try? await api.intents(captureIDs: captures.map(\.id)) else {
            return 0
        }
        let byID = Dictionary(uniqueKeysWithValues: intents.map { ($0.captureId, $0) })
        var completed = 0
        for capture in captures {
            guard let intent = byID[capture.id] else { continue }
            do {
                switch intent.status {
                case "activity_related":
                    _ = try await api.persistCapture(
                        activity: capture.activity,
                        turnID: capture.turnID,
                        transcript: capture.transcript,
                        occurredAt: capture.occurredAt,
                        captureID: capture.id,
                        checksum: capture.checksum
                    )
                    try await finishAcceptedCapture(capture)
                    try await pendingCaptureStore.remove(id: capture.id, deleteAudio: true)
                    completed += 1
                case "accepted":
                    try await finishAcceptedCapture(capture)
                    try await pendingCaptureStore.remove(id: capture.id, deleteAudio: true)
                    completed += 1
                case "unrelated":
                    // Keep local recovery material for 24 hours, but never send
                    // transcript or audio. The next reconciliation after the
                    // grace period removes both local and server tombstones.
                    if Date().timeIntervalSince(capture.createdAt) >= 86_400 {
                        try await api.deleteCapture(captureID: capture.id)
                        try await pendingCaptureStore.remove(id: capture.id, deleteAudio: true)
                        completed += 1
                    }
                case "deleted":
                    try await pendingCaptureStore.remove(id: capture.id, deleteAudio: true)
                    completed += 1
                default:
                    break
                }
            } catch {
                // Durable local data remains for the next idempotent pass.
            }
        }
        return completed
    }

    private func finishAcceptedCapture(_ capture: PendingVoiceCapture) async throws {
        let upload = try await api.uploadAudio(
            fileURL: capture.audioURL,
            clipID: capture.clipID,
            activityID: capture.activity.activityId,
            turnID: capture.turnID,
            durationSeconds: capture.durationSeconds,
            captureID: capture.id
        )
        let analysisID = "delivery-\(capture.id)"
        _ = try await api.queueDelivery(
            analysisID: analysisID,
            activity: capture.activity,
            clipID: upload.clipId,
            turnID: capture.turnID
        )
        try await codex.runDeliveryCoach(
            analysisID: analysisID,
            activity: capture.activity,
            clipID: upload.clipId,
            turnID: capture.turnID,
            transcript: capture.transcript,
            transcription: capture.transcription,
            audioURL: capture.audioURL,
            workspaceURL: workspaceURL,
            interviewArcToken: interviewArcToken
        )
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
