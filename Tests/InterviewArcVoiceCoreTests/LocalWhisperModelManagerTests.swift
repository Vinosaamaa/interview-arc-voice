import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func localWhisperPromptPolicyNormalizesAndBoundsVocabularyTokens() {
    let encoded = LocalWhisperPromptPolicy.boundedTokens(
        for: "  Context: Course\nSchedule.   Vocabulary: LeetCode.  "
    ) { value in
        #expect(value == " Context: Course Schedule. Vocabulary: LeetCode.")
        return Array(0..<240)
    }

    #expect(encoded.count == LocalWhisperPromptPolicy.maximumTokenCount)
    #expect(encoded.first == 60)
    #expect(encoded.last == 239)
}

@Test func localWhisperPromptPolicyOmitsEmptyConditioning() {
    var encoderCalled = false
    let encoded = LocalWhisperPromptPolicy.boundedTokens(
        for: " \n\t "
    ) { _ in
        encoderCalled = true
        return [1]
    }

    #expect(encoded.isEmpty)
    #expect(!encoderCalled)
}

@Test func conditionedLocalWhisperChunksUseOneWorker() {
    #expect(
        LocalWhisperPromptPolicy.concurrentWorkerCount(forPromptTokens: [42])
            == 1
    )
    #expect(
        LocalWhisperPromptPolicy.concurrentWorkerCount(forPromptTokens: [])
            == nil
    )
}

@Test func localWhisperModelLifecycleSurvivesRelaunchAndDetectsCorruption() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "InterviewArcVoice-LocalWhisper-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let modelFolder = root.appending(
        path: "fixture-base-en",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: modelFolder,
        withIntermediateDirectories: true
    )
    let fixtureFile = modelFolder.appending(path: "AudioEncoder.mlmodelc")
    try Data("synthetic-model-fixture".utf8).write(to: fixtureFile)

    let first = try LocalWhisperModelManager(rootDirectory: root)
    let installed = try await first.registerExistingModel(at: modelFolder)
    #expect(installed.state == .available)
    #expect(installed.sizeBytes == 23)

    let relaunched = try LocalWhisperModelManager(rootDirectory: root)
    #expect(await relaunched.snapshot().state == .available)

    try Data("corrupted".utf8).write(to: fixtureFile)
    let corrupted = try LocalWhisperModelManager(rootDirectory: root)
    #expect(await corrupted.snapshot().state == .corrupt)

    try await corrupted.deleteModel()
    #expect(await corrupted.snapshot().state == .notInstalled)
}

@Test func unavailableLocalWhisperFailsSafelyWithoutDeveloperTooling() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "InterviewArcVoice-NoLocalWhisper-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = try LocalWhisperModelManager(rootDirectory: root)
    let transcriber = ManagedLocalWhisperTranscriber(manager: manager)

    do {
        _ = try await transcriber.transcribe(
            fileURL: root.appending(path: "answer.m4a"),
            prompt: "ignored",
            temporaryDirectory: root
        )
        Issue.record("Expected the optional model to be unavailable")
    } catch let error as LocalWhisperModelError {
        #expect(error == .unavailable)
    }
}

@Test func cancelledLocalWhisperRequestStopsBeforeModelLoading() async throws {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "InterviewArcVoice-CancelLocalWhisper-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let manager = try LocalWhisperModelManager(rootDirectory: root)
    let task = Task {
        try await manager.transcribe(fileURL: root.appending(path: "answer.m4a"))
    }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Expected local inference cancellation")
    } catch is CancellationError {
        // Expected.
    }
}
