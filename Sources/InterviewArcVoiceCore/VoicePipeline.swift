import Foundation

public enum VoiceDeliveryComponent: String, CaseIterable, Sendable {
    case transcript
    case specialist
    case audio
    case coach
}

public enum VoiceDeliveryComponentState: Equatable, Sendable {
    case working
    case complete
    case queued
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
    public let specialistSent: Bool
    public let audioUploaded: Bool
    public let deliveryCoachQueued: Bool
    public let transcriptionChunkCount: Int

    public var hasQueuedRetry: Bool {
        !capturePersisted || !specialistSent || !audioUploaded || !deliveryCoachQueued
    }
}

public actor VoicePipeline {
    private let api: InterviewArcAPIClient
    private let transcriber: any SpeechTranscribing
    private let codex: CodexBridge
    private let vocabularyResolver: VocabularyResolver
    private let retryQueue: VoiceRetryQueue
    private let temporaryDirectory: URL
    private let workspaceURL: URL
    private let interviewArcToken: String

    public init(
        api: InterviewArcAPIClient,
        transcriber: any SpeechTranscribing,
        codex: CodexBridge,
        vocabularyResolver: VocabularyResolver,
        retryQueue: VoiceRetryQueue,
        temporaryDirectory: URL,
        workspaceURL: URL,
        interviewArcToken: String
    ) {
        self.api = api
        self.transcriber = transcriber
        self.codex = codex
        self.vocabularyResolver = vocabularyResolver
        self.retryQueue = retryQueue
        self.temporaryDirectory = temporaryDirectory
        self.workspaceURL = workspaceURL
        self.interviewArcToken = interviewArcToken
    }

    public func process(
        recordingURL: URL,
        durationSeconds: Double,
        activity: FocusedVoiceActivity,
        specialist: SpecialistRoute,
        progress: @escaping @Sendable (VoicePipelineUpdate) async -> Void = { _ in }
    ) async throws -> VoicePipelineResult {
        await progress(.init(component: .transcript, state: .working))
        let vocabulary = vocabularyResolver.resolve(activity.vocabularyContext)
        let transcription = try await transcriber.transcribe(
            fileURL: recordingURL,
            prompt: vocabulary.prompt,
            temporaryDirectory: temporaryDirectory
        )
        let turnID = "voice-\(UUID().uuidString.lowercased())"
        let requestedClipID = "clip-\(UUID().uuidString.lowercased())"
        let occurredAt = Date()
        do {
            _ = try await api.persistCapture(
                activity: activity,
                turnID: turnID,
                transcript: transcription.text,
                occurredAt: occurredAt
            )
            await progress(.init(component: .transcript, state: .complete))
        } catch {
            try await enqueue(
                kind: .capturePersistence,
                activity: activity,
                specialist: specialist,
                turnID: turnID,
                transcript: transcription.text,
                recordingURL: recordingURL,
                durationSeconds: durationSeconds,
                transcription: transcription,
                occurredAt: occurredAt,
                clipID: requestedClipID,
                error: error
            )
            await progress(.init(component: .transcript, state: .queued))
            return VoicePipelineResult(
                turnID: turnID,
                transcript: transcription.text,
                clipID: nil,
                capturePersisted: false,
                specialistSent: false,
                audioUploaded: false,
                deliveryCoachQueued: false,
                transcriptionChunkCount: transcription.chunkCount
            )
        }

        await progress(.init(component: .specialist, state: .working))
        let specialistTask = Task {
            try await codex.sendToSpecialist(
                route: specialist,
                activity: activity,
                turnID: turnID,
                transcript: transcription.text,
                audioURL: recordingURL,
                workspaceURL: workspaceURL,
                interviewArcToken: interviewArcToken
            )
        }
        await progress(.init(component: .audio, state: .working))
        let audioUploadTask = Task {
            try await api.uploadAudio(
                fileURL: recordingURL,
                clipID: requestedClipID,
                activityID: activity.activityId,
                turnID: turnID,
                durationSeconds: durationSeconds
            )
        }

        var clipID: String?
        var audioUploaded = true
        switch await audioUploadTask.result {
        case .success(let upload):
            clipID = upload.clipId
            await progress(.init(component: .audio, state: .complete))
        case .failure(let error):
            audioUploaded = false
            try await enqueue(
                kind: .audioUpload,
                activity: activity,
                specialist: specialist,
                turnID: turnID,
                transcript: transcription.text,
                recordingURL: recordingURL,
                durationSeconds: durationSeconds,
                transcription: transcription,
                clipID: requestedClipID,
                error: error
            )
            await progress(.init(component: .audio, state: .queued))
        }

        var deliveryCoachQueued = false
        if let clipID {
            await progress(.init(component: .coach, state: .working))
            let analysisID = "delivery-\(UUID().uuidString.lowercased())"
            do {
                _ = try await api.queueDelivery(
                    analysisID: analysisID,
                    activity: activity,
                    clipID: clipID,
                    turnID: turnID
                )
                deliveryCoachQueued = true
                await progress(.init(component: .coach, state: .complete))
                Task {
                    do {
                        try await self.codex.runDeliveryCoach(
                            analysisID: analysisID,
                            activity: activity,
                            clipID: clipID,
                            turnID: turnID,
                            transcript: transcription.text,
                            transcription: transcription,
                            audioURL: recordingURL,
                            workspaceURL: self.workspaceURL,
                            interviewArcToken: self.interviewArcToken
                        )
                    } catch {
                        try? await self.enqueue(
                            kind: .deliveryCoach,
                            activity: activity,
                            specialist: specialist,
                            turnID: turnID,
                            transcript: transcription.text,
                            recordingURL: recordingURL,
                            durationSeconds: durationSeconds,
                            transcription: transcription,
                            clipID: clipID,
                            analysisID: analysisID,
                            error: error
                        )
                    }
                }
            } catch {
                try await enqueue(
                    kind: .deliveryCoach,
                    activity: activity,
                    specialist: specialist,
                    turnID: turnID,
                    transcript: transcription.text,
                    recordingURL: recordingURL,
                    durationSeconds: durationSeconds,
                    transcription: transcription,
                    clipID: clipID,
                    analysisID: analysisID,
                    error: error
                )
                await progress(.init(component: .coach, state: .queued))
            }
        } else {
            await progress(.init(component: .coach, state: .queued))
        }

        var specialistSent = true
        switch await specialistTask.result {
        case .success:
            await progress(.init(component: .specialist, state: .complete))
        case .failure(let error):
            specialistSent = false
            try await enqueue(
                kind: .specialistDelivery,
                activity: activity,
                specialist: specialist,
                turnID: turnID,
                transcript: transcription.text,
                recordingURL: recordingURL,
                durationSeconds: durationSeconds,
                transcription: transcription,
                error: error
            )
            await progress(.init(component: .specialist, state: .queued))
        }

        return VoicePipelineResult(
            turnID: turnID,
            transcript: transcription.text,
            clipID: clipID,
            capturePersisted: true,
            specialistSent: specialistSent,
            audioUploaded: audioUploaded,
            deliveryCoachQueued: deliveryCoachQueued,
            transcriptionChunkCount: transcription.chunkCount
        )
    }

    public func retryPending() async -> Int {
        guard let items = try? await retryQueue.items() else { return 0 }
        var completed = 0
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
                        try await codex.sendToSpecialist(
                            route: item.specialist,
                            activity: item.activity,
                            turnID: item.turnID,
                            transcript: item.transcript,
                            audioURL: item.audioURL,
                            workspaceURL: workspaceURL,
                            interviewArcToken: interviewArcToken
                        )
                    } catch {
                        try await enqueue(
                            kind: .specialistDelivery,
                            item: item,
                            error: error
                        )
                    }
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
                    try await codex.sendToSpecialist(
                        route: item.specialist,
                        activity: item.activity,
                        turnID: item.turnID,
                        transcript: item.transcript,
                        audioURL: item.audioURL,
                        workspaceURL: workspaceURL,
                        interviewArcToken: interviewArcToken
                    )
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

    private func enqueue(
        kind: VoiceRetryItem.Kind,
        activity: FocusedVoiceActivity,
        specialist: SpecialistRoute,
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
            specialist: specialist,
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
            specialist: item.specialist,
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
