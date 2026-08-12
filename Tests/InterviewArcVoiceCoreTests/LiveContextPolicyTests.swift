import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func desktopCodexCapturesMayAttachToInterviewArc() {
    let decision = CaptureTargetApplicationPolicy.decision(
        for: CaptureTargetDescriptor(
            bundleIdentifier: "com.openai.codex",
            windowTitle: nil
        )
    )

    #expect(decision.canAttach)
    #expect(decision.kind == .desktopCodex)
    #expect(decision.reason == .desktopCodex)
}

@Test func codexCLIInsideApprovedTerminalWorkspacesMayAttach() {
    let appleTerminal = CaptureTargetApplicationPolicy.decision(
        for: CaptureTargetDescriptor(
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "Interview Arc — Codex"
        )
    )
    let cmux = CaptureTargetApplicationPolicy.decision(
        for: CaptureTargetDescriptor(
            bundleIdentifier: "com.cmuxterm.app",
            windowTitle: "Interview Arc — Native cmux"
        )
    )
    let warp = CaptureTargetApplicationPolicy.decision(
        for: CaptureTargetDescriptor(
            bundleIdentifier: "dev.warp.Warp-Stable",
            windowTitle: "Interview Arc"
        )
    )

    #expect(appleTerminal.canAttach)
    #expect(appleTerminal.kind == .codexCLITerminal)
    #expect(appleTerminal.reason == .verifiedCodexWorkspace)
    #expect(cmux.canAttach)
    #expect(cmux.kind == .codexCLITerminal)
    #expect(cmux.reason == .verifiedCodexWorkspace)
    #expect(warp.canAttach)
    #expect(warp.kind == .codexCLITerminal)
}

@Test func approvedWorkspaceTitleSupportsDetachedCodexCLITerminals() {
    let appleTerminalShell = CaptureTargetApplicationPolicy.decision(
        for: CaptureTargetDescriptor(
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "zsh — 80×24"
        )
    )
    let appleTerminalFallback = CaptureTargetApplicationPolicy.decision(
        for: CaptureTargetDescriptor(
            bundleIdentifier: "com.apple.Terminal",
            windowTitle: "Interview Arc — Codex",
            windowEvidence: .visibleWindowFallback
        )
    )
    let shell = CaptureTargetApplicationPolicy.decision(
        for: CaptureTargetDescriptor(
            bundleIdentifier: "com.cmuxterm.app",
            windowTitle: "Personal shell"
        )
    )
    let titledShellWithoutCodex = CaptureTargetApplicationPolicy.decision(
        for: CaptureTargetDescriptor(
            bundleIdentifier: "com.cmuxterm.app",
            windowTitle: "Interview Arc — shell"
        )
    )
    let detachedCodexWorkspace = CaptureTargetApplicationPolicy.decision(
        for: CaptureTargetDescriptor(
            bundleIdentifier: "com.cmuxterm.app",
            windowTitle: "Interview Arc — Coordinator | codex"
        )
    )
    let browser = CaptureTargetApplicationPolicy.decision(
        for: CaptureTargetDescriptor(
            bundleIdentifier: "com.google.Chrome",
            windowTitle: "Interview Arc Codex"
        )
    )
    let missing = CaptureTargetApplicationPolicy.decision(for: nil)

    #expect(!appleTerminalShell.canAttach)
    #expect(appleTerminalShell.reason == .terminalWithoutWorkspaceEvidence)
    #expect(!appleTerminalFallback.canAttach)
    #expect(appleTerminalFallback.reason == .terminalWithoutFocusedWindowEvidence)
    #expect(!shell.canAttach)
    #expect(shell.reason == .terminalWithoutWorkspaceEvidence)
    #expect(titledShellWithoutCodex.canAttach)
    #expect(titledShellWithoutCodex.reason == .verifiedCodexWorkspace)
    #expect(detachedCodexWorkspace.canAttach)
    #expect(detachedCodexWorkspace.kind == .codexCLITerminal)
    #expect(detachedCodexWorkspace.reason == .verifiedCodexWorkspace)
    #expect(!shell.canAttach)
    #expect(shell.reason == .terminalWithoutWorkspaceEvidence)
    #expect(!browser.canAttach)
    #expect(browser.reason == .unsupportedApplication)
    #expect(!missing.canAttach)
    #expect(missing.reason == .missingApplication)
}

