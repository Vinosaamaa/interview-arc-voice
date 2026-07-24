import AppKit
import AVFoundation
import Carbon
import SwiftUI
import InterviewArcVoiceCore

private struct SecureCredentialSnapshot: Sendable {
    let interviewArcToken: String
    let groqAPIKey: String
    let errorDescription: String?
}

@main
struct InterviewArcVoiceApp: App {
    @StateObject private var model: VoiceBridgeModel

    init() {
        if ProcessInfo.processInfo.arguments.contains("--verify-package") {
            do {
                let catalog = try VocabularyCatalog.bundled()
                print("Interview Arc Voice package verified with \(catalog.packs.count) vocabulary packs.")
                exit(EXIT_SUCCESS)
            } catch {
                fputs("Interview Arc Voice package verification failed: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }
        _model = StateObject(wrappedValue: VoiceBridgeModel())
    }

    var body: some Scene {
        MenuBarExtra {
            VoiceBridgeMenu(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
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
        case inserting
        case delivered
        case queued
        case failed(String)

        var label: String {
            switch self {
            case .setup: "Add your Groq key"
            case .refreshing: "Checking current activity"
            case .idle: "Ready"
            case .recording: "Recording"
            case .transcribing: "Transcribing with Groq"
            case .sending: "Saving interview answer"
            case .inserting: "Inserting at the cursor"
            case .delivered: "Complete"
            case .queued: "Complete with retry queued"
            case .failed: "Needs attention"
            }
        }

        var symbol: String {
            switch self {
            case .recording: "waveform.circle.fill"
            case .transcribing, .sending, .refreshing, .inserting: "arrow.triangle.2.circlepath"
            case .delivered: "checkmark.circle.fill"
            case .queued: "clock.arrow.circlepath"
            case .failed: "exclamationmark.triangle.fill"
            case .setup: "key.fill"
            case .idle: "mic.circle"
            }
        }
    }

    private enum CaptureDestination {
        case linked(FocusedVoiceActivity, startedAt: Date)
        case general
    }

    @Published var phase: Phase = .setup
    @Published var context: VoiceContextResponse?
    @Published var contextMessage = "Loading secure settings…"
    @Published var lastTranscript = ""
    @Published var connectionTokenDraft = ""
    @Published var groqKeyDraft = ""
    @Published var settingsExpanded = false
    @Published var workspacePath: String
    @Published var apiBaseURL: String
    @Published var codexPath: String
    @Published var pendingRetryCount = 0
    @Published var linkToInterviewArc: Bool
    @Published var shortcut: HotKeyShortcut
    @Published var shortcutCapturing = false
    @Published var accessibilityNeeded = false
    @Published var deliveryStates: [VoiceDeliveryComponent: VoiceDeliveryComponentState] = [:]
    @Published private(set) var hasLastAudio = false
    @Published private(set) var isPlayingLastAudio = false
    @Published private(set) var canRetryLastTranscription = false
    @Published private(set) var processingElapsedSeconds: TimeInterval = 0
    @Published private(set) var showProcessingIndicator = false

    let recorder = AnswerRecorder()

    private let keychain = KeychainStore()
    private let routingPolicy = CaptureRoutingPolicy()
    private let hotKeyManager = GlobalHotKeyManager()
    private let textInjector = DictationTextInjector()
    private var recordingStore: RecordingStore?
    private var pipeline: VoicePipeline?
    private var captureDestination: CaptureDestination?
    private var captureGeneration = UUID()
    private var targetApplicationPID: pid_t?
    private var lastInsertionText = ""
    private var shortcutMonitor: Any?
    private var lastInsertionSucceeded = false
    private var contextPollTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var lastExternalApplicationPID: pid_t?
    private var lastAudioData: Data?
    private var lastAudioDuration: TimeInterval = 0
    private var lastMemoCreatedAt = Date()
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var processingTimer: Timer?
    private var processingIndicatorTask: Task<Void, Never>?

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool { [.refreshing, .transcribing, .sending, .inserting].contains(phase) }
    var hasGroqCredential: Bool {
        !groqKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canRecord: Bool {
        hasGroqCredential && !isBusy
    }
    var menuBarSymbol: String {
        switch phase {
        case .recording: "waveform.circle.fill"
        case .transcribing, .sending, .inserting: "arrow.triangle.2.circlepath.circle.fill"
        case .queued: "clock.badge.exclamationmark.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "waveform.circle"
        }
    }
    var floatingEyebrow: String {
        if !linkToInterviewArc { return "GENERAL DICTATION" }
        if let activity = context?.focusedActivity { return specialtyLabel(activity.specialty).uppercased() + " · LINKED" }
        return "AUTO-LINK ON · GENERAL FALLBACK"
    }
    var floatingTitle: String {
        if !linkToInterviewArc { return "Paste speech into the active app" }
        return context?.focusedActivity?.title ?? "No focused activity — dictation stays unlinked"
    }
    var compactStatus: String {
        if case .failed(let message) = phase { return message }
        if phase == .idle, !contextMessage.isEmpty { return contextMessage }
        return phase.label
    }
    var showsDeliverySteps: Bool { !deliveryStates.isEmpty }
    var hasLastMemo: Bool { hasLastAudio || !lastTranscript.isEmpty }
    var lastMemoDetails: String {
        let words = lastTranscript.split(whereSeparator: \.isWhitespace).count
        let duration = clock(lastAudioDuration)
        if words == 0 { return duration }
        return "\(words) words · \(duration)"
    }
    var processingStatus: String {
        "\(phase.label) · \(clock(processingElapsedSeconds))"
    }
    var linkStatusSymbol: String {
        if !linkToInterviewArc { return "link" }
        return context?.focusedActivity == nil ? "link.circle" : "link.circle.fill"
    }
    var linkStatusColor: Color {
        if !linkToInterviewArc {
            return Color(red: 0.08, green: 0.20, blue: 0.42)
        }
        if context?.focusedActivity == nil {
            return Color(red: 0.92, green: 0.64, blue: 0.22)
        }
        return Color(red: 0.40, green: 0.84, blue: 0.79)
    }
    var linkStatusAccessibilityLabel: String {
        if !linkToInterviewArc { return "General dictation. Interview Arc linking is off." }
        if let activity = context?.focusedActivity { return "Linked to \(activity.title)." }
        return "Auto-link is on. No activity is focused, so recording will use general dictation."
    }

    init() {
        let defaults = UserDefaults.standard
        apiBaseURL = defaults.string(forKey: "voice.apiBaseURL") ?? "https://limitless-mcp.vinosama.workers.dev"
        workspacePath = defaults.string(forKey: "voice.workspacePath") ?? "/Users/wenkxu/Projects/Interview Prep/interview-arc"
        codexPath = defaults.string(forKey: "voice.codexPath") ?? "/Applications/ChatGPT.app/Contents/Resources/codex"
        linkToInterviewArc = defaults.object(forKey: "voice.linkToInterviewArc") as? Bool ?? true
        if let data = defaults.data(forKey: "voice.shortcut"),
           let saved = try? JSONDecoder().decode(HotKeyShortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .standard
        }
        recordingStore = try? RecordingStore()
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApplicationPID = frontmost.processIdentifier
        }

        // Present visible UI before touching Keychain. A credential prompt or
        // error must never make this agent-style app appear to launch and quit.
        Task {
            await Task.yield()
            FloatingPanelController.shared.show(model: self)
            hotKeyManager.register(shortcut) { [weak self] in self?.toggleRecording() }
            await loadSecureSettings()
            startContextPolling()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshContext(showProgress: false) }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.bundleIdentifier != Bundle.main.bundleIdentifier else {
                return
            }
            Task { @MainActor in
                self?.lastExternalApplicationPID = application.processIdentifier
            }
        }
    }

    func refresh() async {
        await refreshContext(showProgress: true)
    }

    func toggleRecording() {
        if isRecording {
            stopAndProcess()
        } else {
            Task { await prepareAndStartRecording() }
        }
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastTranscript, forType: .string)
        contextMessage = "Transcript copied."
    }

    func toggleLastAudioPlayback() {
        guard let lastAudioData else { return }
        if let audioPlayer, audioPlayer.isPlaying {
            audioPlayer.pause()
            isPlayingLastAudio = false
            playbackTimer?.invalidate()
            playbackTimer = nil
            return
        }
        do {
            let player = try AVAudioPlayer(data: lastAudioData)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            isPlayingLastAudio = true
            playbackTimer?.invalidate()
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    if self.audioPlayer?.isPlaying != true {
                        self.isPlayingLastAudio = false
                        self.playbackTimer?.invalidate()
                        self.playbackTimer = nil
                    }
                }
            }
        } catch {
            phase = .failed("The last recording could not be played.")
        }
    }

    func exportLastMemo() {
        guard hasLastMemo else { return }
        let panel = NSOpenPanel()
        panel.title = "Save Voice Memo"
        panel.message = "Choose a folder for the original audio and verbatim transcript."
        panel.prompt = "Save"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let basename = "Interview Arc Voice \(formatter.string(from: lastMemoCreatedAt))"
        do {
            if let lastAudioData {
                try lastAudioData.write(
                    to: directory.appending(path: basename + ".m4a"),
                    options: .atomic
                )
            }
            if !lastTranscript.isEmpty {
                try lastTranscript.write(
                    to: directory.appending(path: basename + ".txt"),
                    atomically: true,
                    encoding: .utf8
                )
            }
            contextMessage = "Voice memo saved."
        } catch {
            phase = .failed("The voice memo could not be saved: \(error.localizedDescription)")
        }
    }

    func retryLastTranscription() {
        guard canRetryLastTranscription,
              let lastAudioData,
              let recordingStore else { return }
        let retryURL = recordingStore.nextTemporaryRecordingURL()
        do {
            try lastAudioData.write(to: retryURL, options: .atomic)
            targetApplicationPID = currentInsertionTargetPID()
            canRetryLastTranscription = false
            beginProcessing()
            phase = .transcribing
            Task {
                await processGeneral(
                    recording: RecordedCapture(
                        url: retryURL,
                        duration: lastAudioDuration,
                        writtenFrameCount: 1,
                        writeErrorDescription: nil
                    ),
                    rememberAudio: false
                )
            }
        } catch {
            phase = .failed("The recording could not be prepared for retry.")
        }
    }

    func toggleLinkMode() {
        setLinkMode(!linkToInterviewArc)
    }

    func setLinkMode(_ enabled: Bool) {
        guard !isRecording else { return }
        linkToInterviewArc = enabled
        UserDefaults.standard.set(enabled, forKey: "voice.linkToInterviewArc")
        if !isBusy {
            deliveryStates = [:]
        }
        if enabled {
            contextMessage = "Auto-link will check the current activity before recording."
            if !isBusy {
                phase = hasGroqCredential ? .idle : .setup
            }
            Task { await refreshContext(showProgress: false) }
        } else {
            contextMessage = "General dictation will not touch Interview Arc."
            if !isBusy {
                phase = hasGroqCredential ? .idle : .setup
            }
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
            Task { await refreshContext(showProgress: false) }
        } catch {
            phase = .failed("Secure settings could not be saved: \(error.localizedDescription)")
        }
    }

    func requestAccessibilityPermission() {
        textInjector.requestAccessibilityPermission()
        accessibilityNeeded = !textInjector.accessibilityTrusted
    }

    func beginShortcutCapture() {
        guard shortcutMonitor == nil else { return }
        shortcutCapturing = true
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if Int(event.keyCode) == kVK_Escape {
                self.endShortcutCapture()
                return nil
            }
            guard let shortcut = HotKeyShortcut.from(event: event) else { return nil }
            self.shortcut = shortcut
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: "voice.shortcut")
            }
            self.hotKeyManager.register(shortcut) { [weak self] in self?.toggleRecording() }
            self.endShortcutCapture()
            return nil
        }
    }

    func retryPending() {
        phase = .sending
        Task {
            if pipeline == nil { pipeline = try? makeLinkedPipeline() }
            guard let pipeline else {
                phase = .failed("Add the Interview Arc token before retrying linked delivery.")
                return
            }
            _ = await pipeline.retryPending()
            await updateRetryCount()
            phase = pendingRetryCount == 0 ? .delivered : .queued
        }
    }

    func toggleFloatingPanel() {
        FloatingPanelController.shared.toggle(model: self)
    }

    private func loadSecureSettings() async {
        let keychain = keychain
        let snapshot = await Task.detached(priority: .userInitiated) {
            do {
                return SecureCredentialSnapshot(
                    interviewArcToken: try keychain.value(for: .interviewArcToken) ?? "",
                    groqAPIKey: try keychain.value(for: .groqAPIKey) ?? "",
                    errorDescription: nil
                )
            } catch {
                return SecureCredentialSnapshot(
                    interviewArcToken: "",
                    groqAPIKey: "",
                    errorDescription: error.localizedDescription
                )
            }
        }.value

        connectionTokenDraft = snapshot.interviewArcToken
        groqKeyDraft = snapshot.groqAPIKey
        if snapshot.errorDescription != nil {
            contextMessage = "Keychain access failed. Open Connection settings to enter the keys again."
        }
        accessibilityNeeded = !textInjector.accessibilityTrusted
        phase = hasGroqCredential ? .idle : .setup
        await refreshContext(showProgress: false)
    }

    private func refreshContext(showProgress: Bool) async {
        guard linkToInterviewArc else {
            contextMessage = "General dictation will not touch Interview Arc."
            settlePhaseAfterContextRefresh(force: showProgress)
            return
        }
        let token = connectionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            context = nil
            contextMessage = "No Interview Arc token — general dictation is still available."
            settlePhaseAfterContextRefresh(force: showProgress)
            return
        }
        guard let baseURL = URL(string: apiBaseURL) else {
            context = nil
            contextMessage = "Interview Arc API address is invalid — using general dictation."
            settlePhaseAfterContextRefresh(force: showProgress)
            return
        }
        if showProgress { phase = .refreshing }
        do {
            let loaded = try await InterviewArcAPIClient(baseURL: baseURL, token: token).context()
            context = loaded
            if let activity = loaded.focusedActivity {
                contextMessage = "Linked to \(activity.title)"
            } else {
                contextMessage = "No focused activity — using general dictation."
            }
            pipeline = try? makeLinkedPipeline()
            await updateRetryCount()
            if pendingRetryCount > 0, pipeline != nil {
                Task { await retryPendingInBackground() }
            }
        } catch {
            context = nil
            contextMessage = "Interview Arc is unavailable — using general dictation."
        }
        settlePhaseAfterContextRefresh(force: showProgress)
    }

    private func startContextPolling() {
        contextPollTask?.cancel()
        contextPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.linkToInterviewArc, !self.isRecording, !self.isBusy else { continue }
                await self.refreshContext(showProgress: false)
            }
        }
    }

    private func prepareAndStartRecording() async {
        guard canRecord else {
            phase = .setup
            contextMessage = "Add your Groq API key in Connection settings."
            return
        }
        guard textInjector.accessibilityTrusted else {
            accessibilityNeeded = true
            textInjector.requestAccessibilityPermission()
            phase = .failed("Enable Accessibility so Voice can insert text at the focused cursor.")
            return
        }
        targetApplicationPID = currentInsertionTargetPID()
        deliveryStates = [:]
        canRetryLastTranscription = false
        captureGeneration = UUID()

        // Context is refreshed continuously while idle. Opening the
        // microphone must not wait for a network round trip because that
        // loses the first words of an answer.
        let route = routingPolicy.route(
            linkToInterviewArc: linkToInterviewArc,
            hasFocusedActivity: context?.focusedActivity != nil
        )
        switch route {
        case .linked:
            guard let activity = context?.focusedActivity else { return }
            captureDestination = .linked(activity, startedAt: Date())
        case .general:
            captureDestination = .general
        }

        guard let recordingStore else {
            phase = .failed("Interview Arc Voice cannot open its private recording folder.")
            return
        }
        let destination: URL
        switch captureDestination {
        case .linked(let activity, _): destination = recordingStore.nextRecordingURL(activityID: activity.activityId)
        case .general: destination = recordingStore.nextTemporaryRecordingURL()
        case nil: return
        }
        do {
            try await recorder.start(at: destination)
            phase = .recording
            if linkToInterviewArc {
                Task { await refreshContext(showProgress: false) }
            }
        } catch {
            self.captureDestination = nil
            canRetryLastTranscription = false
            phase = .failed(error.localizedDescription)
            contextMessage = "Voice could not start the microphone."
        }
    }

    private func stopAndProcess() {
        guard let captureDestination else {
            phase = .failed("The recording destination was lost. Record again.")
            return
        }
        do {
            let recording = try recorder.stop()
            let generation = captureGeneration
            self.captureDestination = nil
            let recovery = try recordingRecoveryAction(for: recording)
            switch recovery {
            case .transcribe:
                rememberLastAudio(recording)
            case .preserveWithoutRetry:
                rememberLastAudio(recording)
                canRetryLastTranscription = false
                phase = .failed("Recording ended early.")
                contextMessage = "The playable portion is preserved. Record again for a complete transcript."
                return
            case .recordAgain:
                clearLastMemo()
                canRetryLastTranscription = false
                phase = .failed("No usable speech was captured.")
                contextMessage = "Check the microphone input, then record again. Voice will not insert a guessed transcript."
                return
            }
            beginProcessing()
            phase = .transcribing
            Task {
                switch captureDestination {
                case .linked(let activity, let startedAt):
                    await processLinked(
                        recording: recording,
                        activity: activity,
                        startedAt: startedAt,
                        generation: generation
                    )
                case .general:
                    await processGeneral(recording: recording, rememberAudio: false)
                }
            }
        } catch {
            self.captureDestination = nil
            clearLastMemo()
            canRetryLastTranscription = false
            phase = .failed("No usable speech was captured.")
            contextMessage = "Check the microphone input, then record again. Voice will not insert a guessed transcript."
        }
    }

    private func processGeneral(
        recording: RecordedCapture,
        rememberAudio: Bool = true
    ) async {
        guard let recordingStore else {
            endProcessing()
            phase = .failed("Voice settings are incomplete.")
            return
        }
        if rememberAudio { rememberLastAudio(recording) }
        do {
            try validateRecording(recording)
        } catch {
            canRetryLastTranscription = false
            endProcessing()
            phase = .failed("The saved recording is not playable. Record again.")
            return
        }
        do {
            let generalPipeline = GeneralDictationPipeline(
                transcriber: GroqTranscriber(apiKey: groqKeyDraft),
                temporaryDirectory: recordingStore.temporaryDirectory
            )
            let result = try await generalPipeline.process(
                recordingURL: recording.url,
                durationSeconds: recording.duration
            )
            let transcript = result.transcription.text
            let inserted = await insertTranscript(
                transcript,
                editorText: transcript,
                showDeliveryStep: false
            )
            canRetryLastTranscription = false
            endProcessing()
            phase = inserted ? .delivered : .failed("Voice could not find the focused text editor. Click the editor and try again.")
            contextMessage = inserted
                ? "Dictation inserted at the cursor. Press Send when ready."
                : "No editable cursor was available."
        } catch {
            canRetryLastTranscription = hasLastAudio
            endProcessing()
            phase = .failed(error.localizedDescription)
        }
    }

    private func processLinked(
        recording: RecordedCapture,
        activity: FocusedVoiceActivity,
        startedAt: Date,
        generation: UUID
    ) async {
        do {
            try validateRecording(recording)
        } catch {
            guard generation == captureGeneration else { return }
            canRetryLastTranscription = false
            endProcessing()
            phase = .failed("The saved recording is not playable. Record again.")
            return
        }
        do {
            lastInsertionSucceeded = false
            let builtPipeline = try makeLinkedPipeline()
            pipeline = builtPipeline
            let result = try await builtPipeline.process(
                recordingURL: recording.url,
                durationSeconds: recording.duration,
                activity: activity,
                occurredAt: startedAt,
                transcriptReady: { capture in
                    _ = await self.insertTranscript(
                        capture.transcript,
                        editorText: capture.editorText,
                        showDeliveryStep: true
                    )
                    await self.finishForegroundInsertion()
                },
                progress: { update in
                    await self.applyDeliveryUpdate(update, generation: generation)
                }
            )
            await updateRetryCount()
            guard generation == captureGeneration else { return }
            endProcessing()
            if !lastInsertionSucceeded {
                phase = .failed("The answer was saved, but Voice could not find the focused text editor.")
                contextMessage = "Click the editor, then use Insert again from Last transcript."
            } else {
                phase = result.hasQueuedRetry ? .queued : .delivered
                contextMessage = result.hasQueuedRetry
                    ? "Inserted at the cursor; one background step will retry."
                    : "Inserted at the cursor. Press Send when ready."
            }
        } catch {
            guard generation == captureGeneration else { return }
            canRetryLastTranscription = hasLastAudio
            endProcessing()
            phase = .failed(error.localizedDescription)
        }
    }

    private func updateRetryCount() async {
        guard let recordingStore else { pendingRetryCount = 0; return }
        let queue = VoiceRetryQueue(directory: recordingStore.queueDirectory)
        pendingRetryCount = (try? await queue.items().count) ?? 0
    }

    private func applyDeliveryUpdate(_ update: VoicePipelineUpdate, generation: UUID) {
        guard generation == captureGeneration else { return }
        deliveryStates[update.component] = update.state
        guard !lastInsertionSucceeded else { return }
        phase = update.component == .transcript ? .transcribing : .sending
    }

    private func finishForegroundInsertion() {
        endProcessing()
        if lastInsertionSucceeded {
            phase = .delivered
            contextMessage = "Inserted at the cursor. Press Send when ready."
        }
    }

    func reinsertLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        targetApplicationPID = currentInsertionTargetPID()
        Task {
            let inserted = await insertTranscript(
                lastTranscript,
                editorText: lastInsertionText.isEmpty ? lastTranscript : lastInsertionText,
                showDeliveryStep: linkToInterviewArc
            )
            phase = inserted ? .delivered : .failed("Click an editable text field, then try Insert again.")
        }
    }

    private func insertTranscript(_ transcript: String, editorText: String, showDeliveryStep: Bool) async -> Bool {
        lastTranscript = transcript
        lastInsertionText = editorText
        phase = .inserting
        if showDeliveryStep { deliveryStates[.insertion] = .working }
        let output = await textInjector.deliver(text: editorText, targetPID: targetApplicationPID)
        switch output {
        case .inserted:
            lastInsertionSucceeded = true
            accessibilityNeeded = false
            if showDeliveryStep { deliveryStates[.insertion] = .complete }
            return true
        case .accessibilityRequired:
            lastInsertionSucceeded = false
            accessibilityNeeded = true
            if showDeliveryStep { deliveryStates[.insertion] = .needsAttention }
            return false
        case .noFocusedEditor:
            lastInsertionSucceeded = false
            if showDeliveryStep { deliveryStates[.insertion] = .needsAttention }
            return false
        }
    }

    private func makeLinkedPipeline() throws -> VoicePipeline {
        guard let baseURL = URL(string: apiBaseURL), let recordingStore else {
            throw VoiceBridgeError.recordingUnavailable
        }
        let token = connectionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw VoiceBridgeError.missingCredential("Interview Arc token") }
        return VoicePipeline(
            api: InterviewArcAPIClient(baseURL: baseURL, token: token),
            transcriber: GroqTranscriber(apiKey: groqKeyDraft),
            codex: CodexBridge(executableURL: URL(fileURLWithPath: codexPath)),
            vocabularyResolver: VocabularyResolver(catalog: try .bundled()),
            retryQueue: VoiceRetryQueue(directory: recordingStore.queueDirectory),
            temporaryDirectory: recordingStore.temporaryDirectory,
            workspaceURL: URL(fileURLWithPath: workspacePath, isDirectory: true),
            interviewArcToken: token
        )
    }

    private func settlePhaseAfterContextRefresh(force: Bool) {
        guard force || phase == .setup || phase == .idle || phase == .refreshing else {
            return
        }
        phase = hasGroqCredential ? .idle : .setup
    }

    private func currentInsertionTargetPID() -> pid_t? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApplicationPID = frontmost.processIdentifier
            return frontmost.processIdentifier
        }
        return lastExternalApplicationPID
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

    private func endShortcutCapture() {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        shortcutCapturing = false
    }

    private func rememberLastAudio(_ recording: RecordedCapture) {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingLastAudio = false
        lastAudioData = try? Data(contentsOf: recording.url, options: .mappedIfSafe)
        hasLastAudio = lastAudioData != nil
        lastAudioDuration = recording.duration
        lastMemoCreatedAt = Date()
        lastTranscript = ""
        lastInsertionText = ""
    }

    private func clearLastMemo() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingLastAudio = false
        lastAudioData = nil
        hasLastAudio = false
        lastAudioDuration = 0
        lastTranscript = ""
        lastInsertionText = ""
    }

    private func beginProcessing() {
        processingTimer?.invalidate()
        processingIndicatorTask?.cancel()
        processingElapsedSeconds = 0
        showProcessingIndicator = false
        let startedAt = Date()
        processingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.processingElapsedSeconds = Date().timeIntervalSince(startedAt)
            }
        }
        processingIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isBusy else { return }
                self.showProcessingIndicator = true
            }
        }
    }

    private func endProcessing() {
        processingIndicatorTask?.cancel()
        processingIndicatorTask = nil
        processingTimer?.invalidate()
        processingTimer = nil
        processingElapsedSeconds = 0
        showProcessingIndicator = false
    }

    private func validateRecording(_ recording: RecordedCapture) throws {
        let evidence = try RecordingFileInspector.inspect(recording)
        let recovery = RecordingRecoveryPolicy.action(for: evidence)
        guard recovery == .transcribe else {
            let integrity = RecordingIntegrityEvaluator.evaluate(evidence)
            throw VoiceBridgeError.incompleteRecording(integrity.reasons)
        }
    }

    private func recordingRecoveryAction(
        for recording: RecordedCapture
    ) throws -> RecordingRecoveryAction {
        let evidence = try RecordingFileInspector.inspect(recording)
        return RecordingRecoveryPolicy.action(for: evidence)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func specialtyLabel(_ specialty: PracticeSpecialty) -> String {
        switch specialty {
        case .coding: "Coding"
        case .systemDesign: "System design"
        case .behavioral: "Behavioral"
        }
    }
}

