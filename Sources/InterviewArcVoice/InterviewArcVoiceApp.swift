import SwiftUI
import InterviewArcVoiceCore

@main
struct InterviewArcVoiceApp: App {
    @StateObject private var model = VoiceBridgeModel()

    var body: some Scene {
        MenuBarExtra {
            VoiceBridgeMenu(model: model)
        } label: {
            Image(systemName: model.isRecording ? "waveform.circle.fill" : "waveform.circle")
                .accessibilityLabel(model.isRecording ? "Interview Arc Voice recording" : "Interview Arc Voice")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class VoiceBridgeModel: ObservableObject {
    enum Phase: Equatable {
        case setup
        case refreshing
        case idle
        case recording
        case transcribing
        case sending
        case delivered
        case queued
        case failed(String)

        var label: String {
            switch self {
            case .setup: "Setup needed"
            case .refreshing: "Finding focused activity"
            case .idle: "Ready"
            case .recording: "Recording"
            case .transcribing: "Transcribing with Groq"
            case .sending: "Sending to specialist"
            case .delivered: "Answer delivered"
            case .queued: "Delivered with a retry queued"
            case .failed: "Needs attention"
            }
        }

        var symbol: String {
            switch self {
            case .recording: "waveform"
            case .transcribing, .sending, .refreshing: "arrow.triangle.2.circlepath"
            case .delivered: "checkmark"
            case .queued: "clock.arrow.circlepath"
            case .failed: "exclamationmark"
            case .setup: "key"
            case .idle: "mic"
            }
        }
    }

    @Published var phase: Phase = .refreshing
    @Published var context: VoiceContextResponse?
    @Published var lastTranscript = ""
    @Published var connectionTokenDraft = ""
    @Published var groqKeyDraft = ""
    @Published var settingsExpanded = false
    @Published var workspacePath: String
    @Published var apiBaseURL: String
    @Published var codexPath: String
    @Published var pendingRetryCount = 0

    let recorder = AnswerRecorder()

    private let keychain = KeychainStore()
    private var recordingURL: URL?
    private var recordingStore: RecordingStore?
    private var pipeline: VoicePipeline?

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool { phase == .refreshing || phase == .transcribing || phase == .sending }
    var focusedTitle: String { context?.focusedActivity?.title ?? "No focused activity" }
    var focusedSpecialty: PracticeSpecialty? { context?.focusedActivity?.specialty }
    var canRecord: Bool { context?.focusedActivity != nil && context?.specialist != nil && !isBusy }

    init() {
        let defaults = UserDefaults.standard
        apiBaseURL = defaults.string(forKey: "voice.apiBaseURL") ?? "https://limitless-mcp.vinosama.workers.dev"
        workspacePath = defaults.string(forKey: "voice.workspacePath") ?? "/Users/wenkxu/Projects/Interview Prep/interview-arc"
        codexPath = defaults.string(forKey: "voice.codexPath") ?? "/Applications/ChatGPT.app/Contents/Resources/codex"
        recordingStore = try? RecordingStore()
        connectionTokenDraft = (try? keychain.value(for: .interviewArcToken)) ?? ""
        groqKeyDraft = (try? keychain.value(for: .groqAPIKey)) ?? ""
        if connectionTokenDraft.isEmpty || groqKeyDraft.isEmpty { phase = .setup }
        Task { await refresh() }
    }

    func refresh() async {
        guard !connectionTokenDraft.isEmpty else {
            phase = .setup
            return
        }
        guard let baseURL = URL(string: apiBaseURL) else {
            phase = .failed("The Interview Arc API URL is invalid.")
            return
        }
        phase = .refreshing
        do {
            let api = InterviewArcAPIClient(baseURL: baseURL, token: connectionTokenDraft)
            let loaded = try await api.context()
            context = loaded
            if loaded.focusedActivity == nil {
                phase = .failed(loaded.message ?? "Focus an activity in Interview Arc first.")
            } else if loaded.specialist == nil {
                phase = .failed(loaded.message ?? "Connect the matching specialist task first.")
            } else if groqKeyDraft.isEmpty {
                phase = .setup
            } else {
                pipeline = try makePipeline()
                phase = .idle
            }
            await updateRetryCount()
            if pendingRetryCount > 0, pipeline != nil {
                Task { await retryPendingInBackground() }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func toggleRecording() {
        if isRecording {
            stopAndSend()
        } else {
            startRecording()
        }
    }

    func saveSettings() {
        do {
            try keychain.set(connectionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines), for: .interviewArcToken)
            try keychain.set(groqKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines), for: .groqAPIKey)
            UserDefaults.standard.set(apiBaseURL, forKey: "voice.apiBaseURL")
            UserDefaults.standard.set(workspacePath, forKey: "voice.workspacePath")
            UserDefaults.standard.set(codexPath, forKey: "voice.codexPath")
            settingsExpanded = false
            Task { await refresh() }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func retryPending() {
        phase = .sending
        Task {
            if pipeline == nil {
                do {
                    pipeline = try makePipeline()
                } catch {
                    phase = .failed(error.localizedDescription)
                    return
                }
            }
            guard let pipeline else { return }
            _ = await pipeline.retryPending()
            await updateRetryCount()
            phase = pendingRetryCount == 0 ? .delivered : .queued
        }
    }

    private func startRecording() {
        guard let activity = context?.focusedActivity else {
            phase = .failed("Focus an activity in Interview Arc first.")
            return
        }
        guard let recordingStore else {
            phase = .failed("Interview Arc Voice cannot open Application Support.")
            return
        }
        let destination = recordingStore.nextRecordingURL(activityID: activity.activityId)
        Task {
            do {
                try await recorder.start(at: destination)
                recordingURL = destination
                phase = .recording
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func stopAndSend() {
        guard let activity = context?.focusedActivity, let specialist = context?.specialist else {
            phase = .failed("The focused activity or specialist changed. Refresh and record again.")
            return
        }
        do {
            let recording = try recorder.stop()
            phase = .transcribing
            Task {
                await process(recording: recording, activity: activity, specialist: specialist)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func process(
        recording: (url: URL, duration: TimeInterval),
        activity: FocusedVoiceActivity,
        specialist: SpecialistRoute
    ) async {
        guard recordingStore != nil else {
            phase = .failed("Voice settings are incomplete.")
            return
        }
        do {
            let builtPipeline = try makePipeline()
            pipeline = builtPipeline
            let result = try await builtPipeline.process(
                recordingURL: recording.url,
                durationSeconds: recording.duration,
                activity: activity,
                specialist: specialist
            )
            lastTranscript = result.transcript
            await updateRetryCount()
            phase = result.hasQueuedRetry ? .queued : .delivered
            Task {
                try? await Task.sleep(for: .seconds(20))
                await updateRetryCount()
                if pendingRetryCount > 0, phase == .delivered { phase = .queued }
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func updateRetryCount() async {
        guard let recordingStore else { pendingRetryCount = 0; return }
        let queue = VoiceRetryQueue(directory: recordingStore.queueDirectory)
        pendingRetryCount = (try? await queue.items().count) ?? 0
    }

    private func makePipeline() throws -> VoicePipeline {
        guard let baseURL = URL(string: apiBaseURL), let recordingStore else {
            throw VoiceBridgeError.recordingUnavailable
        }
        let catalog = try VocabularyCatalog.bundled()
        return VoicePipeline(
            api: InterviewArcAPIClient(baseURL: baseURL, token: connectionTokenDraft),
            transcriber: GroqTranscriber(apiKey: groqKeyDraft),
            codex: CodexBridge(executableURL: URL(fileURLWithPath: codexPath)),
            vocabularyResolver: VocabularyResolver(catalog: catalog),
            retryQueue: VoiceRetryQueue(directory: recordingStore.queueDirectory),
            temporaryDirectory: recordingStore.temporaryDirectory,
            workspaceURL: URL(fileURLWithPath: workspacePath, isDirectory: true),
            interviewArcToken: connectionTokenDraft
        )
    }

    private func retryPendingInBackground() async {
        guard let pipeline else { return }
        let previousPhase = phase
        _ = await pipeline.retryPending()
        await updateRetryCount()
        if phase == previousPhase || phase == .idle {
            phase = pendingRetryCount == 0 ? .idle : .queued
        }
    }
}

private struct VoiceBridgeMenu: View {
    @ObservedObject var model: VoiceBridgeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusHeader
            activityCard
            recordingControl
            if !model.lastTranscript.isEmpty { transcriptPreview }
            if model.pendingRetryCount > 0 { retryRow }
            settings
            providerFooter
        }
        .padding(18)
        .frame(width: 380)
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(statusColor.opacity(0.14))
                Image(systemName: model.phase.symbol).foregroundStyle(statusColor)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.phase.label).font(.headline)
                if case .failed(let message) = model.phase {
                    Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                } else {
                    Text("Interview Arc Voice").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .frame(width: 44, height: 44)
                .disabled(model.isRecording || model.isBusy)
                .accessibilityLabel("Refresh focused activity")
        }
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.focusedSpecialty.map(specialtyLabel) ?? "NOT CONNECTED")
                .font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
            Text(model.focusedTitle).font(.title3.weight(.semibold)).lineLimit(3)
            Text(model.context?.specialist?.title ?? "Connect the matching specialist task")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var recordingControl: some View {
        HStack(spacing: 10) {
            Button(action: model.toggleRecording) {
                Label(model.isRecording ? "Stop and send" : "Record answer", systemImage: model.isRecording ? "stop.fill" : "mic.fill")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(model.isRecording ? .red : Color(red: 0.08, green: 0.34, blue: 0.22))
            .disabled(!model.isRecording && !model.canRecord)
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            if model.isRecording { RecordingClock(recorder: model.recorder) }
        }
    }

    private var transcriptPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LAST VERBATIM TRANSCRIPT").font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
            Text(model.lastTranscript).font(.caption).lineLimit(4).textSelection(.enabled)
        }
        .padding(.top, 2)
    }

    private var retryRow: some View {
        HStack {
            Label("\(model.pendingRetryCount) background retry\(model.pendingRetryCount == 1 ? "" : "ies")", systemImage: "clock.arrow.circlepath")
                .font(.caption)
            Spacer()
            Button("Retry now", action: model.retryPending).disabled(model.isBusy || model.isRecording)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
    }

    private var settings: some View {
        DisclosureGroup(isExpanded: $model.settingsExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                SecureField("Interview Arc token", text: $model.connectionTokenDraft)
                    .textFieldStyle(.roundedBorder)
                SecureField("Groq API key", text: $model.groqKeyDraft)
                    .textFieldStyle(.roundedBorder)
                TextField("Interview Arc API", text: $model.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Interview Arc repository", text: $model.workspacePath)
                    .textFieldStyle(.roundedBorder)
                TextField("Codex executable", text: $model.codexPath)
                    .textFieldStyle(.roundedBorder)
                Button("Save secure settings", action: model.saveSettings)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
        } label: {
            Label("Connection settings", systemImage: "key.horizontal")
                .font(.subheadline.weight(.medium))
        }
    }

    private var providerFooter: some View {
        HStack {
            Label("Groq Large v3", systemImage: "cloud")
            Spacer()
            Label("Private R2", systemImage: "lock.fill")
            Spacer()
            Label("Delivery Coach", systemImage: "waveform.badge.magnifyingglass")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var statusColor: Color {
        switch model.phase {
        case .recording, .failed: .red
        case .queued, .setup: .orange
        case .delivered, .idle: .green
        default: .blue
        }
    }

    private func specialtyLabel(_ specialty: PracticeSpecialty) -> String {
        switch specialty {
        case .coding: "CODING"
        case .systemDesign: "SYSTEM DESIGN"
        case .behavioral: "BEHAVIORAL"
        }
    }
}

private struct RecordingClock: View {
    @ObservedObject var recorder: AnswerRecorder

    var body: some View {
        Text(clock(recorder.elapsedSeconds))
            .font(.system(.body, design: .monospaced).weight(.semibold))
            .frame(minWidth: 58)
            .accessibilityLabel("Recording time \(clock(recorder.elapsedSeconds))")
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