@Test func routeEvaluationExplainsEverySilentDowngradeGate() {
    let target = CaptureTargetDecision(
        canAttach: true,
        kind: .codexCLITerminal,
        reason: .verifiedCodexCLIProcess
    )
    let evaluator = CaptureRouteEvaluationPolicy()

    #expect(evaluator.evaluate(
        linkEnabled: true,
        target: target,
        hasFocusedActivity: true,
        contextIsFresh: true,
        phase: .contextRefresh
    ) == CaptureRouteEvaluation(route: .linked, reason: .linkedAfterContextRefresh))
    #expect(evaluator.evaluate(
        linkEnabled: true,
        target: target,
        hasFocusedActivity: true,
        contextIsFresh: true
    ) == CaptureRouteEvaluation(route: .linked, reason: .linkedAtRecordStart))
    #expect(evaluator.evaluate(
        linkEnabled: true,
        target: target,
        hasFocusedActivity: true,
        contextIsFresh: false
    ) == CaptureRouteEvaluation(route: .general, reason: .staleFocusedContext))
    #expect(evaluator.evaluate(
        linkEnabled: true,
        target: CaptureTargetDecision(
            canAttach: true,
            kind: .codexCLITerminal,
            reason: .verifiedCodexWorkspace
        ),
        hasFocusedActivity: true,
        contextIsFresh: true
    ) == CaptureRouteEvaluation(route: .linked, reason: .linkedAtRecordStart))
    #expect(evaluator.evaluate(
        linkEnabled: true,
        target: CaptureTargetDecision(
            canAttach: false,
            kind: .other,
            reason: .unsupportedApplication
        ),
        hasFocusedActivity: true,
        contextIsFresh: true
    ) == CaptureRouteEvaluation(route: .general, reason: .unsupportedTarget))
}

@Test func staleContextRefreshCannotReplaceTheLatestActivity() {
    #expect(
        ContextRefreshOrderingPolicy.shouldApply(
            requestID: 8,
            latestRequestID: 9
        ) == false
    )
    #expect(
        ContextRefreshOrderingPolicy.shouldApply(
            requestID: 9,
            latestRequestID: 9
        )
    )
}

@Test func transientRefreshFailureRetainsLastKnownContext() {
    let previous = voiceContext(
        activityID: "course-schedule",
        runningSince: 1_000
    )

    #expect(
        VoiceContextRetentionPolicy().context(
            previous: previous,
            refreshed: nil
        ) == previous
    )
}

@Test func successfulEmptyRefreshClearsThePreviousActivity() {
    let previous = voiceContext(
        activityID: "course-schedule",
        runningSince: 1_000
    )
    let refreshed = VoiceContextResponse(
        protocolVersion: 2,
        date: "2026-07-24",
        focusedActivity: nil,
        timerInstrument: nil,
        specialist: nil,
        message: "No activity is running."
    )

    #expect(
        VoiceContextRetentionPolicy().context(
            previous: previous,
            refreshed: refreshed
        ) == refreshed
    )
}

