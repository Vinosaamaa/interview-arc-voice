import Foundation

public actor CodexBridge {
    private let executableURL: URL

    public init(executableURL: URL = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")) {
        self.executableURL = executableURL
    }

    public func runDeliveryCoach(
        analysisID: String,
        activity: FocusedVoiceActivity,
        clipID: String,
        turnID: String,
        transcript: String,
        transcription: TranscriptionResult,
        audioURL: URL,
        workspaceURL: URL,
        interviewArcToken: String
    ) async throws {
        let wordTiming = transcription.words.prefix(2_500).map {
            "\(String(format: "%.2f", $0.start))-\(String(format: "%.2f", $0.end)) \($0.word)"
        }.joined(separator: "\n")
        let prompt = """
        You are the background Interview Arc Delivery Coach for one recorded practice answer. This is an ephemeral analysis task, not the visible specialist conversation.

        Analyze only observable delivery evidence: pace, pauses, filler words, clarity, organization, vocal variation, and perceived confidence. Do not infer mental state, health, identity, personality, or any other sensitive trait. Use the local recording and the verbatim transcript. Keep feedback concrete and supportive.

        activityId: \(activity.activityId)
        activityTitle: \(activity.title)
        specialty: \(activity.interviewArcSpecialty)
        analysisId: \(analysisID)
        audioClipId: \(clipID)
        transcriptTurnId: \(turnID)
        durationSeconds: \(String(format: "%.2f", transcription.durationSeconds))
        localAudioPath: \(audioURL.path)

        Verbatim transcript:
        \(transcript)

        Whisper word timestamps (may be empty):
        \(wordTiming)

        Use local, read-only audio inspection tools if useful. Then call the Interview Arc MCP tool `save_delivery_analysis` exactly once with status `available` and a schemaVersion 1 payload. Include a concise summary, measurable wordsPerMinute when supported, filler counts, long pauses when supported, strengths, improvements, and evidence-grounded observations. If the recording cannot be analyzed, call the same tool with status `failed` and a concise error instead. Do not modify repository files.
        """
        let result = try await runCodex(
            arguments: ["exec", "--ephemeral", "--sandbox", "workspace-write", "-C", workspaceURL.path, "-"],
            prompt: prompt,
            workspaceURL: workspaceURL,
            interviewArcToken: interviewArcToken
        )
        guard result.exitCode == 0 else {
            throw VoiceBridgeError.codexUnavailable(result.errorOutput.isEmpty ? result.standardOutput : result.errorOutput)
        }
    }

    private func runCodex(
        arguments: [String],
        prompt: String,
        workspaceURL: URL,
        interviewArcToken: String
    ) async throws -> ProcessResult {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw VoiceBridgeError.codexUnavailable("Set the Codex executable path in Interview Arc Voice settings.")
        }
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workspaceURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        var environment = ProcessInfo.processInfo.environment
        environment["INTERVIEW_ARC_MCP_TOKEN"] = interviewArcToken
        process.environment = environment

        try process.run()
        try input.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
        try input.fileHandleForWriting.close()

        async let stdoutData = output.fileHandleForReading.readToEnd()
        async let stderrData = error.fileHandleForReading.readToEnd()
        process.waitUntilExit()
        let exitCode = process.terminationStatus
        let standardOutput = String(data: (try await stdoutData) ?? Data(), encoding: .utf8) ?? ""
        let errorOutput = String(data: (try await stderrData) ?? Data(), encoding: .utf8) ?? ""
        return ProcessResult(exitCode: exitCode, standardOutput: standardOutput, errorOutput: errorOutput)
    }
}

private struct ProcessResult: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let errorOutput: String
}
