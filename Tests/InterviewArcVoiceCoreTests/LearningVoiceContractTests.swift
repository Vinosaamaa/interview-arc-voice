import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func learningTranscriptUsesTheNarrowChecksumBoundServerContract() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LearningVoiceURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let request = LearningVoiceTranscriptRequest(
        operationId: "learning-voice-operation-1",
        sessionId: "learning-session-1",
        expectedTranscriptRevision: 4,
        turnId: "learning-voice-turn-7",
        sequence: 7,
        transcript: "Voice preserves this exact Learning turn without cloud audio.",
        checksum: VoiceTranscriptIdentity(
            "Voice preserves this exact Learning turn without cloud audio."
        ).checksum,
        occurredAt: 1_786_507_200_000
    )
    let observedRequest = LockedBox<URLRequest?>(nil)
    let observedBody = LockedBox<Data?>(nil)
    LearningVoiceURLProtocol.handler = { received in
        observedRequest.set(received)
        observedBody.set(try requestBodyData(received))
        let response = HTTPURLResponse(
            url: try #require(received.url),
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let body = Data(#"""
        {
          "protocolVersion": 2,
          "transcriptRevision": 5,
          "turnIds": ["learning-voice-turn-7"],
          "evidencePolicy": "transcript_only",
          "duplicate": false
        }
        """#.utf8)
        return (response, body)
    }
    defer { LearningVoiceURLProtocol.handler = nil }
    let client = InterviewArcAPIClient(
        baseURL: URL(string: "https://voice.example.test")!,
        token: "test-token",
        session: session
    )

    let receipt = try await client.persistLearningTranscript(request)

    #expect(receipt.transcriptRevision == 5)
    #expect(receipt.turnIds == [request.turnId])
    #expect(receipt.evidencePolicy == .transcriptOnly)
    #expect(receipt.duplicate == false)
    let sent = try #require(observedRequest.value)
    #expect(sent.url?.path == "/voice/learning-transcripts")
    #expect(sent.httpMethod == "POST")
    let sentBody = try #require(observedBody.value)
    let decodedObject = try JSONSerialization.jsonObject(with: sentBody)
    let object = try #require(decodedObject as? [String: Any])
    #expect(object["sessionId"] as? String == request.sessionId)
    #expect(object["operationId"] as? String == request.operationId)
    #expect(object["turnId"] as? String == request.turnId)
    #expect(object["checksum"] as? String == request.checksum)
    #expect(object["audio"] == nil)
    #expect(object["clipId"] == nil)
    #expect(object["captureId"] == nil)
}

@Test func learningRecoveryStoreReplaysExactIdentityAndRejectsChangedRetry() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "learning-voice-store-\(UUID().uuidString)"
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let audio = root.appending(path: "protected.m4a")
    try Data("transient audio".utf8).write(to: audio)
    let store = LearningVoiceCaptureStore(directory: root.appending(path: "Pending"))
    let capture = pendingLearningCapture(audioURL: audio)

    try await store.saveNew(capture)
    try await store.saveNew(capture)

    #expect(try await store.item(id: capture.id) == capture)
    let changed = pendingLearningCapture(
        audioURL: audio,
        transcript: "Changed retry"
    )
    await #expect(throws: LearningVoiceCaptureStoreError.identityConflict) {
        try await store.saveNew(changed)
    }
    #expect(FileManager.default.fileExists(atPath: audio.path))
}

@Test func learningRecoveryStoreReadsLegacyISO8601Dates() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "learning-voice-legacy-store-\(UUID().uuidString)"
    )
    let pendingDirectory = root.appending(path: "Pending")
    try FileManager.default.createDirectory(
        at: pendingDirectory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let audio = root.appending(path: "protected.m4a")
    try Data("transient audio".utf8).write(to: audio)
    let capture = pendingLearningCapture(audioURL: audio)
    let legacyEncoder = JSONEncoder()
    legacyEncoder.dateEncodingStrategy = .iso8601
    try legacyEncoder.encode(capture).write(
        to: pendingDirectory.appending(path: "\(capture.id).json")
    )
    let store = LearningVoiceCaptureStore(directory: pendingDirectory)

    #expect(try await store.item(id: capture.id) == capture)
}

@Test func successfulLearningCaptureInsertsVerbatimCommitsTextAndDisposesAudio() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "learning-voice-pipeline-\(UUID().uuidString)"
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let audio = root.appending(path: "protected.m4a")
    try Data("transient audio".utf8).write(to: audio)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LearningVoicePipelineURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let learningStore = LearningVoiceCaptureStore(
        directory: root.appending(path: "LearningPending")
    )
    let observedPaths = LockedBox<[String]>([])
    LearningVoicePipelineURLProtocol.handler = { request in
        let path = try #require(request.url).path
        observedPaths.mutate { $0.append(path) }
        let body = try requestBodyData(request)
        let object = try #require(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let turnId = try #require(object["turnId"] as? String)
        let revision = try #require(object["expectedTranscriptRevision"] as? Int)
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let responseBody = try JSONSerialization.data(withJSONObject: [
            "protocolVersion": 2,
            "transcriptRevision": revision + 1,
            "turnIds": [turnId],
            "evidencePolicy": "transcript_only",
            "duplicate": false,
        ])
        return (response, responseBody)
    }
    defer { LearningVoicePipelineURLProtocol.handler = nil }
    let pipeline = VoicePipeline(
        api: InterviewArcAPIClient(
            baseURL: URL(string: "https://voice.example.test")!,
            token: "test-token",
            session: session
        ),
        transcriber: LearningStubTranscriber(),
        codex: CodexBridge(executableURL: URL(fileURLWithPath: "/usr/bin/false")),
        vocabularyResolver: VocabularyResolver(catalog: try .bundled()),
        retryQueue: VoiceRetryQueue(directory: root.appending(path: "Retry")),
        pendingCaptureStore: PendingVoiceCaptureStore(
            directory: root.appending(path: "InterviewPending")
        ),
        learningCaptureStore: learningStore,
        temporaryDirectory: root.appending(path: "Temporary"),
        workspaceURL: root,
        interviewArcToken: "test-token"
    )
    let focused = pendingLearningCapture(audioURL: audio).session
    let insertedText = LockedBox<String?>(nil)

    let result = try await pipeline.processLearning(
        recordingURL: audio,
        durationSeconds: 2,
        session: focused,
        occurredAt: Date(timeIntervalSince1970: 1_786_507_200),
        transcriptReady: { transcript in
            insertedText.set(transcript)
            return true
        }
    )

    #expect(insertedText.value == result.transcript)
    #expect(!result.transcript.contains("interview-arc-voice:v2"))
    #expect(observedPaths.value == ["/voice/learning-transcripts"])
    #expect(!FileManager.default.fileExists(atPath: audio.path))
    #expect(try await learningStore.items().isEmpty)
}

@Test func failedLearningAcknowledgementRetainsOneRecoverableOriginal() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "learning-voice-failure-\(UUID().uuidString)"
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let audio = root.appending(path: "protected.m4a")
    try Data("transient audio".utf8).write(to: audio)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [LearningVoiceFailureURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let learningStore = LearningVoiceCaptureStore(
        directory: root.appending(path: "LearningPending")
    )
    let requestBodies = LockedBox<[Data]>([])
    LearningVoiceFailureURLProtocol.handler = { request in
        let body = try requestBodyData(request)
        requestBodies.mutate { $0.append(body) }
        if requestBodies.value.count > 1 {
            let object = try #require(
                JSONSerialization.jsonObject(with: body) as? [String: Any]
            )
            let response = HTTPURLResponse(
                url: try #require(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, try JSONSerialization.data(withJSONObject: [
                "protocolVersion": 2,
                "transcriptRevision":
                    (try #require(object["expectedTranscriptRevision"] as? Int)) + 1,
                "turnIds": [try #require(object["turnId"] as? String)],
                "evidencePolicy": "transcript_only",
                "duplicate": true,
            ]))
        }
        let response = HTTPURLResponse(
            url: try #require(request.url),
            statusCode: 503,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, Data(#"""
        {
          "error": "The Learning Voice transcript could not be saved.",
          "code": "learning_voice_internal_error",
          "retryable": true
        }
        """#.utf8))
    }
    defer { LearningVoiceFailureURLProtocol.handler = nil }
    let pipeline = VoicePipeline(
        api: InterviewArcAPIClient(
            baseURL: URL(string: "https://voice.example.test")!,
            token: "test-token",
            session: session
        ),
        transcriber: LearningStubTranscriber(),
        codex: CodexBridge(executableURL: URL(fileURLWithPath: "/usr/bin/false")),
        vocabularyResolver: VocabularyResolver(catalog: try .bundled()),
        retryQueue: VoiceRetryQueue(directory: root.appending(path: "Retry")),
        pendingCaptureStore: PendingVoiceCaptureStore(
            directory: root.appending(path: "InterviewPending")
        ),
        learningCaptureStore: learningStore,
        temporaryDirectory: root.appending(path: "Temporary"),
        workspaceURL: root,
        interviewArcToken: "test-token"
    )

    await #expect(throws: InterviewArcAPIError.self) {
        try await pipeline.processLearning(
            recordingURL: audio,
            durationSeconds: 2,
            session: pendingLearningCapture(audioURL: audio).session,
            transcriptReady: { _ in true }
        )
    }

    let pending = try #require(try await learningStore.items().first)
    #expect(pending.stage == .acknowledgementPending)
    #expect(pending.lastErrorRetryable == true)
    #expect(FileManager.default.fileExists(atPath: audio.path))
    #expect(try await learningStore.items().count == 1)

    #expect(await pipeline.retryPendingLearningAcknowledgements() == 1)
    let bodies = requestBodies.value
    #expect(bodies.count == 2)
    let firstBody = try #require(bodies.first)
    let secondBody = try #require(bodies.dropFirst().first)
    let first = try #require(
        JSONSerialization.jsonObject(with: firstBody)
            as? NSDictionary
    )
    let second = try #require(
        JSONSerialization.jsonObject(with: secondBody)
            as? NSDictionary
    )
    #expect(first == second)
    #expect(!FileManager.default.fileExists(atPath: audio.path))
    #expect(try await learningStore.items().isEmpty)
}

private final class LearningVoiceURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class LearningVoicePipelineURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class LearningVoiceFailureURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler:
        (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            let handler = try #require(Self.handler)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private actor LearningStubTranscriber: SpeechTranscribing {
    func transcribe(
        fileURL: URL,
        prompt: String,
        temporaryDirectory: URL
    ) async throws -> TranscriptionResult {
        TranscriptionResult(
            text: "Voice preserves this exact Learning turn without cloud audio.",
            words: [],
            durationSeconds: 2,
            chunkCount: 1
        )
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.withLock { storage }
    }

    func set(_ value: Value) {
        lock.withLock { storage = value }
    }

    func mutate(_ mutation: (inout Value) throws -> Void) rethrows {
        try lock.withLock { try mutation(&storage) }
    }
}

private enum RequestBodyReadError: Error {
    case missingBody
    case streamReadFailed
}

private func requestBodyData(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        throw RequestBodyReadError.missingBody
    }

    stream.open()
    defer { stream.close() }
    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while true {
        let bytesRead = stream.read(&buffer, maxLength: buffer.count)
        if bytesRead < 0 {
            throw stream.streamError ?? RequestBodyReadError.streamReadFailed
        }
        if bytesRead == 0 {
            return body
        }
        body.append(contentsOf: buffer.prefix(bytesRead))
    }
}

private func pendingLearningCapture(
    audioURL: URL,
    transcript: String = "Voice preserves this exact Learning turn without cloud audio."
) -> PendingLearningVoiceCapture {
    return PendingLearningVoiceCapture(
        operationId: "learning-voice-operation-1",
        turnId: "learning-voice-turn-7",
        session: FocusedLearningVoiceSession(
            sessionId: "learning-session-1",
            scopeType: "course",
            courseId: "course-architecture",
            blueprintRevision: 3,
            courseTitle: "Interview Arc Architecture",
            moduleId: "module-runtime",
            moduleTitle: "Runtime",
            lessonId: "lesson-voice-boundary",
            lessonRevision: 2,
            lessonTitle: "Voice boundary",
            state: "running",
            transcriptRevision: 4,
            nextTranscriptSequence: 7,
            startedAt: 1_786_507_190_000,
            runningSince: 1_786_507_200_000,
            evidencePolicy: .transcriptOnly
        ),
        transcript: transcript,
        checksum: VoiceTranscriptIdentity(transcript).checksum,
        audioURL: audioURL,
        durationSeconds: 2,
        occurredAt: Date(timeIntervalSince1970: 1_786_507_200),
        transcription: TranscriptionResult(
            text: transcript,
            words: [],
            durationSeconds: 2,
            chunkCount: 1
        ),
        createdAt: Date(timeIntervalSince1970: 1_786_507_201)
    )
}
