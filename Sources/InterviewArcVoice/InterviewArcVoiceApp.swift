import AppKit
import Carbon
import SwiftUI
import InterviewArcVoiceCore

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
        case pasting
        case delivered
        case copied
        case queued
        case failed(String)

        var label: String {
            switch self {
            case .setup: "Add your Groq key"
            case .refreshing: "Checking current activity"
            case .idle: "Ready"
            case .recording: "Recording"
            case .transcribing: "Transcribing with Groq"
            case .sending: "Syncing interview answer"
            case .pasting: "Pasting dictation"
            case .delivered: "Complete"
            case .copied: "Copied to clipboard"
            case .queued: "Complete with retry queued"
            case .failed: "Needs attention"
            }
        }

        var symbol: String {
            switch self {
            case .recording: "waveform.circle.fill"
            case .transcribing, .sending, .refreshing, .pasting: "arrow.triangle.2.circlepath"
            case .delivered: "checkmark.circle.fill"
            case .copied: "doc.on.clipboard.fill"
            case .queued: "clock.arrow.circlepath"
            case .failed: "exclamationmark.triangle.fill"
            case .setup: "key.fill"
            case .idle: "mic.circle"
            }
        }
    }

    private enum CaptureDestination {
        case linked(FocusedVoiceActivity, SpecialistRoute)
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
    @Published var autoPaste: Bool
    @Published var shortcut: HotKeyShortcut
    @Published var shortcutCapturing = false
    @Published var accessibilityNeeded = false
    @Published var deliveryStates: [VoiceDeliveryComponent: VoiceDeliveryComponentState] = [:]

    let recorder = AnswerRecorder()

    private let keychain = KeychainStore()
    private let routingPolicy = CaptureRoutingPolicy()
    private let hotKeyManager = GlobalHotKeyManager()
    private let textInjector = DictationTextInjector()
    private var recordingStore: RecordingStore?
    private var pipeline: VoicePipeline?
    private var captureDestination: CaptureDestination?
    private var targetApplicationPID: pid_t?
    private var shortcutMonitor: Any?

    var isRecording: Bool { phase == .recording }
    var isBusy: Bool { [.refreshing, .transcribing, .sending, .pasting].contains(phase) }
    var canRecord: Bool {
        !groqKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }
    var menuBarSymbol: String {
        switch phase {
        case .recording: "waveform.circle.fill"
        case .transcribing, .sending, .pasting: "arrow.triangle.2.circlepath.circle.fill"
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

    init() {
        let defaults = UserDefaults.standard
        apiBaseURL = defaults.string(forKey: "voice.apiBaseURL") ?? "https://limitless-mcp.vinosama.workers.dev"
        workspacePath = defaults.string(forKey: "voice.workspacePath") ?? "/Users/wenkxu/Projects/Interview Prep/interview-arc"
        codexPath = defaults.string(forKey: "voice.codexPath") ?? "/Applications/ChatGPT.app/Contents/Resources/codex"
        linkToInterviewArc = defaults.object(forKey: "voice.linkToInterviewArc") as? Bool ?? true
        autoPaste = defaults.object(forKey: "voice.autoPaste") as? Bool ?? true
        if let data = defaults.data(forKey: "voice.shortcut"),
           let saved = try? JSONDecoder().decode(HotKeyShortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .standard
        }
        recordingStore = try? RecordingStore()

        // Present visible UI before touching Keychain. A credential prompt or
        // error must never make this agent-style app appear to launch and quit.
        Task {
            await Task.yield()
            FloatingPanelController.shared.show(model: self)
            hotKeyManager.register(shortcut) { [weak self] in self?.toggleRecording() }
            await loadSecureSettings()
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

    func toggleLinkMode() {
        setLinkMode(!linkToInterviewArc)
    }

    func setLinkMode(_ enabled: Bool) {
        guard !isRecording, !isBusy else { return }
        linkToInterviewArc = enabled
        UserDefaults.standard.set(enabled, forKey: "voice.linkToInterviewArc")
        deliveryStates = [:]
        if enabled {
            contextMessage = "Auto-link will check the current activity before recording."
            Task { await refreshContext(showProgress: false) }
        } else {
            contextMessage = "General dictation will not touch Interview Arc."
            phase = canRecord ? .idle : .setup
        }
    }

    func saveSettings() {
        do {
            try keychain.set(connectionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines), for: .interviewArcToken)
            try keychain.set(groqKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines), for: .groqAPIKey)
            UserDefaults.standard.set(apiBaseURL, forKey: "voice.apiBaseURL")
            UserDefaults.standard.set(workspacePath, forKey: "voice.workspacePath")
            UserDefaults.standard.set(codexPath, forKey: "voice.codexPath")
            UserDefaults.standard.set(autoPaste, forKey: "voice.autoPaste")
            settingsExpanded = false
            Task { await refreshContext(showProgress: false) }
        } catch {
            phase = .failed("Secure settings could not be saved: \(error.localizedDescription)")
        }
    }

    func setAutoPaste(_ enabled: Bool) {
        autoPaste = enabled
        UserDefaults.standard.set(enabled, forKey: "voice.autoPaste")
        accessibilityNeeded = enabled && !textInjector.accessibilityTrusted
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
        do {
            connectionTokenDraft = try keychain.value(for: .interviewArcToken) ?? ""
            groqKeyDraft = try keychain.value(for: .groqAPIKey) ?? ""
        } catch {
            contextMessage = "Keychain access failed. Open Connection settings to enter the keys again."
        }
        accessibilityNeeded = autoPaste && !textInjector.accessibilityTrusted
        phase = canRecord ? .idle : .setup
        await refreshContext(showProgress: false)
    }

    private func refreshContext(showProgress: Bool) async {
        guard linkToInterviewArc else {
            contextMessage = "General dictation will not touch Interview Arc."
            phase = canRecord ? .idle : .setup
            return
        }
        let token = connectionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            context = nil
            contextMessage = "No Interview Arc token — general dictation is still available."
            phase = canRecord ? .idle : .setup
            return
        }
        guard let baseURL = URL(string: apiBaseURL) else {
            context = nil
            contextMessage = "Interview Arc API address is invalid — using general dictation."
            phase = canRecord ? .idle : .setup
            return
        }
        if showProgress { phase = .refreshing }
        do {
            let loaded = try await InterviewArcAPIClient(baseURL: baseURL, token: token).context()
            context = loaded
            if let activity = loaded.focusedActivity, loaded.specialist != nil {
                contextMessage = "Linked to \(activity.title)"
            } else if loaded.focusedActivity != nil {
                contextMessage = "The focused activity has no specialist — using general dictation."
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
        phase = canRecord ? .idle : .setup
    }

    private func prepareAndStartRecording() async {
        guard canRecord else {
            phase = .setup
            contextMessage = "Add your Groq API key in Connection settings."
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        targetApplicationPID = frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : frontmost?.processIdentifier
        deliveryStates = [:]

        if linkToInterviewArc { await refreshContext(showProgress: true) }
        let route = routingPolicy.route(
            linkToInterviewArc: linkToInterviewArc,
            hasFocusedActivity: context?.focusedActivity != nil,
            hasSpecialist: context?.specialist != nil
        )
        switch route {
        case .linked:
            guard let activity = context?.focusedActivity, let specialist = context?.specialist else { return }
            captureDestination = .linked(activity, specialist)
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
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func stopAndProcess() {
        guard let captureDestination else {
            phase = .failed("The recording destination was lost. Record again.")
            return
        }
        do {
            let recording = try recorder.stop()
            phase = .transcribing
            Task {
                switch captureDestination {
                case .linked(let activity, let specialist):
                    await processLinked(recording: recording, activity: activity, specialist: specialist)
                case .general:
                    await processGeneral(recording: recording)
                }
                self.captureDestination = nil
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func processGeneral(recording: (url: URL, duration: TimeInterval)) async {
        guard let recordingStore else {
            phase = .failed("Voice settings are incomplete.")
            return
        }
        do {
            let generalPipeline = GeneralDictationPipeline(
                transcriber: GroqTranscriber(apiKey: groqKeyDraft),
                temporaryDirectory: recordingStore.temporaryDirectory
            )
            let result = try await generalPipeline.process(recordingURL: recording.url)
            lastTranscript = result.text
            phase = .pasting
            let output = await textInjector.deliver(
                text: result.text,
                targetPID: targetApplicationPID,
                autoPaste: autoPaste
            )
            accessibilityNeeded = autoPaste && output == .copied
            phase = output == .pasted ? .delivered : .copied
            contextMessage = output == .pasted
                ? "Dictation pasted into the active app."
                : "Dictation copied. Enable Accessibility to paste automatically."
        } catch {
            try? FileManager.default.removeItem(at: recording.url)
            phase = .failed(error.localizedDescription)
        }
    }

    private func processLinked(
        recording: (url: URL, duration: TimeInterval),
        activity: FocusedVoiceActivity,
        specialist: SpecialistRoute
    ) async {
        do {
            let builtPipeline = try makeLinkedPipeline()
            pipeline = builtPipeline
            let result = try await builtPipeline.process(
                recordingURL: recording.url,
                durationSeconds: recording.duration,
                activity: activity,
                specialist: specialist,
                progress: { update in
                    await self.applyDeliveryUpdate(update)
                }
            )
            lastTranscript = result.transcript
            await updateRetryCount()
            phase = result.hasQueuedRetry ? .queued : .delivered
            contextMessage = result.hasQueuedRetry
                ? "The answer is safe; one background step will retry."
                : "Transcript, specialist, audio, and coach are connected."
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func updateRetryCount() async {
        guard let recordingStore else { pendingRetryCount = 0; return }
        let queue = VoiceRetryQueue(directory: recordingStore.queueDirectory)
        pendingRetryCount = (try? await queue.items().count) ?? 0
    }

    private func applyDeliveryUpdate(_ update: VoicePipelineUpdate) {
        deliveryStates[update.component] = update.state
        phase = update.component == .transcript ? .transcribing : .sending
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
        VStack(alignment: .leading, spacing: 15) {
            statusHeader
            modeCard
            recordingControl
            if model.showsDeliverySteps { deliveryProgress }
            if !model.lastTranscript.isEmpty { transcriptPreview }
            if model.pendingRetryCount > 0 { retryRow }
            settings
            providerFooter
        }
        .padding(18)
        .frame(width: 390)
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
                Text(model.compactStatus).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer()
            Button(action: model.toggleFloatingPanel) { Image(systemName: "macwindow.on.rectangle") }
                .buttonStyle(.borderless)
                .frame(width: 34, height: 34)
                .accessibilityLabel("Show or hide floating recorder")
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .frame(width: 34, height: 34)
                .disabled(model.isRecording || model.isBusy)
                .accessibilityLabel("Refresh focused activity")
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "Link to Interview Arc",
                isOn: Binding(
                    get: { model.linkToInterviewArc },
                    set: { enabled in model.setLinkMode(enabled) }
                )
            )
            .toggleStyle(.switch)
            .disabled(model.isRecording || model.isBusy)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: model.linkToInterviewArc && model.context?.focusedActivity != nil ? "link.circle.fill" : "text.cursor")
                    .foregroundStyle(model.linkToInterviewArc && model.context?.focusedActivity != nil ? .teal : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.floatingTitle).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(model.contextMessage).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
            }
        }
        .padding(13)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var recordingControl: some View {
        HStack(spacing: 10) {
            Button(action: model.toggleRecording) {
                Label(model.isRecording ? "Stop" : "Record", systemImage: model.isRecording ? "stop.fill" : "mic.fill")
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(model.isRecording ? .red : Color(red: 0.08, green: 0.34, blue: 0.22))
            .disabled(!model.isRecording && !model.canRecord)
            if model.isRecording { RecordingClock(recorder: model.recorder) }
            Text(model.shortcut.displayName).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }

    private var deliveryProgress: some View {
        HStack(spacing: 8) {
            ForEach(VoiceDeliveryComponent.allCases, id: \.self) { component in
                DeliveryMenuStep(component: component, state: model.deliveryStates[component])
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var transcriptPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LAST VERBATIM TRANSCRIPT").font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
            Text(model.lastTranscript).font(.caption).lineLimit(4).textSelection(.enabled)
        }
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
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Text("Global shortcut")
                    Spacer()
                    Button(model.shortcutCapturing ? "Press shortcut…" : model.shortcut.displayName) {
                        model.beginShortcutCapture()
                    }
                }
                Toggle(
                    "Paste general dictation automatically",
                    isOn: Binding(
                        get: { model.autoPaste },
                        set: { enabled in model.setAutoPaste(enabled) }
                    )
                )
                if model.accessibilityNeeded {
                    Button("Enable Accessibility for auto-paste", action: model.requestAccessibilityPermission)
                        .font(.caption)
                }
                Divider()
                SecureField("Interview Arc token", text: $model.connectionTokenDraft).textFieldStyle(.roundedBorder)
                SecureField("Groq API key", text: $model.groqKeyDraft).textFieldStyle(.roundedBorder)
                TextField("Interview Arc API", text: $model.apiBaseURL).textFieldStyle(.roundedBorder)
                TextField("Interview Arc repository", text: $model.workspacePath).textFieldStyle(.roundedBorder)
                TextField("Codex executable", text: $model.codexPath).textFieldStyle(.roundedBorder)
                Button("Save secure settings", action: model.saveSettings).buttonStyle(.borderedProminent)
            }
            .padding(.top, 10)
        } label: {
            Label("Settings", systemImage: "gearshape")
                .font(.subheadline.weight(.medium))
        }
    }

    private var providerFooter: some View {
        HStack {
            Label("Groq Large v3", systemImage: "cloud")
            Spacer()
            Label(model.linkToInterviewArc ? "Auto-link" : "General", systemImage: model.linkToInterviewArc ? "link" : "text.cursor")
            Spacer()
            Label("Private", systemImage: "lock.fill")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var statusColor: Color {
        switch model.phase {
        case .recording, .failed: .red
        case .queued, .setup, .copied: .orange
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
        case .transcript: "Text"
        case .specialist: "Codex"
        case .audio: "R2"
        case .coach: "Coach"
        }
    }

    private var symbol: String {
        switch state {
        case .working: "arrow.triangle.2.circlepath"
        case .complete: "checkmark.circle.fill"
        case .queued: "clock.badge.exclamationmark"
        case nil: "circle"
        }
    }

    private var color: Color {
        switch state {
        case .working: .blue
        case .complete: .green
        case .queued: .orange
        case nil: .secondary
        }
    }
}

struct RecordingClock: View {
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