private struct VoiceBridgeMenu: View {
    @ObservedObject var model: VoiceBridgeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader
            modeCard
            recordingControl
            if model.showsDeliverySteps { deliveryProgress }
            if model.hasLastMemo { transcriptPreview }
            if model.pendingRetryCount > 0 { retryRow }
            settings
            providerFooter
        }
        .padding(12)
        .frame(width: 260)
    }

    private var statusHeader: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(statusColor.opacity(0.14))
                Image(systemName: model.phase.symbol).foregroundStyle(statusColor)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.phase.label).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(model.linkToInterviewArc ? "Interview Arc" : "General dictation")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: model.toggleFloatingPanel) { Image(systemName: "macwindow.on.rectangle") }
                .buttonStyle(.borderless)
                .frame(width: 26, height: 26)
                .voiceHoverFeedback(cornerRadius: 7)
                .accessibilityLabel("Show or hide floating recorder")
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .frame(width: 26, height: 26)
                .voiceHoverFeedback(enabled: !model.isRecording && !model.isBusy, cornerRadius: 7)
                .disabled(model.isRecording || model.isBusy)
                .accessibilityLabel("Refresh focused activity")
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(
                "Link to Interview Arc",
                isOn: Binding(
                    get: { model.linkToInterviewArc },
                    set: { enabled in model.setLinkMode(enabled) }
                )
            )
            .toggleStyle(.switch)
            .voiceHoverFeedback(enabled: !model.isRecording, cornerRadius: 8)
            .disabled(model.isRecording)
            HStack(alignment: .center, spacing: 7) {
                LinkStatusIcon(
                    isLinked: model.linkToInterviewArc,
                    symbol: model.linkStatusSymbol,
                    color: model.linkStatusColor,
                    size: 14
                )
                Text(model.linkToInterviewArc && model.context?.focusedActivity != nil
                     ? model.floatingTitle
                     : "Inserts at the cursor")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var recordingControl: some View {
        Button(action: model.toggleRecording) {
            HStack(spacing: 7) {
                if model.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                }
                Text(
                    model.isBusy
                        ? model.processingStatus
                        : (model.isRecording ? "Stop" : "Record")
                )
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                if model.isRecording {
                    Spacer()
                    RecordingClock(recorder: model.recorder, compact: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(model.isRecording ? .red : Color(red: 0.08, green: 0.34, blue: 0.22))
        .voiceHoverFeedback(
            enabled: model.isRecording || model.canRecord,
            cornerRadius: 10,
            tint: model.isRecording ? .red : .teal
        )
        .disabled(!model.isRecording && !model.canRecord)
    }

    private var deliveryProgress: some View {
        HStack(spacing: 4) {
            ForEach(VoiceDeliveryComponent.allCases, id: \.self) { component in
                DeliveryMenuStep(component: component, state: model.deliveryStates[component])
            }
        }
        .padding(7)
        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var transcriptPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LAST TRANSCRIPT").font(.caption2.weight(.bold)).tracking(0.8).foregroundStyle(.secondary)
                Spacer()
                memoAction(
                    symbol: "doc.on.doc",
                    label: "Copy transcript",
                    disabled: model.lastTranscript.isEmpty,
                    action: model.copyLastTranscript
                )
                memoAction(
                    symbol: model.isPlayingLastAudio ? "pause.fill" : "play.fill",
                    label: model.isPlayingLastAudio ? "Pause recording" : "Play recording",
                    disabled: !model.hasLastAudio,
                    action: model.toggleLastAudioPlayback
                )
                memoAction(
                    symbol: "square.and.arrow.down",
                    label: "Save audio and transcript",
                    disabled: !model.hasLastMemo,
                    action: model.exportLastMemo
                )
                memoAction(
                    symbol: "text.cursor",
                    label: "Insert transcript again",
                    disabled: model.lastTranscript.isEmpty,
                    action: model.reinsertLastTranscript
                )
            }
            if !model.lastTranscript.isEmpty {
                ScrollView {
                    Text(model.lastTranscript)
                        .font(.caption)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 4)
                }
                .frame(maxHeight: 118)
            } else {
                Text("The recording is safe in memory. Retry transcription when ready.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(model.lastMemoDetails)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if model.canRetryLastTranscription {
                    Button(action: model.retryLastTranscription) {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(.semibold))
                    .voiceHoverFeedback(enabled: !model.isBusy && !model.isRecording, cornerRadius: 6)
                    .disabled(model.isBusy || model.isRecording)
                }
            }
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func memoAction(
        symbol: String,
        label: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.borderless)
        .voiceHoverFeedback(enabled: !disabled, cornerRadius: 6)
        .disabled(disabled)
        .accessibilityLabel(label)
        .help(label)
    }

    private var retryRow: some View {
        HStack {
            Label("\(model.pendingRetryCount) background retry\(model.pendingRetryCount == 1 ? "" : "ies")", systemImage: "clock.arrow.circlepath")
                .font(.caption)
            Spacer()
            Button("Retry now", action: model.retryPending)
                .voiceHoverFeedback(enabled: !model.isBusy && !model.isRecording, cornerRadius: 6)
                .disabled(model.isBusy || model.isRecording)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
    }

    private var settings: some View {
        DisclosureGroup(isExpanded: $model.settingsExpanded) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Global shortcut")
                    Spacer()
                    Button(model.shortcutCapturing ? "Press shortcut…" : model.shortcut.displayName) {
                        model.beginShortcutCapture()
                    }
                    .voiceHoverFeedback(cornerRadius: 6)
                }
                if model.accessibilityNeeded {
                    Button("Enable Accessibility for insertion", action: model.requestAccessibilityPermission)
                        .font(.caption)
                        .voiceHoverFeedback(cornerRadius: 6)
                } else {
                    Label("Direct insertion enabled", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Divider()
                SecureField("Interview Arc token", text: $model.connectionTokenDraft).textFieldStyle(.roundedBorder)
                SecureField("Groq API key", text: $model.groqKeyDraft).textFieldStyle(.roundedBorder)
                TextField("Interview Arc API", text: $model.apiBaseURL).textFieldStyle(.roundedBorder)
                TextField("Interview Arc repository", text: $model.workspacePath).textFieldStyle(.roundedBorder)
                TextField("Codex executable", text: $model.codexPath).textFieldStyle(.roundedBorder)
                Button("Save secure settings", action: model.saveSettings)
                    .buttonStyle(.borderedProminent)
                    .voiceHoverFeedback(cornerRadius: 7)
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Label("Settings", systemImage: "gearshape")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(model.shortcut.displayName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .voiceHoverFeedback(cornerRadius: 7)
        }
    }

    private var providerFooter: some View {
        HStack {
            Label("Groq Large v3", systemImage: "cloud")
            Spacer()
            Label("Private", systemImage: "lock.fill")
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
}

private struct DeliveryMenuStep: View {
    let component: VoiceDeliveryComponent
    let state: VoiceDeliveryComponentState?

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(label).font(.caption2)
        }
        .frame(maxWidth: .infinity)
    }

    private var label: String {
        switch component {
        case .insertion: "Cursor"
        case .transcript: "Saved"
        case .audio: "R2"
        case .coach: "Coach"
        }
    }

    private var symbol: String {
        switch state {
        case .working: "arrow.triangle.2.circlepath"
        case .complete: "checkmark.circle.fill"
        case .queued: "clock.badge.exclamationmark"
        case .needsAttention: "exclamationmark.circle.fill"
        case nil: "circle"
        }
    }

    private var color: Color {
        switch state {
        case .working: .blue
        case .complete: .green
        case .queued: .orange
        case .needsAttention: .red
        case nil: .secondary
        }
    }
}

struct RecordingClock: View {
    @ObservedObject var recorder: AnswerRecorder
    var compact = false

    var body: some View {
        Text(clock(recorder.elapsedSeconds))
            .font(.system(size: compact ? 10 : 14, weight: .semibold, design: .monospaced))
            .frame(minWidth: compact ? 32 : 58)
            .accessibilityLabel("Recording time \(clock(recorder.elapsedSeconds))")
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
