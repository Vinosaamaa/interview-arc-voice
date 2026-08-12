import Foundation

public actor InterviewArcAPIClient {
    public static let protocolVersion = 2

    private let baseURL: URL
    private let token: String
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public func context() async throws -> VoiceContextResponse {
        let response: VoiceContextResponse = try await send(path: "voice/context", method: "GET", body: Optional<Data>.none)
        guard response.protocolVersion == Self.protocolVersion else {
            throw VoiceBridgeError.protocolMismatch(response.protocolVersion)
        }
        return response
    }

    public func liveUpdates(
        afterRevision initialRevision: Int = 0
    ) -> AsyncThrowingStream<VoiceLiveSignal, Error> {
        var components = URLComponents(
            url: baseURL.appending(path: "events"),
            resolvingAgainstBaseURL: false
        )!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("InterviewArcVoice/0.3", forHTTPHeaderField: "User-Agent")
        let socket = session.webSocketTask(with: request)
        let liveDecoder = VoiceLiveFrameDecoder()
        return AsyncThrowingStream { continuation in
            let heartbeat = Task {
                do {
                    while !Task.isCancelled {
                        try await Task.sleep(
                            for: .seconds(VoiceLiveConnectionPolicy.heartbeatIntervalSeconds)
                        )
                        guard !Task.isCancelled else { return }
                        try await withCheckedThrowingContinuation {
                            (continuation: CheckedContinuation<Void, Error>) in
                            socket.sendPing { error in
                                if let error {
                                    continuation.resume(throwing: error)
                                } else {
                                    continuation.resume()
                                }
                            }
                        }
                    }
                } catch {
                    socket.cancel(with: .goingAway, reason: nil)
                    continuation.finish(throwing: error)
                }
            }
            let reader = Task {
                var latestRevision = initialRevision
                socket.resume()
                defer { heartbeat.cancel() }
                do {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        let data: Data
                        switch message {
                        case .data(let value): data = value
                        case .string(let value): data = Data(value.utf8)
                        @unknown default: continue
                        }
                        guard let signal = try? liveDecoder.decode(
                            data,
                            latestRevision: &latestRevision
                        ) else { continue }
                        continuation.yield(signal)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                heartbeat.cancel()
                reader.cancel()
                socket.cancel(with: .normalClosure, reason: nil)
            }
        }
    }

    public func mutateTimer(
        subjectID: String,
        kind: String,
        action: String
    ) async throws -> VoiceTimerMutationResponse {
        struct Mutation: Encodable {
            let type = "timer"
            let subjectId: String
            let kind: String
            let action: String
        }
        struct Body: Encodable {
            let protocolVersion: Int
            let mutation: Mutation
        }
        let body = Body(
            protocolVersion: Self.protocolVersion,
            mutation: Mutation(subjectId: subjectID, kind: kind, action: action)
        )
        return try await send(
            path: "voice/timers",
            method: "POST",
            body: encoder.encode(body)
        )
    }

    public func planning(
        specialty: VoicePlanningSpecialty,
        query: VoicePlanningQuery = VoicePlanningQuery(),
        page: Int = 1,
        pageSize: Int = 30
    ) async throws -> VoicePlanningResponse {
        var components = URLComponents(
            url: baseURL.appending(path: "voice/planning"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "specialty", value: specialty.rawValue),
            URLQueryItem(name: "search", value: query.search),
            URLQueryItem(name: "starred", value: query.starredOnly ? "true" : "false"),
            URLQueryItem(
                name: "attention",
                value: query.attention.map(\.rawValue).sorted().joined(separator: ",")
            ),
            URLQueryItem(
                name: "difficulty",
                value: query.difficulty.map(\.rawValue).sorted().joined(separator: ",")
            ),
            URLQueryItem(name: "sort", value: query.sort.rawValue),
            URLQueryItem(name: "direction", value: query.direction.rawValue),
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "pageSize", value: String(min(100, max(1, pageSize)))),
        ]
        return try await send(
            url: components.url!,
            method: "GET",
            body: Optional<Data>.none
        )
    }

    public func mutatePlanning(
        _ mutation: VoicePlanningMutationRequest
    ) async throws -> VoicePlanningMutationResponse {
        try await send(
            path: "voice/planning/mutations",
            method: "POST",
            body: encoder.encode(mutation)
        )
    }

    public func finishActivity(
        activityID: String,
        outcome: VoicePracticeOutcome,
        starred: Bool
    ) async throws -> VoiceTimerMutationResponse {
        struct Mutation: Encodable {
            let type = "finish-activity"
            let activityId: String
            let outcome: VoicePracticeOutcome
            let starred: Bool
        }
        struct Body: Encodable {
            let protocolVersion: Int
            let mutation: Mutation
        }
        let body = Body(
            protocolVersion: Self.protocolVersion,
            mutation: Mutation(
                activityId: activityID,
                outcome: outcome,
                starred: starred
            )
        )
        return try await send(
            path: "voice/timers",
            method: "POST",
            body: encoder.encode(body)
        )
    }

    public func persistCapture(
        activity: FocusedVoiceActivity,
        turnID: String,
        transcript: String,
        occurredAt: Date,
        captureID: String? = nil,
        checksum: String? = nil
    ) async throws -> VoiceCaptureResponse {
        if let captureID, let checksum {
            let identity = VoiceTranscriptIdentity(transcript)
            guard identity.validates(transcript: transcript, checksum: checksum) else {
                throw InterviewArcAPIError(
                    statusCode: 0,
                    message: "Local transcript identity is inconsistent for \(captureID).",
                    code: "local_transcript_checksum_mismatch",
                    retryable: false
                )
            }
        }
        struct Body: Encodable {
            let protocolVersion: Int
            let activityId: String
            let specialty: String
            let turnId: String
            let transcript: String
            let occurredAt: Int64
            let captureId: String?
            let checksum: String?
        }
        let body = Body(
            protocolVersion: Self.protocolVersion,
            activityId: activity.activityId,
            specialty: activity.interviewArcSpecialty,
            turnId: turnID,
            transcript: transcript,
            occurredAt: Int64(occurredAt.timeIntervalSince1970 * 1_000),
            captureId: captureID,
            checksum: checksum
        )
        return try await send(path: "voice/captures", method: "POST", body: encoder.encode(body))
    }

    public func persistLearningTranscript(
        _ request: LearningVoiceTranscriptRequest
    ) async throws -> LearningVoiceTranscriptResponse {
        let identity = VoiceTranscriptIdentity(request.transcript)
        guard request.protocolVersion == Self.protocolVersion,
              request.expectedTranscriptRevision >= 0,
              request.sequence >= 0,
              request.occurredAt > 0,
              identity.validates(
                  transcript: request.transcript,
                  checksum: request.checksum
              ) else {
            throw InterviewArcAPIError(
                statusCode: 0,
                message: "The local Learning transcript identity is inconsistent.",
                code: "local_learning_transcript_identity_mismatch",
                retryable: false
            )
        }
        let response: LearningVoiceTranscriptResponse = try await send(
            path: "voice/learning-transcripts",
            method: "POST",
            body: encoder.encode(request)
        )
        guard response.protocolVersion == Self.protocolVersion,
              response.evidencePolicy == .transcriptOnly,
              response.transcriptRevision
                == request.expectedTranscriptRevision + 1,
              response.turnIds == [request.turnId] else {
            throw InterviewArcAPIError(
                statusCode: 0,
                message: "The Learning transcript acknowledgement did not match the stable local request.",
                code: "learning_transcript_receipt_mismatch",
                retryable: false
            )
        }
        return response
    }

    public func registerIntent(_ capture: PendingVoiceCapture) async throws -> VoiceCaptureIntentResponse {
        let identity = VoiceTranscriptIdentity(capture.transcript)
        guard identity.validates(
            transcript: capture.transcript,
            checksum: capture.checksum
        ) else {
            throw InterviewArcAPIError(
                statusCode: 0,
                message: "Local transcript identity is inconsistent for \(capture.id).",
                code: "local_transcript_checksum_mismatch",
                retryable: false
            )
        }
        struct Body: Encodable {
            let protocolVersion: Int
            let captureId: String
            let activityId: String
            let turnId: String
            let clipId: String
            let specialty: String
            let checksum: String
            let occurredAt: Int64
        }
        let body = Body(
            protocolVersion: Self.protocolVersion,
            captureId: capture.id,
            activityId: capture.activity.activityId,
            turnId: capture.turnID,
            clipId: capture.clipID,
            specialty: capture.activity.interviewArcSpecialty,
            checksum: capture.checksum,
            occurredAt: Int64(capture.occurredAt.timeIntervalSince1970 * 1_000)
        )
        return try await send(path: "voice/intents", method: "POST", body: encoder.encode(body))
    }

    public func intents(captureIDs: [String]) async throws -> [VoiceCaptureIntent] {
        guard !captureIDs.isEmpty else { return [] }
        var components = URLComponents(
            url: baseURL.appending(path: "voice/intents"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = captureIDs.map { URLQueryItem(name: "captureId", value: $0) }
        let response: VoiceCaptureIntentListResponse = try await send(
            url: components.url!,
            method: "GET",
            body: Optional<Data>.none
        )
        return response.intents
    }

    public func retainedIntents() async throws -> [VoiceCaptureIntent] {
        var cursor: String?
        var results: [VoiceCaptureIntent] = []
        repeat {
            var components = URLComponents(
                url: baseURL.appending(path: "voice/intents"),
                resolvingAgainstBaseURL: false
            )!
            var queryItems = [
                URLQueryItem(name: "status", value: "retained"),
                URLQueryItem(name: "limit", value: "100"),
            ]
            if let cursor {
                queryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            components.queryItems = queryItems
            let response: VoiceCaptureIntentListResponse = try await send(
                url: components.url!,
                method: "GET",
                body: Optional<Data>.none
            )
            results.append(contentsOf: response.intents)
            cursor = response.nextCursor
        } while cursor != nil
        return results
    }

    public func deliveryBlockers(activityID: String) async throws -> VoiceDeliveryBlockersResponse {
        var components = URLComponents(
            url: baseURL.appending(path: "voice/delivery-blockers"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "activityId", value: activityID)]
        let response: VoiceDeliveryBlockersResponse = try await send(
            url: components.url!,
            method: "GET",
            body: Optional<Data>.none
        )
        guard response.protocolVersion == Self.protocolVersion else {
            throw VoiceBridgeError.protocolMismatch(response.protocolVersion)
        }
        return response
    }

    public func legacyVoiceOrphans() async throws -> [LegacyVoiceCapture] {
        let response: VoiceCaptureIntentListResponse = try await send(
            path: "voice/intents",
            method: "GET",
            body: Optional<Data>.none
        )
        return response.legacyOrphans
    }

    public func decideIntent(
        captureID: String,
        decision: String,
        reason: String
    ) async throws -> VoiceCaptureIntentResponse {
        struct Body: Encodable {
            let protocolVersion: Int
            let decision: String
            let reason: String
        }
        return try await send(
            path: "voice/intents/\(captureID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? captureID)/decision",
            method: "POST",
            body: encoder.encode(Body(
                protocolVersion: Self.protocolVersion,
                decision: decision,
                reason: reason
            ))
        )
    }

    public func expireIntent(_ capture: PendingVoiceCapture) async throws -> VoiceCaptureIntentResponse {
        struct Body: Encodable {
            let protocolVersion: Int
            let activityId: String
            let turnId: String
        }
        return try await send(
            path: "voice/intents/\(capture.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? capture.id)/expire",
            method: "POST",
            body: encoder.encode(Body(
                protocolVersion: Self.protocolVersion,
                activityId: capture.activity.activityId,
                turnId: capture.turnID
            ))
        )
    }

    public func reportAudioLoss(
        captureID: String,
        clipID: String,
        reason: String
    ) async throws -> VoiceAudioLossResponse {
        struct Body: Encodable {
            let clipId: String
            let reason: String
        }
        return try await send(
            path: "voice/captures/\(captureID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? captureID)/audio-loss",
            method: "POST",
            body: encoder.encode(Body(clipId: clipID, reason: reason))
        )
    }

    public func acknowledgeAudioLoss(
        captureID: String,
        clipID: String
    ) async throws -> VoiceAudioLossResponse {
        struct Body: Encodable { let clipId: String }
        return try await send(
            path: "voice/captures/\(captureID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? captureID)/audio-loss/acknowledge",
            method: "POST",
            body: encoder.encode(Body(clipId: clipID))
        )
    }

    public func deleteCapture(captureID: String) async throws {
        struct Response: Decodable { let status: String }
        let _: Response = try await send(
            path: "voice/captures/\(captureID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? captureID)",
            method: "DELETE",
            body: Optional<Data>.none
        )
    }

    public func deleteLegacyCapture(clipID: String) async throws {
        struct Response: Decodable { let status: String }
        let _: Response = try await send(
            path: "voice/legacy-orphans/\(clipID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? clipID)",
            method: "DELETE",
            body: Optional<Data>.none
        )
    }

    public func uploadAudio(
        fileURL: URL,
        clipID: String,
        activityID: String,
        turnID: String,
        durationSeconds: Double,
        captureID: String? = nil
    ) async throws -> AudioUploadResponse {
        let boundary = "InterviewArcVoice-\(UUID().uuidString)"
        var request = authorizedRequest(path: "audio/upload", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        var body = Data()
        body.appendFormField("clipId", clipID, boundary: boundary)
        if let captureID {
            body.appendFormField("captureId", captureID, boundary: boundary)
        }
        body.appendFormField("activityId", activityID, boundary: boundary)
        body.appendFormField("transcriptTurnId", turnID, boundary: boundary)
        body.appendFormField("label", "Recorded answer", boundary: boundary)
        body.appendFormField("durationSeconds", String(Int(durationSeconds.rounded())), boundary: boundary)
        body.appendFileField(
            "file",
            filename: fileURL.lastPathComponent,
            mimeType: "audio/mp4",
            data: fileData,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        let (data, response) = try await session.upload(for: request, from: body)
        try validate(response: response, data: data)
        return try decoder.decode(AudioUploadResponse.self, from: data)
    }

    public func queueDelivery(
        analysisID: String,
        activity: FocusedVoiceActivity,
        clipID: String,
        turnID: String
    ) async throws -> DeliveryQueueResponse {
        struct Body: Encodable {
            let protocolVersion: Int
            let id: String
            let activityId: String
            let audioClipId: String
            let transcriptTurnId: String
            let specialty: String
            let status: String
        }
        let body = Body(
            protocolVersion: Self.protocolVersion,
            id: analysisID,
            activityId: activity.activityId,
            audioClipId: clipID,
            transcriptTurnId: turnID,
            specialty: activity.interviewArcSpecialty,
            status: "queued"
        )
        return try await send(path: "voice/delivery", method: "POST", body: encoder.encode(body))
    }

    private func send<Response: Decodable>(path: String, method: String, body: Data?) async throws -> Response {
        try await send(url: baseURL.appending(path: path), method: method, body: body)
    }

    private func send<Response: Decodable>(url: URL, method: String, body: Data?) async throws -> Response {
        var request = authorizedRequest(url: url, method: method)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func authorizedRequest(path: String, method: String) -> URLRequest {
        authorizedRequest(url: baseURL.appending(path: path), method: method)
    }

    private func authorizedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("InterviewArcVoice/0.1", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 120
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        struct APIError: Decodable {
            let error: String
            let code: String?
            let retryable: Bool?
        }
        guard let http = response as? HTTPURLResponse else {
            throw VoiceBridgeError.invalidResponse(0, "Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = try? decoder.decode(APIError.self, from: data)
            let detail = payload?.error ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw InterviewArcAPIError(
                statusCode: http.statusCode,
                message: detail,
                code: payload?.code,
                retryable: payload?.retryable ?? (http.statusCode == 408 || http.statusCode == 429 || http.statusCode >= 500)
            )
        }
    }
}

private extension Data {
    mutating func appendFormField(_ name: String, _ value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendFileField(_ name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
