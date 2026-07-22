import Foundation

public actor InterviewArcAPIClient {
    public static let protocolVersion = 1

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

    public func persistCapture(
        activity: FocusedVoiceActivity,
        turnID: String,
        transcript: String,
        occurredAt: Date
    ) async throws -> VoiceCaptureResponse {
        struct Body: Encodable {
            let protocolVersion: Int
            let activityId: String
            let specialty: String
            let turnId: String
            let transcript: String
            let occurredAt: Int64
        }
        let body = Body(
            protocolVersion: Self.protocolVersion,
            activityId: activity.activityId,
            specialty: activity.interviewArcSpecialty,
            turnId: turnID,
            transcript: transcript,
            occurredAt: Int64(occurredAt.timeIntervalSince1970 * 1_000)
        )
        return try await send(path: "voice/captures", method: "POST", body: encoder.encode(body))
    }

    public func uploadAudio(
        fileURL: URL,
        clipID: String,
        activityID: String,
        turnID: String,
        durationSeconds: Double
    ) async throws -> AudioUploadResponse {
        let boundary = "InterviewArcVoice-\(UUID().uuidString)"
        var request = authorizedRequest(path: "audio/upload", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        var body = Data()
        body.appendFormField("clipId", clipID, boundary: boundary)
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
        var request = authorizedRequest(path: path, method: method)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func authorizedRequest(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("InterviewArcVoice/0.1", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 120
        return request
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw VoiceBridgeError.invalidResponse(0, "Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw VoiceBridgeError.invalidResponse(http.statusCode, String(data: data, encoding: .utf8) ?? "Unknown error")
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