@Test func exactLearningContextSelectsTranscriptOnlyCaptureAndAmbiguityFailsClosed() throws {
    let payload = Data(#"""
    {
      "protocolVersion": 2,
      "date": "2026-08-12",
      "captureTarget": "learning",
      "focusedActivity": null,
      "focusedLearningSession": {
        "sessionId": "session-architecture-1",
        "scopeType": "course",
        "courseId": "course-architecture",
        "blueprintRevision": 3,
        "courseTitle": "Interview Arc Architecture",
        "moduleId": "module-runtime",
        "moduleTitle": "Runtime",
        "lessonId": "lesson-voice-boundary",
        "lessonRevision": 2,
        "lessonTitle": "Voice boundary",
        "state": "running",
        "transcriptRevision": 4,
        "nextTranscriptSequence": 7,
        "startedAt": 1786507200000,
        "runningSince": 1786507205000,
        "evidencePolicy": "transcript_only"
      },
      "timerInstrument": null,
      "specialist": {
        "specialty": "learning_specialist",
        "threadId": "thread-learning",
        "hostId": null,
        "title": "Learning Specialist"
      },
      "message": null
    }
    """#.utf8)
    let context = try JSONDecoder().decode(VoiceContextResponse.self, from: payload)
    let session = try #require(context.focusedLearningSession)

    #expect(
        VoiceCaptureContextPolicy().selection(for: context)
            == .learning(session)
    )

    let ambiguous = VoiceContextResponse(
        protocolVersion: 2,
        date: "2026-08-12",
        captureTarget: .ambiguous,
        focusedActivity: focusedActivity(id: "interview", runningSince: 1_000),
        focusedLearningSession: session,
        timerInstrument: nil,
        specialist: nil,
        message: "Pause one active target."
    )

    #expect(VoiceCaptureContextPolicy().selection(for: ambiguous) == nil)
}

@Test func normalNetworkJitterDoesNotDropAVisibleLinkedActivity() {
    let policy = CaptureContextFreshnessPolicy(maximumAge: 10)
    let now = Date(timeIntervalSince1970: 20)

    #expect(
        policy.isFresh(
            lastVerifiedAt: Date(timeIntervalSince1970: 11),
            now: now
        )
    )
}

@Test func genuinelyStaleContextStillFallsBackToGeneralDictation() {
    let policy = CaptureContextFreshnessPolicy(maximumAge: 10)
    let now = Date(timeIntervalSince1970: 20)

    #expect(
        !policy.isFresh(
            lastVerifiedAt: Date(timeIntervalSince1970: 9),
            now: now
        )
    )
}

@Test func aGeneralCaptureMayLateBindToAnActivityAlreadyRunningAtRecordStart() {
    let activity = focusedActivity(
        id: "course-schedule",
        runningSince: 1_000
    )

    #expect(
        LateCaptureBindingPolicy().activity(
            initiallyLinkedActivityID: nil,
            recordingStartedAtMilliseconds: 2_000,
            refreshedActivity: activity
        ) == activity
    )
}

@Test func aGeneralCaptureNeverBindsToAnActivityStartedAfterRecording() {
    let activity = focusedActivity(
        id: "new-problem",
        runningSince: 2_500
    )

    #expect(
        LateCaptureBindingPolicy().activity(
            initiallyLinkedActivityID: nil,
            recordingStartedAtMilliseconds: 2_000,
            refreshedActivity: activity
        ) == nil
    )
}

@Test func anAlreadyLinkedCaptureNeverMovesWhenFocusChanges() {
    let activity = focusedActivity(
        id: "new-problem",
        runningSince: 1_000
    )

    #expect(
        LateCaptureBindingPolicy().activity(
            initiallyLinkedActivityID: "original-problem",
            recordingStartedAtMilliseconds: 2_000,
            refreshedActivity: activity
        ) == nil
    )
}

@Test func memoExportUsesActivityTitleAndCreatesSiblingTranscript() {
    let date = Date(timeIntervalSince1970: 1_721_863_200)
    let plan = VoiceMemoExportPlan(
        activityTitle: "Course Schedule: BFS / DFS?",
        createdAt: date
    )
    let audio = URL(fileURLWithPath: "/tmp/\(plan.suggestedAudioFilename)")

    #expect(plan.suggestedAudioFilename == "Course Schedule BFS DFS.m4a")
    #expect(plan.transcriptURL(forAudioURL: audio).lastPathComponent == "Course Schedule BFS DFS.txt")
}

@Test func memoExportFallsBackToTimestampWhenUnlinked() {
    let date = Date(timeIntervalSince1970: 1_721_863_200)
    let plan = VoiceMemoExportPlan(activityTitle: nil, createdAt: date)

    #expect(plan.suggestedAudioFilename.hasPrefix("Interview Arc Voice "))
    #expect(plan.suggestedAudioFilename.hasSuffix(".m4a"))
}

@Test func lateBoundRecordingMovesFromTemporaryStorageToLinkedStorage() throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "voice-store-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try RecordingStore(rootDirectory: root)
    let temporaryURL = store.nextTemporaryRecordingURL()
    try Data("audio".utf8).write(to: temporaryURL)
    let recording = RecordedCapture(
        url: temporaryURL,
        duration: 2,
        writtenFrameCount: 1,
        writeErrorDescription: nil
    )

    let promoted = try store.promoteToLinkedRecording(
        recording,
        activityID: "course-schedule"
    )

    #expect(promoted.url.deletingLastPathComponent() == store.recordingsDirectory)
    #expect(FileManager.default.fileExists(atPath: promoted.url.path))
    #expect(!FileManager.default.fileExists(atPath: temporaryURL.path))
}

@Test func playbackCompletionRecognizesAVFoundationClockReset() {
    let policy = PlaybackCompletionPolicy()

    #expect(policy.didFinish(previousTime: 40.9, currentTime: 0, duration: 41))
    #expect(!policy.didFinish(previousTime: 12, currentTime: 12, duration: 41))
    #expect(!policy.didFinish(previousTime: 12, currentTime: 0, duration: 41))
}

private func voiceContext(
    activityID: String,
    runningSince: Int64
) -> VoiceContextResponse {
    VoiceContextResponse(
        protocolVersion: 2,
        date: "2026-07-24",
        focusedActivity: focusedActivity(
            id: activityID,
            runningSince: runningSince
        ),
        timerInstrument: nil,
        specialist: nil,
        message: nil
    )
}

private func focusedActivity(
    id: String,
    runningSince: Int64
) -> FocusedVoiceActivity {
    FocusedVoiceActivity(
        activityId: id,
        questionId: nil,
        specialty: .coding,
        interviewArcSpecialty: "leetcode",
        title: id,
        prompt: nil,
        topics: [],
        tags: [],
        companies: [],
        projects: [],
        vocabularyPackIds: [],
        speechTerms: [],
        startedAt: runningSince - 500,
        runningSince: runningSince
    )
}
