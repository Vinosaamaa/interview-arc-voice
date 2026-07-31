import Foundation
import Testing
@testable import InterviewArcVoiceCore

private func retentionRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    return root
}

private func writeAudio(
    _ bytes: Int,
    named name: String,
    in directory: URL
) throws -> URL {
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    let url = directory.appending(path: name)
    try Data(repeating: 0x2A, count: bytes).write(to: url)
    return url
}

@Test func generalHistoryArchivesTheExactRecordingWithPrivatePermissions() async throws {
    let root = try retentionRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let metadata = root.appending(path: "TranscriptHistory", directoryHint: .isDirectory)
    let recent = root.appending(path: "RecentHistory", directoryHint: .isDirectory)
    let temporary = root.appending(path: "Transcription", directoryHint: .isDirectory)
    let source = try writeAudio(32, named: "general.m4a", in: temporary)
    let store = try LocalTranscriptHistoryStore(
        directory: metadata,
        audioDirectory: recent
    )
    let record = LocalTranscriptRecord(
        transcript: "Course Schedule",
        editorText: "Course Schedule",
        durationSeconds: 4
    )

    let archived = try await store.append(record, recordingURL: source)
    let retainedURL = try #require(await store.audioURL(for: archived))

    #expect(!FileManager.default.fileExists(atPath: source.path))
    #expect(try Data(contentsOf: retainedURL) == Data(repeating: 0x2A, count: 32))
    #expect(archived.audioReference != nil)
    let directoryAttributes = try FileManager.default.attributesOfItem(
        atPath: recent.path
    )
    let fileAttributes = try FileManager.default.attributesOfItem(
        atPath: retainedURL.path
    )
    #expect((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func acceptedLinkedAudioMovesOnlyAfterItsHistoryRecordExists() async throws {
    let root = try retentionRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let linked = root.appending(path: "LinkedPending", directoryHint: .isDirectory)
    let source = try writeAudio(48, named: "capture.m4a", in: linked)
    let store = try LocalTranscriptHistoryStore(
        directory: root.appending(path: "TranscriptHistory"),
        audioDirectory: root.appending(path: "RecentHistory")
    )
    let record = LocalTranscriptRecord(
        transcript: "Explain the invariant",
        editorText: "voice envelope",
        durationSeconds: 8,
        activityTitle: "Course Schedule",
        captureID: "capture-1"
    )
    _ = try await store.append(record)

    #expect(try await store.adoptLinkedAudio(
        captureID: "capture-1",
        recordingURL: source
    ))
    let retained = try #require(
        try await store.records().first(where: { $0.captureID == "capture-1" })
    )
    let retainedURL = try #require(await store.audioURL(for: retained))
    #expect(!FileManager.default.fileExists(atPath: source.path))
    #expect(FileManager.default.fileExists(atPath: retainedURL.path))
}

@Test func historyPruningNeverDeletesLifecycleProtectedLinkedAudio() async throws {
    let root = try retentionRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let linked = root.appending(path: "LinkedPending", directoryHint: .isDirectory)
    let store = try LocalTranscriptHistoryStore(
        directory: root.appending(path: "TranscriptHistory"),
        audioDirectory: root.appending(path: "RecentHistory"),
        retentionLimit: 20
    )
    let now = Date(timeIntervalSince1970: 20_000_000)
    var linkedURLs: [URL] = []

    for index in 0..<30 {
        let source = try writeAudio(
            8,
            named: "capture-\(index).m4a",
            in: linked
        )
        linkedURLs.append(source)
        _ = try await store.append(
            LocalTranscriptRecord(
                createdAt: now.addingTimeInterval(Double(index)),
                transcript: "Transcript \(index)",
                editorText: "Envelope \(index)",
                durationSeconds: 1,
                captureID: "capture-\(index)"
            ),
            now: now.addingTimeInterval(Double(index))
        )
    }

    #expect(try await store.records(now: now.addingTimeInterval(30)).count == 20)
    #expect(linkedURLs.allSatisfy {
        FileManager.default.fileExists(atPath: $0.path)
    })
    #expect(!(try await store.adoptLinkedAudio(
        captureID: "capture-0",
        recordingURL: linkedURLs[0],
        now: now.addingTimeInterval(30)
    )))
    #expect(FileManager.default.fileExists(atPath: linkedURLs[0].path))
}

@Test func countAgeDiskDeleteAndClearRemoveHistoryOnlyAudioAtomically() async throws {
    let root = try retentionRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let temporary = root.appending(path: "Transcription", directoryHint: .isDirectory)
    let store = try LocalTranscriptHistoryStore(
        directory: root.appending(path: "TranscriptHistory"),
        audioDirectory: root.appending(path: "RecentHistory"),
        retentionDuration: 100,
        retentionLimit: 3,
        diskBudgetBytes: 25
    )
    let now = Date(timeIntervalSince1970: 30_000_000)
    var retained: [LocalTranscriptRecord] = []

    for index in 0..<4 {
        let source = try writeAudio(10, named: "\(index).m4a", in: temporary)
        retained.append(try await store.append(
            LocalTranscriptRecord(
                createdAt: now.addingTimeInterval(Double(index)),
                transcript: "Transcript \(index)",
                editorText: "Transcript \(index)",
                durationSeconds: 1
            ),
            recordingURL: source,
            now: now.addingTimeInterval(Double(index))
        ))
    }

    let afterBudget = try await store.records(now: now.addingTimeInterval(4))
    #expect(afterBudget.count == 2)
    #expect(afterBudget.map(\.transcript) == ["Transcript 3", "Transcript 2"])

    try await store.delete(id: afterBudget[0].id)
    #expect(try await store.records(now: now.addingTimeInterval(4)).count == 1)
    try await store.clear()
    #expect(try await store.records(now: now.addingTimeInterval(4)).isEmpty)

    let expiringSource = try writeAudio(10, named: "expiring.m4a", in: temporary)
    let expiring = try await store.append(
        LocalTranscriptRecord(
            createdAt: now,
            transcript: "Old",
            editorText: "Old",
            durationSeconds: 1
        ),
        recordingURL: expiringSource,
        now: now
    )
    let expiringURL = try #require(await store.audioURL(for: expiring))
    #expect(try await store.records(now: now.addingTimeInterval(101)).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: expiringURL.path))
}

@Test func interruptedLinkedMoveIsRepairedWithoutCreatingADuplicate() async throws {
    let root = try retentionRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let recent = root.appending(path: "RecentHistory", directoryHint: .isDirectory)
    let store = try LocalTranscriptHistoryStore(
        directory: root.appending(path: "TranscriptHistory"),
        audioDirectory: recent
    )
    let record = LocalTranscriptRecord(
        transcript: "Recovered",
        editorText: "Recovered",
        durationSeconds: 2,
        captureID: "capture-recovered"
    )
    _ = try await store.append(record)
    let interruptedDestination = recent.appending(path: "\(record.id.uuidString.lowercased()).m4a")
    _ = try writeAudio(
        12,
        named: interruptedDestination.lastPathComponent,
        in: recent
    )
    let missingSource = root.appending(path: "LinkedPending/missing.m4a")

    #expect(try await store.adoptLinkedAudio(
        captureID: "capture-recovered",
        recordingURL: missingSource
    ))
    let repaired = try #require(
        try await store.records().first(where: {
            $0.captureID == "capture-recovered"
        })
    )
    #expect(await store.audioURL(for: repaired) == interruptedDestination)
}

@Test func recordingStoreCreatesPrivateLifecycleDirectoriesAndMigratesMetadata() throws {
    let root = try retentionRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let legacyPending = root.appending(
        path: "PendingCaptures",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
        at: legacyPending,
        withIntermediateDirectories: true
    )
    let legacyMetadata = legacyPending.appending(path: "capture-legacy.json")
    try Data("{}".utf8).write(to: legacyMetadata)

    let store = try RecordingStore(rootDirectory: root)
    let migrated = store.linkedPendingDirectory
        .appending(path: legacyMetadata.lastPathComponent)

    #expect(store.recordingsDirectory == store.linkedPendingDirectory)
    #expect(store.pendingCapturesDirectory == store.linkedPendingDirectory)
    #expect(FileManager.default.fileExists(atPath: migrated.path))
    #expect(!FileManager.default.fileExists(atPath: legacyMetadata.path))
    for directory in [
        store.linkedPendingDirectory,
        store.recentHistoryDirectory,
        store.recoveryDirectory,
    ] {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: directory.path
        )
        #expect(
            (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
        )
    }
    let metadataAttributes = try FileManager.default.attributesOfItem(
        atPath: migrated.path
    )
    #expect(
        (metadataAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600
    )
}
