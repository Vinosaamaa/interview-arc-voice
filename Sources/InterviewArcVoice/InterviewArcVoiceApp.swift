import AppKit
import AVFoundation
import Carbon
import os
import SwiftUI
import UniformTypeIdentifiers
import InterviewArcVoiceCore

private let voiceBridgeLogger = Logger(
    subsystem: "app.interviewarc.voice",
    category: "VoiceBridge"
)

private struct SecureCredentialSnapshot: Sendable {
    let interviewArcToken: String
    let groqAPIKey: String
    let errorDescription: String?
}

enum VoiceLinkPresentationState: Equatable {
    case off
    case waiting
    case linked
}

@main
struct InterviewArcVoiceApp: App {
    @StateObject private var model: VoiceBridgeModel
    @Environment(\.openSettings) private var openSettings

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
        if ProcessInfo.processInfo.arguments.contains("--credential-status") {
            let keychain = KeychainStore()
            do {
                let groqKey = try keychain.value(for: .groqAPIKey) ?? ""
                let interviewArcToken = try keychain.value(for: .interviewArcToken) ?? ""
                print("groq-api-key: \(groqKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "missing" : "saved")")
                print("interview-arc-token: \(interviewArcToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "missing" : "saved")")
                exit(EXIT_SUCCESS)
            } catch {
                fputs("Interview Arc Voice could not read secure settings: \(error.localizedDescription)\n", stderr)
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
                .accessibilityLabel(
                    model.isStartingRecording
                        ? "Interview Arc Voice preparing microphone"
                        : (model.isRecording ? "Interview Arc Voice recording" : "Interview Arc Voice")
                )
        }
        .menuBarExtraStyle(.window)

        Settings {
            VoiceSettingsWindow(model: model)
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsWindowPresenter.present {
                        openSettings()
                    }
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class VoiceBridgeModel: ObservableObject {
    enum Phase: Equatable {
        case setup
        case refreshing
        case idle
        case preparingMicrophone
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
            case .preparingMicrophone: "Preparing microphone"
            case .recording: "Recording"
            case .transcribing: "Transcribing with Groq"
            case .sending: "Saving interview answer"
            case .inserting: "Inserting at the cursor"
            case .delivered: "Complete"
            case .queued: "Complete with retry queued"
            case .failed(let message): message
            }
        }

        var symbol: String {
            switch self {
            case .recording: "waveform.circle.fill"
            case .preparingMicrophone: "mic.badge.plus"
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
        case general(startedAt: Date)
    }

    private enum FailureStage {
        case microphone
        case recording
        case transcription
        case insertion
        case interviewArc
        case configuration
        case playback
        case export
    }

    private struct CaptureDiagnosticSeed {
        let id: UUID
        let startedAt: Date
        let recordingDurationSeconds: Double
        let fileFinalizationSeconds: Double
        let integrityInspectionSeconds: Double
        let localSpeechScanSeconds: Double
        let protectionMode: SpeechProtectionMode
    }

    @Published var phase: Phase = .setup
    @Published var context: VoiceContextResponse?
    @Published private(set) var timerInstrument: VoiceTimerInstrument?
    @Published private(set) var timerMutationInFlight = false
    @Published private(set) var timerMutationMessage: String?
    @Published var timerPanelExpanded = false
    @Published var activityPickerExpanded = false
    @Published private(set) var finishingActivityID: String?
    @Published var sessionFinishResolutionRequested = false
    @Published var finishOutcome: VoicePracticeOutcome?
    @Published var finishStarred = false
    @Published var contextMessage = "Loading secure settings…"
    @Published var lastTranscript = ""
    @Published var connectionTokenDraft = ""
    @Published var groqKeyDraft = ""
    @Published var settingsExpanded = false
    @Published var workspacePath: String
    @Published var apiBaseURL: String
    @Published var codexPath: String
    @Published var pendingRetryCount = 0
    @Published private(set) var pendingVoiceCaptures: [PendingVoiceCapture] = []
    @Published private(set) var legacyVoiceOrphans: [LegacyVoiceCapture] = []
    @Published var linkToInterviewArc: Bool
    @Published var widgetTheme: VoiceWidgetTheme
    @Published var backgroundAudioMode: BackgroundAudioRecordingMode
    @Published var backgroundAudioRelativeLevel: Double
    @Published var dynamicRecordingInterfaceEnabled: Bool
    @Published var speechProtectionMode: SpeechProtectionMode
    @Published private(set) var diagnosticRecords: [VoiceDiagnosticRecord] = []
    @Published private(set) var dynamicRecordingInterfaceActive = false
    @Published var shortcut: HotKeyShortcut
    @Published var shortcutCapturing = false
    @Published var linkShortcut: HotKeyShortcut
    @Published var linkShortcutCapturing = false
    @Published var shortcutMessage: String?
    @Published var accessibilityNeeded = false
    @Published var deliveryStates: [VoiceDeliveryComponent: VoiceDeliveryComponentState] = [:]
    @Published private(set) var hasLastAudio = false
    @Published private(set) var isPlayingLastAudio = false
    @Published private(set) var isPlaybackExpanded = false
    @Published private(set) var playbackCurrentTime: TimeInterval = 0
    @Published private(set) var playbackDuration: TimeInterval = 0
    @Published private(set) var canRetryLastTranscription = false
    @Published private(set) var processingElapsedSeconds: TimeInterval = 0
    @Published private(set) var showProcessingIndicator = false
    @Published private(set) var failureNotice: VoiceFailureNotice?
    @Published var failureDetailsPresented = false
    private var pendingFailurePopoverActionTask: Task<Void, Never>?
    private var pendingFailurePopoverCloseObserver: NSObjectProtocol?
    private var pendingRetryInFlight = false
    private lazy var generalDictationPrompt: String = {
        (try? VocabularyCatalog.bundled().generalDictationPrompt()) ?? "LeetCode"
    }()

    let recorder = AnswerRecorder()

    private let keychain = KeychainStore()
    private let routingPolicy = CaptureRoutingPolicy()
    private let contextRetentionPolicy = VoiceContextRetentionPolicy()
    private let contextFreshnessPolicy = CaptureContextFreshnessPolicy()
    private let lateBindingPolicy = LateCaptureBindingPolicy()
    private let playbackCompletionPolicy = PlaybackCompletionPolicy()
    private let compactPresentationPolicy = CompactVoicePresentationPolicy()
    private let hotKeyManager = GlobalHotKeyManager(identifierID: 1)
    private let linkHotKeyManager = GlobalHotKeyManager(identifierID: 2)
    private let textInjector = DictationTextInjector()
    private let outputVolumeController = SystemOutputVolumeController()
    private var recordingStore: RecordingStore?
    private var diagnosticsStore: VoiceDiagnosticsStore?
    private var pipeline: VoicePipeline?
    private var captureDestination: CaptureDestination?
    private var captureStartedInCodex = false
    private var captureGeneration = UUID()
    private var targetApplicationPID: pid_t?
    private var lastInsertionText = ""
    private var shortcutMonitor: Any?
    private var linkShortcutMonitor: Any?
    private var lastInsertionSucceeded = false
    private var contextPollTask: Task<Void, Never>?
    private var pendingReconciliationTask: Task<Void, Never>?
    private var pendingReconciliationGeneration = UUID()
    private var lastLiveRevision = 0
    private var contextRefreshRequestID = 0
    private var contextLastVerifiedAt: Date?
    private var timerInstrumentReceivedAt = Date()
    private var wakeObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var lastExternalApplicationPID: pid_t?
    private var lastAudioData: Data?
    private var lastAudioURL: URL?
    private var lastAudioDuration: TimeInterval = 0
    private var lastMemoCreatedAt = Date()
    private var lastMemoActivityTitle: String?
    private var lastRetryDestination: CaptureDestination?
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?
    private var processingTimer: Timer?
    private var processingIndicatorTask: Task<Void, Never>?
    private var disclosureStateBeforeRecording: FloatingWidgetDisclosureState?
    private var recordingStartupTask: Task<Void, Never>?
    private var currentInsertionDurationSeconds: Double = 0
    @Published private(set) var isStartingRecording = false

    var isRecording: Bool { recorder.isRecording }
    var isBusy: Bool {
        [.refreshing, .preparingMicrophone, .transcribing, .sending, .inserting].contains(phase)
    }
    var shouldCenterFloatingTitle: Bool {
        !linkToInterviewArc
            && !hasTimerInstrument
            && !hasLastAudio
            && lastTranscript.isEmpty
    }
    var hasGroqCredential: Bool {
        !groqKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var configurationIsReady: Bool {
        hasGroqCredential
    }
    var canRecord: Bool {
        hasGroqCredential && !isBusy && !isStartingRecording
    }
    var menuBarSymbol: String {
        switch phase {
        case .preparingMicrophone: "mic.badge.plus"
        case .recording: "waveform.circle.fill"
        case .transcribing, .sending, .inserting: "arrow.triangle.2.circlepath.circle.fill"
        case .queued: "clock.badge.exclamationmark.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "waveform.circle"
        }
    }
    var floatingEyebrow: String {
        switch compactLinkPresentation.state {
        case .off:
            return "GENERAL DICTATION"
        case .waiting:
            return "AUTO-LINK ON · GENERAL FALLBACK"
        case .connectedIdle:
            return "CONNECTED · GENERAL DICTATION"
        case .linked:
            guard let activity = context?.focusedActivity else { return "LINKED" }
            return specialtyLabel(activity.specialty).uppercased() + " · LINKED"
        }
    }
    var floatingTitle: String {
        compactLinkPresentation.title
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
    var playbackProgress: Double {
        guard playbackDuration > 0 else { return 0 }
        return min(1, max(0, playbackCurrentTime / playbackDuration))
    }
    var playbackTimeLabel: String {
        "\(clock(playbackCurrentTime)) / \(clock(playbackDuration))"
    }
    var statusTitle: String {
        failureNotice?.title ?? phase.label
    }
    var statusSummary: String {
        if let failureNotice { return failureNotice.message }
        if !contextMessage.isEmpty { return contextMessage }
        return linkToInterviewArc ? "Interview Arc" : "General dictation"
    }
    var processingStatus: String {
        "\(phase.label) · \(clock(processingElapsedSeconds))"
    }
    var linkPresentationState: VoiceLinkPresentationState {
        switch compactLinkPresentation.state {
        case .off:
            return .off
        case .waiting, .connectedIdle:
            return .waiting
        case .linked:
            return .linked
        }
    }
    var linkStatusColor: Color {
        let palette = widgetPalette
        switch compactLinkPresentation.state {
        case .off:
            return palette.linkOff
        case .waiting:
            return palette.teal.opacity(0.82)
        case .connectedIdle:
            return palette.connectedIdle
        case .linked:
            return palette.teal
        }
    }
    var widgetPalette: VoiceWidgetPalette {
        .palette(for: widgetTheme)
    }
    var linkStatusAccessibilityLabel: String {
        compactLinkPresentation.accessibilityLabel
    }
    var isFailurePresented: Bool {
        if case .failed = phase { return failureNotice != nil }
        return false
    }
    var floatingWidth: CGFloat {
        if dynamicRecordingInterfaceActive {
            return FloatingWidgetWindowPolicy.recordingWidth
        }
        if timerPanelExpanded && hasTimerInstrument {
            return FloatingWidgetWindowPolicy.expandedWidth
        }
        return isPlaybackExpanded
            ? FloatingWidgetWindowPolicy.playbackWidth
            : FloatingWidgetWindowPolicy.collapsedWidth
    }
    var floatingSize: CGSize {
        CGSize(width: floatingWidth, height: floatingHeight)
    }
    var floatingHeight: CGFloat {
        if dynamicRecordingInterfaceActive {
            return FloatingWidgetWindowPolicy.hostHeight
        }
        guard timerPanelExpanded && hasTimerInstrument else {
            return FloatingWidgetWindowPolicy.hostHeight
        }
        return finishingActivityID == nil
            && !activityPickerExpanded
            && !sessionFinishResolutionRequested
            ? FloatingWidgetWindowPolicy.expandedHostHeight
            : FloatingWidgetWindowPolicy.expandedDrawerHostHeight
    }
    var hasTimerInstrument: Bool {
        linkToInterviewArc
            && (timerInstrument?.session != nil || timerInstrument?.activity != nil)
    }
    var isFinishDrawerPresented: Bool {
        finishingActivityID != nil
    }
    var finishingActivity: VoiceTimerActivity? {
        guard let finishingActivityID else { return nil }
        return timerInstrument?.activities.first { $0.id == finishingActivityID }
    }
    var availableTimerActivities: [VoiceTimerActivity] {
        timerInstrument?.activities ?? []
    }
    var sessionFinishBlockers: [VoiceTimerActivity] {
        guard sessionFinishResolutionRequested else { return [] }
        return timerInstrument?.sessionFinishBlockers ?? []
    }
    var compactTimerTitle: String {
        timerInstrument?.activity?.title
            ?? timerInstrument?.session?.label
            ?? floatingTitle
    }

    func compactActivityTime(at now: Date) -> String? {
        guard let timer = timerInstrument?.activity?.timer else { return nil }
        return compactClock(elapsedSeconds(for: timer, now: now))
    }

    func compactSessionTime(at now: Date) -> String? {
        guard let session = timerInstrument?.session else { return nil }
        let elapsed = elapsedSeconds(for: session.timer, now: now)
        let remaining = session.allocatedSeconds - elapsed
        return remaining >= 0
            ? compactClock(remaining)
            : "+\(compactClock(abs(remaining)))"
    }
    private var compactLinkPresentation: CompactVoicePresentation {
        compactPresentationPolicy.presentation(
            linkEnabled: linkToInterviewArc,
            activeActivityTitle: context?.focusedActivity?.title,
            hasOpenSession: timerInstrument?.session != nil,
            sessionIsRunning: timerInstrument?.session?.timer.isRunning == true
        )
    }

    private func compactClock(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        if safe >= 3_600 {
            return String(
                format: "%02d:%02d:%02d",
                safe / 3_600,
                (safe % 3_600) / 60,
                safe % 60
            )
        }
        return String(format: "%02d:%02d", safe / 60, safe % 60)
    }

    init() {
        let defaults = UserDefaults.standard
        apiBaseURL = defaults.string(forKey: "voice.apiBaseURL") ?? "https://limitless-mcp.vinosama.workers.dev"
        workspacePath = defaults.string(forKey: "voice.workspacePath") ?? "/Users/wenkxu/Projects/Interview Prep/interview-arc"
        codexPath = defaults.string(forKey: "voice.codexPath") ?? "/Applications/ChatGPT.app/Contents/Resources/codex"
        linkToInterviewArc = defaults.object(forKey: "voice.linkToInterviewArc") as? Bool ?? true
        widgetTheme = VoiceWidgetTheme.load(from: defaults)
        backgroundAudioMode = BackgroundAudioRecordingMode(
            rawValue: defaults.string(forKey: "voice.backgroundAudioMode") ?? ""
        ) ?? .lower
        backgroundAudioRelativeLevel = defaults.object(
            forKey: "voice.backgroundAudioRelativeLevel"
        ) as? Double ?? BackgroundAudioPolicy.defaultRelativeLevel
        dynamicRecordingInterfaceEnabled = defaults.object(
            forKey: "voice.dynamicRecordingInterfaceEnabled"
        ) as? Bool ?? false
        speechProtectionMode = SpeechProtectionMode.load(from: defaults)
        let resolvedShortcut: HotKeyShortcut
        if let data = defaults.data(forKey: "voice.shortcut"),
           let saved = try? JSONDecoder().decode(HotKeyShortcut.self, from: data) {
            resolvedShortcut = saved
        } else {
            resolvedShortcut = .standard
        }
        shortcut = resolvedShortcut
        let resolvedLinkShortcut: HotKeyShortcut
        if let data = defaults.data(forKey: "voice.linkShortcut"),
           let saved = try? JSONDecoder().decode(HotKeyShortcut.self, from: data) {
            resolvedLinkShortcut = saved == resolvedShortcut ? .linkToggle : saved
        } else {
            resolvedLinkShortcut = .linkToggle
        }
        linkShortcut = resolvedLinkShortcut
        if resolvedLinkShortcut == .linkToggle,
           let data = try? JSONEncoder().encode(resolvedLinkShortcut) {
            defaults.set(data, forKey: "voice.linkShortcut")
        }
        if let data = defaults.data(forKey: "voice.lastFailure"),
           let storedFailure = try? JSONDecoder().decode(VoiceFailureNotice.self, from: data) {
            failureNotice = storedFailure
        }
        recordingStore = try? RecordingStore()
        if let recordingStore {
            diagnosticsStore = try? VoiceDiagnosticsStore(
                directory: recordingStore.diagnosticsDirectory
            )
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           CaptureTargetApplicationPolicy.canReceiveDictation(
               bundleIdentifier: frontmost.bundleIdentifier
           ) {
            lastExternalApplicationPID = frontmost.processIdentifier
        }
        recorder.onUnexpectedTermination = { [weak self] in
            self?.handleUnexpectedRecorderTermination()
        }

        // Present visible UI before touching Keychain. A credential prompt or
        // error must never make this agent-style app appear to launch and quit.
        Task {
            await Task.yield()
            FloatingPanelController.shared.show(model: self)
            outputVolumeController.recoverInterruptedSessionIfNeeded()
            registerGlobalShortcuts()
            await loadSecureSettings()
            await refreshDiagnostics()
            startLiveUpdates()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshContext(showProgress: false)
                await self?.retryPendingInBackground()
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  CaptureTargetApplicationPolicy.canReceiveDictation(
                      bundleIdentifier: application.bundleIdentifier
                  ) else {
                return
            }
            Task { @MainActor in
                self?.lastExternalApplicationPID = application.processIdentifier
            }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.outputVolumeController.restoreNow()
            }
        }
    }

    func refresh() async {
        await refreshContext(showProgress: true)
    }

    func toggleTimerPanel() {
        guard hasTimerInstrument, !isRecording else { return }
        withAnimation(.easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds)) {
            timerPanelExpanded.toggle()
            if !timerPanelExpanded {
                cancelFinishDrawer()
                activityPickerExpanded = false
            }
        }
        synchronizeFloatingPanelSize()
    }

    func toggleActivityPicker() {
        guard !timerMutationInFlight else { return }
        withAnimation(.easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds)) {
            activityPickerExpanded.toggle()
            if activityPickerExpanded {
                cancelFinishDrawer()
            }
        }
        synchronizeFloatingPanelSize()
    }

    func openFinishDrawer(for activity: VoiceTimerActivity) {
        guard activity.timer?.startedAt != nil, !timerMutationInFlight else { return }
        if activity.isFocusBlock {
            performTimerAction(subjectID: activity.id, kind: "activity", action: "finish")
            return
        }
        withAnimation(.easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds)) {
            finishingActivityID = activity.id
            finishOutcome = nil
            finishStarred = activity.starred
            activityPickerExpanded = false
            timerMutationMessage = nil
        }
        synchronizeFloatingPanelSize()
    }

    func cancelFinishDrawer() {
        withAnimation(.easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds)) {
            finishingActivityID = nil
            finishOutcome = nil
            finishStarred = false
        }
        synchronizeFloatingPanelSize()
    }

    func performTimerAction(
        subjectID: String,
        kind: String,
        action: String
    ) {
        guard !timerMutationInFlight else { return }
        Task {
            await runTimerMutation {
                try await self.timerAPIClient().mutateTimer(
                    subjectID: subjectID,
                    kind: kind,
                    action: action
                )
            }
        }
    }

    func requestFinishSession(_ session: VoiceTimerSession) {
        guard session.timer.startedAt != nil, !timerMutationInFlight else { return }
        let blockers = timerInstrument?.sessionFinishBlockers ?? []
        guard !blockers.isEmpty else {
            performTimerAction(subjectID: session.id, kind: "session", action: "finish")
            return
        }
        withAnimation(.easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds)) {
            sessionFinishResolutionRequested = true
            finishingActivityID = nil
            activityPickerExpanded = false
            timerMutationMessage = nil
        }
        synchronizeFloatingPanelSize()
        SessionFinishResolverWindowPresenter.shared.present(model: self)
    }

    func cancelSessionFinishResolution() {
        withAnimation(.easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds)) {
            sessionFinishResolutionRequested = false
        }
        SessionFinishResolverWindowPresenter.shared.dismiss()
        synchronizeFloatingPanelSize()
    }

    func requestSessionFinishReview() {
        SessionFinishResolverWindowPresenter.shared.present(model: self)
    }

    func resolveSessionActivity(
        _ activity: VoiceTimerActivity,
        outcome: VoicePracticeOutcome
    ) {
        guard !timerMutationInFlight, !activity.isFocusBlock else { return }
        Task {
            let succeeded = await runTimerMutation {
                try await self.timerAPIClient().finishActivity(
                    activityID: activity.id,
                    outcome: outcome,
                    starred: activity.starred
                )
            }
            guard succeeded else { return }
            let blockers = self.timerInstrument?.sessionFinishBlockers ?? []
            guard blockers.isEmpty, let session = self.timerInstrument?.session else { return }
            self.cancelSessionFinishResolution()
            _ = await self.runTimerMutation {
                try await self.timerAPIClient().mutateTimer(
                    subjectID: session.id,
                    kind: "session",
                    action: "finish"
                )
            }
        }
    }

    func startActivity(_ activity: VoiceTimerActivity, openProblem: Bool) {
        guard !timerMutationInFlight else { return }
        Task {
            let succeeded = await runTimerMutation {
                try await self.timerAPIClient().mutateTimer(
                    subjectID: activity.id,
                    kind: "activity",
                    action: "start"
                )
            }
            if succeeded, openProblem, let value = activity.url, let url = URL(string: value) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func confirmFinishActivity() {
        guard
            let activityID = finishingActivityID,
            let finishOutcome,
            !timerMutationInFlight
        else { return }
        Task {
            let succeeded = await runTimerMutation {
                try await self.timerAPIClient().finishActivity(
                    activityID: activityID,
                    outcome: finishOutcome,
                    starred: self.finishStarred
                )
            }
            if succeeded {
                cancelFinishDrawer()
            }
        }
    }

    func elapsedSeconds(for timer: VoiceTimerState, now: Date) -> Int {
        timer.elapsedSeconds(
            serverNow: timerInstrument?.serverNow ?? Int64(Date().timeIntervalSince1970 * 1_000),
            receivedAt: timerInstrumentReceivedAt,
            now: now
        )
    }

    func toggleRecording() {
        switch RecordingCommandPolicy.action(
            isRecording: isRecording,
            isStarting: isStartingRecording,
            isBusy: isBusy
        ) {
        case .stop:
            stopAndProcess()
        case .cancelStart:
            recordingStartupTask?.cancel()
        case .start:
            isStartingRecording = true
            recordingStartupTask = Task { [weak self] in
                guard let self else { return }
                defer {
                    self.isStartingRecording = false
                    self.recordingStartupTask = nil
                }
                await self.prepareAndStartRecording()
            }
        case .ignore:
            break
        }
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            lastInsertionText.isEmpty ? lastTranscript : lastInsertionText,
            forType: .string
        )
        contextMessage = lastInsertionText == lastTranscript || lastInsertionText.isEmpty
            ? "Transcript copied."
            : "Transcript and Voice v2 envelope copied."
    }

    func copyPendingCapture(_ capture: PendingVoiceCapture) {
        let payload = CaptureActionPolicy.copyPayload(
            transcript: capture.transcript,
            captureID: capture.id,
            activityID: capture.activity.activityId,
            turnID: capture.turnID
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)
        contextMessage = "Capture and Voice v2 envelope copied."
    }

    func insertPendingAgain(_ capture: PendingVoiceCapture) {
        let envelope = VoiceCaptureEnvelope(
            captureID: capture.id,
            activityID: capture.activity.activityId,
            turnID: capture.turnID,
            transcript: capture.transcript
        )
        targetApplicationPID = currentInsertionTargetPID()
        Task {
            let inserted = await insertTranscript(
                capture.transcript,
                editorText: envelope.editorText,
                showDeliveryStep: true
            )
            switch CaptureActionPolicy.insertionCompletion(inserted: inserted) {
            case .delivered:
                clearFailureAfterSuccess()
                phase = .delivered
                contextMessage = "Capture and Voice v2 envelope inserted again."
            case .needsAttention:
                phase = hasGroqCredential ? .idle : .setup
                contextMessage = "No editable cursor was available."
            }
        }
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
            let player: AVAudioPlayer
            if let audioPlayer {
                player = audioPlayer
            } else {
                player = try AVAudioPlayer(data: lastAudioData)
                player.prepareToPlay()
                audioPlayer = player
                playbackDuration = player.duration
            }
            if player.currentTime >= max(0, player.duration - 0.05) {
                player.currentTime = 0
            }
            player.play()
            isPlayingLastAudio = true
            isPlaybackExpanded = true
            playbackCurrentTime = player.currentTime
            playbackTimer?.invalidate()
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let previousTime = self.playbackCurrentTime
                    let currentTime = self.audioPlayer?.currentTime ?? 0
                    self.playbackCurrentTime = currentTime
                    if self.audioPlayer?.isPlaying != true {
                        self.isPlayingLastAudio = false
                        if self.playbackCompletionPolicy.didFinish(
                            previousTime: previousTime,
                            currentTime: currentTime,
                            duration: self.playbackDuration
                        ) {
                            self.audioPlayer?.currentTime = 0
                            self.playbackCurrentTime = 0
                            self.isPlaybackExpanded = false
                        }
                        self.playbackTimer?.invalidate()
                        self.playbackTimer = nil
                    }
                }
            }
        } catch {
            reportFailure(error, stage: .playback, hasRecoverableAudio: hasLastAudio)
        }
    }

    func stopLastAudioPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlayingLastAudio = false
        isPlaybackExpanded = false
        playbackCurrentTime = 0
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    func seekLastAudio(to progress: Double) {
        guard let audioPlayer else { return }
        let time = min(1, max(0, progress)) * audioPlayer.duration
        audioPlayer.currentTime = time
        playbackCurrentTime = time
    }

    func exportLastMemo() {
        guard hasLastMemo else { return }
        let plan = VoiceMemoExportPlan(
            activityTitle: lastMemoActivityTitle,
            createdAt: lastMemoCreatedAt
        )
        let panel = NSSavePanel()
        panel.title = "Save Voice Memo"
        panel.message = lastMemoActivityTitle.map { "Linked to \($0)" }
            ?? "General dictation · not linked to Interview Arc"
        panel.prompt = "Save"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.mpeg4Audio]
        panel.nameFieldStringValue = plan.suggestedAudioFilename
        let transcriptCheckbox = NSButton(
            checkboxWithTitle: "Also save transcript as .txt",
            target: nil,
            action: nil
        )
        transcriptCheckbox.state = lastTranscript.isEmpty ? .off : .on
        transcriptCheckbox.isEnabled = !lastTranscript.isEmpty
        transcriptCheckbox.toolTip = "The transcript uses the same filename as the audio."
        panel.accessoryView = transcriptCheckbox
        guard panel.runModal() == .OK, let audioURL = panel.url else { return }

        do {
            if let lastAudioData {
                try lastAudioData.write(to: audioURL, options: .atomic)
            }
            if transcriptCheckbox.state == .on, !lastTranscript.isEmpty {
                try lastTranscript.write(
                    to: plan.transcriptURL(forAudioURL: audioURL),
                    atomically: true,
                    encoding: .utf8
                )
            }
            contextMessage = "Voice memo saved."
        } catch {
            reportFailure(error, stage: .export, hasRecoverableAudio: hasLastAudio)
        }
    }

    func retryLastTranscription() {
        guard canRetryLastTranscription,
              let lastAudioData,
              let recordingStore else { return }
        let retryURL = lastAudioURL ?? recordingStore.nextTemporaryRecordingURL()
        do {
            if !FileManager.default.fileExists(atPath: retryURL.path) {
                try lastAudioData.write(to: retryURL, options: .atomic)
            }
            let retryStartedAt = Date()
            let speechScanStartedAt = Date()
            let speechEvidence = speechProtectionMode == .off
                ? nil
                : try LocalSpeechEvidenceAnalyzer.inspect(retryURL)
            let speechScanSeconds = speechProtectionMode == .off
                ? 0
                : Date().timeIntervalSince(speechScanStartedAt)
            guard speechEvidence?.containsSpeech != false else {
                canRetryLastTranscription = false
                reportFailure(
                    kind: .recording,
                    title: "No speech detected",
                    message: "Nothing was inserted or sent · record again when ready",
                    detail: "Local speech detection found no sustained speech-shaped frames in the preserved recording.",
                    actions: [.recordAgain, .playRecording, .saveRecording]
                )
                return
            }
            let diagnosticSeed = CaptureDiagnosticSeed(
                id: UUID(),
                startedAt: retryStartedAt,
                recordingDurationSeconds: lastAudioDuration,
                fileFinalizationSeconds: 0,
                integrityInspectionSeconds: 0,
                localSpeechScanSeconds: speechScanSeconds,
                protectionMode: speechProtectionMode
            )
            targetApplicationPID = currentInsertionTargetPID()
            canRetryLastTranscription = false
            captureGeneration = UUID()
            let generation = captureGeneration
            beginProcessing()
            phase = .transcribing
            Task {
                let recording = RecordedCapture(
                    url: retryURL,
                    duration: lastAudioDuration,
                    writtenFrameCount: 1,
                    writeErrorDescription: nil
                )
                switch lastRetryDestination {
                case .linked(let activity, let startedAt):
                    await processLinked(
                        recording: recording,
                        activity: activity,
                        startedAt: startedAt,
                        generation: generation,
                        speechEvidence: speechEvidence,
                        diagnosticSeed: diagnosticSeed
                    )
                case .general, nil:
                    await processGeneral(
                        recording: recording,
                        rememberAudio: false,
                        speechEvidence: speechEvidence,
                        diagnosticSeed: diagnosticSeed
                    )
                }
            }
        } catch {
            reportFailure(error, stage: .recording, hasRecoverableAudio: hasLastAudio)
        }
    }

    func toggleLinkMode() {
        setLinkMode(!linkToInterviewArc)
    }

    func selectWidgetTheme(_ theme: VoiceWidgetTheme) {
        guard widgetTheme != theme else { return }
        widgetTheme = theme
        theme.save()
    }

    func setBackgroundAudioMode(_ mode: BackgroundAudioRecordingMode) {
        backgroundAudioMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "voice.backgroundAudioMode")
    }

    func setBackgroundAudioRelativeLevel(_ level: Double) {
        backgroundAudioRelativeLevel = max(0.05, min(0.50, level))
        UserDefaults.standard.set(
            backgroundAudioRelativeLevel,
            forKey: "voice.backgroundAudioRelativeLevel"
        )
    }

    func setDynamicRecordingInterfaceEnabled(_ enabled: Bool) {
        dynamicRecordingInterfaceEnabled = enabled
        UserDefaults.standard.set(
            enabled,
            forKey: "voice.dynamicRecordingInterfaceEnabled"
        )
    }

    func setSpeechProtectionMode(_ mode: SpeechProtectionMode) {
        speechProtectionMode = mode
        mode.save()
    }

    func refreshDiagnostics() async {
        diagnosticRecords = (try? await diagnosticsStore?.records()) ?? []
    }

    func copyDiagnostic(_ record: VoiceDiagnosticRecord) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(record.report, forType: .string)
        contextMessage = "Diagnostic timing report copied."
    }

    func revealDiagnosticsFile() {
        guard let fileURL = diagnosticsStore?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func clearDiagnostics() {
        Task {
            try? await diagnosticsStore?.clear()
            await refreshDiagnostics()
        }
    }

    private func recordDiagnostic(
        seed: CaptureDiagnosticSeed,
        timing: TranscriptionTiming?,
        segmentValidationSeconds: Double,
        insertionSeconds: Double,
        omittedUnsupportedSegmentCount: Int,
        outcome: VoiceDiagnosticOutcome
    ) async {
        let record = VoiceDiagnosticRecord(
            id: seed.id,
            createdAt: seed.startedAt,
            recordingDurationSeconds: seed.recordingDurationSeconds,
            fileFinalizationSeconds: seed.fileFinalizationSeconds,
            integrityInspectionSeconds: seed.integrityInspectionSeconds,
            localSpeechScanSeconds: seed.localSpeechScanSeconds,
            providerWaitSeconds:
                (timing?.chunkPreparationSeconds ?? 0)
                + (timing?.providerWaitSeconds ?? 0),
            responseProcessingSeconds: timing?.responseProcessingSeconds ?? 0,
            segmentValidationSeconds: segmentValidationSeconds,
            insertionSeconds: insertionSeconds,
            totalSeconds: Date().timeIntervalSince(seed.startedAt),
            protectionMode: seed.protectionMode,
            omittedUnsupportedSegmentCount: omittedUnsupportedSegmentCount,
            outcome: outcome
        )
        try? await diagnosticsStore?.append(record)
        await refreshDiagnostics()
    }

    func setLinkMode(_ enabled: Bool) {
        guard !isRecording else { return }
        linkToInterviewArc = enabled
        UserDefaults.standard.set(enabled, forKey: "voice.linkToInterviewArc")
        startLiveUpdates()
        synchronizePendingReconciliationLoop()
        reconcilePersistedCredentialFailure()
        if !isBusy {
            deliveryStates = [:]
        }
        if enabled {
            contextMessage = "Auto-link will check the current activity before recording."
            if !isBusy {
                phase = failureNotice.map { .failed($0.title) }
                    ?? (hasGroqCredential ? .idle : .setup)
            }
            Task { await refreshContext(showProgress: false) }
        } else {
            timerPanelExpanded = false
            cancelFinishDrawer()
            activityPickerExpanded = false
            contextMessage = "General dictation will not touch Interview Arc."
            if !isBusy {
                phase = failureNotice.map { .failed($0.title) }
                    ?? (hasGroqCredential ? .idle : .setup)
            }
        }
    }

    func saveSettings() {
        do {
            let submittedToken = connectionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let submittedGroqKey = groqKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !submittedGroqKey.isEmpty else {
                throw VoiceBridgeError.missingCredential("Groq API key")
            }
            try keychain.set(submittedToken, for: .interviewArcToken)
            try keychain.set(submittedGroqKey, for: .groqAPIKey)
            let savedToken = try keychain.value(for: .interviewArcToken)
            let savedGroqKey = try keychain.value(for: .groqAPIKey)
            let verification = CredentialSaveVerificationPolicy()
            guard verification.isVerified(
                submittedValue: submittedToken,
                retrievedValue: savedToken,
                permitsEmpty: true
            ) else {
                throw CredentialPersistenceError(credential: .interviewArcToken)
            }
            guard verification.isVerified(
                submittedValue: submittedGroqKey,
                retrievedValue: savedGroqKey
            ) else {
                throw CredentialPersistenceError(credential: .groqAPIKey)
            }
            connectionTokenDraft = savedToken ?? ""
            groqKeyDraft = savedGroqKey ?? ""
            UserDefaults.standard.set(apiBaseURL, forKey: "voice.apiBaseURL")
            UserDefaults.standard.set(workspacePath, forKey: "voice.workspacePath")
            UserDefaults.standard.set(codexPath, forKey: "voice.codexPath")
            reconcilePersistedCredentialFailure()
            if !isBusy {
                phase = failureNotice.map { .failed($0.title) }
                    ?? (hasGroqCredential ? .idle : .setup)
            }
            settingsExpanded = false
            startLiveUpdates()
            Task { await refreshContext(showProgress: false) }
        } catch {
            reportFailure(error, stage: .configuration)
        }
    }

    func requestAccessibilityPermission() {
        textInjector.requestAccessibilityPermission()
        accessibilityNeeded = !textInjector.accessibilityTrusted
    }

    func beginShortcutCapture() {
        guard shortcutMonitor == nil, linkShortcutMonitor == nil else { return }
        shortcutMessage = nil
        shortcutCapturing = true
        suspendGlobalShortcuts()
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if Int(event.keyCode) == kVK_Escape {
                self.endShortcutCapture()
                return nil
            }
            guard let shortcut = HotKeyShortcut.from(event: event) else { return nil }
            guard shortcut != self.linkShortcut else {
                self.shortcutMessage = "Record/Stop and link mode need different shortcuts."
                self.endShortcutCapture()
                return nil
            }
            self.shortcut = shortcut
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: "voice.shortcut")
            }
            self.endShortcutCapture()
            return nil
        }
    }

    func beginLinkShortcutCapture() {
        guard shortcutMonitor == nil, linkShortcutMonitor == nil else { return }
        shortcutMessage = nil
        linkShortcutCapturing = true
        suspendGlobalShortcuts()
        linkShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if Int(event.keyCode) == kVK_Escape {
                self.endLinkShortcutCapture()
                return nil
            }
            guard let shortcut = HotKeyShortcut.from(event: event) else { return nil }
            guard shortcut != self.shortcut else {
                self.shortcutMessage = "Record/Stop and link mode need different shortcuts."
                self.endLinkShortcutCapture()
                return nil
            }
            self.linkShortcut = shortcut
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: "voice.linkShortcut")
            }
            self.endLinkShortcutCapture()
            return nil
        }
    }

    func cancelShortcutCapture() {
        if shortcutCapturing {
            endShortcutCapture()
        } else if linkShortcutCapturing {
            endLinkShortcutCapture()
        }
    }

    func retryPending() {
        phase = .sending
        Task {
            if pipeline == nil { pipeline = try? makeLinkedPipeline() }
            guard let pipeline else {
                reportFailure(
                    VoiceBridgeError.missingCredential("Interview Arc token"),
                    stage: .configuration
                )
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

    func showFailureDetails() {
        guard failureNotice != nil else { return }
        failureDetailsPresented = true
    }

    func dismissFailure() {
        failureDetailsPresented = false
        failureNotice = nil
        UserDefaults.standard.removeObject(forKey: "voice.lastFailure")
        if case .failed = phase {
            phase = hasGroqCredential ? .idle : .setup
        }
    }

    func performFailureAction(_ action: VoiceFailureAction) {
        switch action {
        case .recordAgain:
            failureDetailsPresented = false
            if canRecord { toggleRecording() }
        case .retryTranscription:
            failureDetailsPresented = false
            retryLastTranscription()
        case .playRecording:
            toggleLastAudioPlayback()
        case .saveRecording:
            exportLastMemo()
        case .insertAgain:
            failureDetailsPresented = false
            reinsertLastTranscript()
        case .enableAccessibility:
            requestAccessibilityPermission()
        case .openSettings:
            failureDetailsPresented = false
            settingsExpanded = true
        case .retryConnection:
            failureDetailsPresented = false
            Task { await refresh() }
        }
    }

    func performFailurePopoverAction(_ action: VoiceFailureAction) {
        pendingFailurePopoverActionTask?.cancel()
        pendingFailurePopoverActionTask = nil
        if let pendingFailurePopoverCloseObserver {
            NotificationCenter.default.removeObserver(
                pendingFailurePopoverCloseObserver
            )
            self.pendingFailurePopoverCloseObserver = nil
        }
        switch FloatingWidgetRecoveryPolicy.timing(for: action) {
        case .immediate:
            performFailureAction(action)
        case .afterPopoverDismissal:
            pendingFailurePopoverCloseObserver = NotificationCenter.default
                .addObserver(
                    forName: NSPopover.didCloseNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.completeFailurePopoverActionAfterClose(action)
                    }
                }
            failureDetailsPresented = false
            pendingFailurePopoverActionTask = Task { [weak self] in
                try? await Task.sleep(
                    for: .milliseconds(
                        FloatingWidgetRecoveryPolicy.dismissalSettleMilliseconds
                    )
                )
                guard !Task.isCancelled else { return }
                self?.completeFailurePopoverActionAfterClose(action)
            }
        }
    }

    private func completeFailurePopoverActionAfterClose(
        _ action: VoiceFailureAction
    ) {
        pendingFailurePopoverActionTask?.cancel()
        pendingFailurePopoverActionTask = nil
        if let pendingFailurePopoverCloseObserver {
            NotificationCenter.default.removeObserver(
                pendingFailurePopoverCloseObserver
            )
            self.pendingFailurePopoverCloseObserver = nil
        }
        // The native close notification is delivered after its animation.
        // Yield one main-loop turn so AppKit can commit the anchor's final
        // geometry before the recorder widens for playback or recording.
        Task { [weak self] in
            await Task.yield()
            self?.performFailureAction(action)
        }
    }

    private func reportFailure(
        kind: VoiceFailureKind,
        title: String,
        message: String,
        detail: String,
        actions: [VoiceFailureAction]
    ) {
        let notice = VoiceFailureNotice(
            kind: kind,
            title: title,
            message: message,
            detail: detail,
            actions: actions
        )
        failureNotice = notice
        phase = .failed(title)
        contextMessage = message
        if let data = try? JSONEncoder().encode(notice) {
            UserDefaults.standard.set(data, forKey: "voice.lastFailure")
        }
        voiceBridgeLogger.error(
            "Failure [\(kind.rawValue, privacy: .public)]: \(title, privacy: .public) — \(detail, privacy: .public)"
        )
    }

    private func reportFailure(
        _ error: Error,
        stage: FailureStage,
        hasRecoverableAudio: Bool = false
    ) {
        let detail = String(
            error.localizedDescription
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(420)
        )
        switch stage {
        case .microphone:
            reportFailure(
                kind: .microphone,
                title: "Microphone unavailable",
                message: "Voice could not open the microphone",
                detail: detail,
                actions: [.recordAgain, .openSettings]
            )
        case .recording:
            reportFailure(
                kind: .recording,
                title: "Recording failed",
                message: hasRecoverableAudio
                    ? "Recording preserved · choose Play or Save"
                    : "No usable recording was created",
                detail: detail,
                actions: hasRecoverableAudio
                    ? [.recordAgain, .playRecording, .saveRecording]
                    : [.recordAgain]
            )
        case .transcription:
            reportFailure(
                kind: .transcription,
                title: "Transcription failed",
                message: hasRecoverableAudio
                    ? "Recording preserved · choose Retry or Play"
                    : "The speech service did not return a transcript",
                detail: detail,
                actions: hasRecoverableAudio
                    ? [.retryTranscription, .playRecording, .saveRecording]
                    : [.recordAgain]
            )
        case .insertion:
            reportFailure(
                kind: .insertion,
                title: "Text was not inserted",
                message: "Your transcript is safe · focus an editor and insert again",
                detail: detail,
                actions: [.insertAgain, .enableAccessibility]
            )
        case .interviewArc:
            reportFailure(
                kind: .interviewArc,
                title: "Interview Arc delivery delayed",
                message: "Your answer is safe · delivery can be retried",
                detail: detail,
                actions: [.retryConnection, .playRecording, .saveRecording]
            )
        case .configuration:
            reportFailure(
                kind: .configuration,
                title: "Settings need attention",
                message: "Open settings to finish Voice setup",
                detail: detail,
                actions: [.openSettings]
            )
        case .playback:
            reportFailure(
                kind: .playback,
                title: "Playback failed",
                message: "The recording could not be played",
                detail: detail,
                actions: [.saveRecording]
            )
        case .export:
            reportFailure(
                kind: .export,
                title: "Save failed",
                message: "Voice could not save the recording",
                detail: detail,
                actions: [.saveRecording]
            )
        }
    }

    private func clearFailureAfterSuccess() {
        failureDetailsPresented = false
        failureNotice = nil
        UserDefaults.standard.removeObject(forKey: "voice.lastFailure")
    }

    private func reconcilePersistedCredentialFailure() {
        let retainedFailure = CredentialFailureRecoveryPolicy().retainedFailure(
            failureNotice,
            configurationIsReady: configurationIsReady
        )
        guard failureNotice != nil, retainedFailure == nil else { return }
        clearFailureAfterSuccess()
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
        accessibilityNeeded = !textInjector.accessibilityTrusted
        if let errorDescription = snapshot.errorDescription {
            reportFailure(
                kind: .configuration,
                title: "Keychain access failed",
                message: "Open settings to enter your keys again",
                detail: errorDescription,
                actions: [.openSettings]
            )
        } else if CredentialReadinessPolicy().readiness(
            groqAPIKey: snapshot.groqAPIKey
        ) == .missingGroqAPIKey {
            reportFailure(
                kind: .configuration,
                title: "Settings need attention",
                message: "Add your Groq API key to start recording",
                detail: "Open Voice settings, enter the Groq API key, and save it. Voice verifies the saved Keychain value before enabling recording.",
                actions: [.openSettings]
            )
        } else {
            reconcilePersistedCredentialFailure()
            phase = failureNotice.map { .failed($0.title) }
                ?? (hasGroqCredential ? .idle : .setup)
        }
        await refreshContext(showProgress: false)
        await retryPendingInBackground()
    }

    private func refreshContext(showProgress: Bool) async {
        contextRefreshRequestID += 1
        let requestID = contextRefreshRequestID
        guard linkToInterviewArc else {
            contextMessage = "General dictation will not touch Interview Arc."
            timerPanelExpanded = false
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
            guard ContextRefreshOrderingPolicy.shouldApply(
                requestID: requestID,
                latestRequestID: contextRefreshRequestID
            ) else { return }
            context = contextRetentionPolicy.context(previous: context, refreshed: loaded)
            timerInstrument = loaded.timerInstrument
            timerInstrumentReceivedAt = Date()
            if !hasTimerInstrument {
                timerPanelExpanded = false
                cancelFinishDrawer()
            }
            if loaded.timerInstrument?.session == nil {
                sessionFinishResolutionRequested = false
            }
            contextLastVerifiedAt = Date()
            applyLateCaptureBinding(from: loaded)
            if let activity = loaded.focusedActivity {
                if !isRecording && !isBusy { contextMessage = "Linked to \(activity.title)" }
            } else {
                if !isRecording && !isBusy { contextMessage = "No focused activity — using general dictation." }
            }
            // Focus refresh is intentionally read-only. Capture reconciliation
            // is driven by Voice events, startup/wake, or an explicit retry.
        } catch {
            guard ContextRefreshOrderingPolicy.shouldApply(
                requestID: requestID,
                latestRequestID: contextRefreshRequestID
            ) else { return }
            context = contextRetentionPolicy.context(previous: context, refreshed: nil)
            if !isRecording && !isBusy {
                contextMessage = context?.focusedActivity == nil
                    ? "Interview Arc is unavailable — using general dictation."
                    : "Interview Arc refresh delayed — keeping the last verified activity."
            }
        }
        settlePhaseAfterContextRefresh(force: showProgress)
    }

    private func timerAPIClient() throws -> InterviewArcAPIClient {
        let token = connectionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw VoiceBridgeError.missingCredential("Interview Arc token")
        }
        guard let baseURL = URL(string: apiBaseURL) else {
            throw VoiceBridgeError.invalidResponse(0, "Interview Arc API address is invalid.")
        }
        return InterviewArcAPIClient(baseURL: baseURL, token: token)
    }

    @discardableResult
    private func runTimerMutation(
        operation: () async throws -> VoiceTimerMutationResponse
    ) async -> Bool {
        timerMutationInFlight = true
        timerMutationMessage = nil
        defer { timerMutationInFlight = false }
        do {
            let response = try await operation()
            guard response.protocolVersion == InterviewArcAPIClient.protocolVersion else {
                throw VoiceBridgeError.protocolMismatch(response.protocolVersion)
            }
            timerInstrument = response.timerInstrument
            timerInstrumentReceivedAt = Date()
            if !hasTimerInstrument {
                timerPanelExpanded = false
                cancelFinishDrawer()
            }
            if response.timerInstrument.session == nil {
                sessionFinishResolutionRequested = false
            }
            await refreshContext(showProgress: false)
            return true
        } catch {
            timerMutationMessage = error.localizedDescription
            return false
        }
    }

    private func startLiveUpdates() {
        contextPollTask?.cancel()
        contextPollTask = Task { [weak self] in
            var fallbackAttempt = 0
            let fallbackPolicy = VoiceLiveUpdateFallbackPolicy()
            while !Task.isCancelled {
                guard
                    let self,
                    self.linkToInterviewArc,
                    let baseURL = URL(string: self.apiBaseURL)
                else {
                    try? await Task.sleep(for: .seconds(15))
                    continue
                }
                let token = self.connectionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !token.isEmpty else {
                    try? await Task.sleep(for: .seconds(15))
                    continue
                }
                do {
                    let client = InterviewArcAPIClient(baseURL: baseURL, token: token)
                    let updates = await client.liveUpdates(afterRevision: self.lastLiveRevision)
                    for try await signal in updates {
                        guard !Task.isCancelled else { return }
                        fallbackAttempt = 0
                        switch signal {
                        case .connected(let revision):
                            self.lastLiveRevision = max(self.lastLiveRevision, revision)
                            await self.retryPendingInBackground()
                            if !self.timerMutationInFlight {
                                await self.refreshContext(showProgress: false)
                            }
                        case .practiceChanged(let update):
                            self.lastLiveRevision = max(self.lastLiveRevision, update.revision)
                            if ["voice_intent", "voice_capture"].contains(update.scope) {
                                await self.retryPendingInBackground()
                            } else if !self.timerMutationInFlight {
                                await self.refreshContext(showProgress: false)
                            }
                        }
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                }
                let delay = fallbackPolicy.delaySeconds(attempt: fallbackAttempt)
                fallbackAttempt += 1
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                if !self.timerMutationInFlight {
                    await self.refreshContext(showProgress: false)
                }
                await self.retryPendingInBackground()
            }
        }
    }

    private func prepareAndStartRecording() async {
        guard RecordingPreparationPolicy.canPrepare(
            hasGroqCredential: hasGroqCredential,
            isBusy: isBusy
        ) else {
            if failureNotice?.kind != .configuration {
                reportFailure(
                    VoiceBridgeError.missingCredential("Groq API key"),
                    stage: .configuration
                )
            }
            return
        }
        guard textInjector.accessibilityTrusted else {
            accessibilityNeeded = true
            textInjector.requestAccessibilityPermission()
            reportFailure(
                kind: .insertion,
                title: "Accessibility permission required",
                message: "Allow Voice to insert text at the focused cursor",
                detail: "macOS Accessibility access is currently disabled for Interview Arc Voice.",
                actions: [.enableAccessibility]
            )
            return
        }
        targetApplicationPID = currentInsertionTargetPID()
        if let targetApplicationPID,
           let targetApplication = NSRunningApplication(processIdentifier: targetApplicationPID) {
            captureStartedInCodex = CaptureTargetApplicationPolicy.canAttachToInterviewArc(
                bundleIdentifier: targetApplication.bundleIdentifier
            )
        } else {
            captureStartedInCodex = false
        }
        deliveryStates = [:]
        canRetryLastTranscription = false
        captureGeneration = UUID()

        // Context is refreshed continuously while idle. Opening the
        // microphone must not wait for a network round trip because that
        // loses the first words of an answer.
        let recordingStartedAt = Date()
        let route = routingPolicy.route(
            linkToInterviewArc: linkToInterviewArc && captureStartedInCodex,
            hasFocusedActivity: context?.focusedActivity != nil && contextIsFreshForCapture
        )
        switch route {
        case .linked:
            guard let activity = context?.focusedActivity else { return }
            captureDestination = .linked(activity, startedAt: recordingStartedAt)
        case .general:
            captureDestination = .general(startedAt: recordingStartedAt)
        }

        guard let recordingStore else {
            reportFailure(
                VoiceBridgeError.recordingUnavailable,
                stage: .configuration
            )
            return
        }
        let destination: URL
        switch captureDestination {
        case .linked(let activity, _): destination = recordingStore.nextRecordingURL(activityID: activity.activityId)
        case .general: destination = recordingStore.nextTemporaryRecordingURL()
        case nil: return
        }
        do {
            outputVolumeController.prepareForRecording(
                mode: backgroundAudioMode,
                relativeLevel: backgroundAudioRelativeLevel
            )
            phase = .preparingMicrophone
            contextMessage = "Preparing the microphone route…"
            try await recorder.start(
                at: destination,
                captureBackendDidStart: { [weak self] in
                    self?.outputVolumeController.recordingDidStart()
                }
            )
            try Task.checkCancellation()
            let readyAt = Date()
            switch captureDestination {
            case .linked(let activity, _):
                captureDestination = .linked(activity, startedAt: readyAt)
            case .general:
                captureDestination = .general(startedAt: readyAt)
            case nil:
                throw VoiceBridgeError.recordingUnavailable
            }
            if dynamicRecordingInterfaceEnabled {
                let currentDisclosure = FloatingWidgetDisclosureState(
                    timerPanelExpanded: timerPanelExpanded,
                    finishingActivityID: finishingActivityID,
                    activityPickerExpanded: activityPickerExpanded
                )
                disclosureStateBeforeRecording = currentDisclosure
                dynamicRecordingInterfaceActive = true
                let recordingDisclosure = FloatingWidgetWindowPolicy
                    .disclosureStateWhenRecordingStarts(
                        current: currentDisclosure
                    )
                timerPanelExpanded = recordingDisclosure.timerPanelExpanded
                finishingActivityID = recordingDisclosure.finishingActivityID
                activityPickerExpanded = recordingDisclosure.activityPickerExpanded
            } else {
                disclosureStateBeforeRecording = nil
                dynamicRecordingInterfaceActive = false
            }
            phase = .recording
            if linkToInterviewArc {
                Task { await refreshContext(showProgress: false) }
            }
        } catch is CancellationError {
            restoreDisclosureAfterRecording()
            outputVolumeController.restoreAfterRouteSettles()
            captureDestination = nil
            canRetryLastTranscription = false
            phase = .idle
            contextMessage = "Microphone preparation canceled."
        } catch {
            restoreDisclosureAfterRecording()
            outputVolumeController.restoreAfterRouteSettles()
            self.captureDestination = nil
            canRetryLastTranscription = false
            reportFailure(error, stage: .microphone)
        }
    }

    private func stopAndProcess(unexpectedTermination: Bool = false) {
        guard let captureDestination else {
            restoreDisclosureAfterRecording()
            reportFailure(
                VoiceBridgeError.recordingUnavailable,
                stage: .recording
            )
            return
        }
        do {
            let diagnosticStartedAt = Date()
            let fileFinalizationStartedAt = Date()
            var recording = try recorder.stop()
            let fileFinalizationSeconds = Date()
                .timeIntervalSince(fileFinalizationStartedAt)
            // The experiment is scoped to live capture. Transcription returns
            // immediately to the prior disclosure and uses the existing spinner.
            restoreDisclosureAfterRecording()
            phase = .transcribing
            outputVolumeController.restoreAfterRouteSettles()
            let generation = captureGeneration
            let memoActivityTitle: String?
            switch captureDestination {
            case .linked(let activity, _):
                memoActivityTitle = activity.title
                if let recordingStore {
                    recording = try recordingStore.promoteToLinkedRecording(
                        recording,
                        activityID: activity.activityId
                    )
                }
            case .general:
                memoActivityTitle = nil
            }
            self.captureDestination = nil
            lastRetryDestination = captureDestination
            if unexpectedTermination {
                rememberLastAudio(recording, activityTitle: memoActivityTitle)
                canRetryLastTranscription = true
                reportFailure(
                    kind: .recording,
                    title: "Recording stopped unexpectedly",
                    message: "Your audio is preserved · choose Retry, Play, or Save",
                    detail: "The active microphone stream ended without a Stop command. Voice preserved the finalized audio and did not silently submit a partial answer.",
                    actions: [.retryTranscription, .recordAgain, .playRecording, .saveRecording]
                )
                Task { [weak self] in
                    await Task.yield()
                    self?.failureDetailsPresented = true
                }
                return
            }
            let integrityInspectionStartedAt = Date()
            let evidence = try RecordingFileInspector.inspect(recording)
            let integrityInspectionSeconds = Date()
                .timeIntervalSince(integrityInspectionStartedAt)
            let recovery = RecordingRecoveryPolicy.action(for: evidence)
            voiceBridgeLogger.info(
                "Capture finalized: wall=\(evidence.wallDurationSeconds, privacy: .public)s decoded=\(evidence.decodedDurationSeconds, privacy: .public)s bytes=\(evidence.fileSizeBytes, privacy: .public) audioBytes=\(evidence.encodedAudioBytes ?? -1, privacy: .public) frames=\(evidence.decodedFrameCount, privacy: .public) recovery=\(String(describing: recovery), privacy: .public)"
            )
            var speechEvidence: SpeechEvidenceResult?
            var localSpeechScanSeconds = 0.0
            if recovery == .transcribe, speechProtectionMode != .off {
                let localSpeechScanStartedAt = Date()
                speechEvidence = try LocalSpeechEvidenceAnalyzer.inspect(recording.url)
                localSpeechScanSeconds = Date()
                    .timeIntervalSince(localSpeechScanStartedAt)
            }
            let diagnosticSeed = CaptureDiagnosticSeed(
                id: UUID(),
                startedAt: diagnosticStartedAt,
                recordingDurationSeconds: recording.duration,
                fileFinalizationSeconds: fileFinalizationSeconds,
                integrityInspectionSeconds: integrityInspectionSeconds,
                localSpeechScanSeconds: localSpeechScanSeconds,
                protectionMode: speechProtectionMode
            )

            switch recovery {
            case .transcribe:
                if let speechEvidence {
                    voiceBridgeLogger.info(
                        "Local speech evidence: speech=\(speechEvidence.containsSpeech, privacy: .public) duration=\(speechEvidence.analyzedDurationSeconds, privacy: .public)s frames=\(speechEvidence.speechLikeFrameCount, privacy: .public) run=\(speechEvidence.longestSpeechRunFrames, privacy: .public) floor=\(speechEvidence.noiseFloorDecibels, privacy: .public)dB peak=\(speechEvidence.peakFrameDecibels, privacy: .public)dB"
                    )
                    guard speechEvidence.containsSpeech else {
                        Task {
                            await recordDiagnostic(
                                seed: diagnosticSeed,
                                timing: nil,
                                segmentValidationSeconds: 0,
                                insertionSeconds: 0,
                                omittedUnsupportedSegmentCount: 0,
                                outcome: .noSpeech
                            )
                        }
                        try? FileManager.default.removeItem(at: recording.url)
                        lastRetryDestination = nil
                        canRetryLastTranscription = false
                        reportFailure(
                            kind: .recording,
                            title: "No speech detected",
                            message: "Nothing was inserted or sent · record again when ready",
                            detail: "Local speech detection found no sustained speech-shaped frames in the finalized recording.",
                            actions: [.recordAgain]
                        )
                        return
                    }
                }
                rememberLastAudio(recording, activityTitle: memoActivityTitle)
            case .preserveWithoutRetry:
                rememberLastAudio(recording, activityTitle: memoActivityTitle)
                canRetryLastTranscription = false
                reportFailure(
                    kind: .recording,
                    title: "Recording ended early",
                    message: "Playable audio preserved · record again for a complete answer",
                    detail: recordingDiagnosticDetail(evidence),
                    actions: [.recordAgain, .playRecording, .saveRecording]
                )
                return
            case .recordAgain:
                rememberLastAudio(recording, activityTitle: memoActivityTitle)
                canRetryLastTranscription = false
                reportFailure(
                    kind: .microphone,
                    title: "No microphone signal",
                    message: "Recording preserved · check the input and record again",
                    detail: recordingDiagnosticDetail(evidence)
                        + " No speech-level signal reached the selected input.",
                    actions: [.recordAgain, .playRecording, .saveRecording]
                )
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
                        generation: generation,
                        speechEvidence: speechEvidence,
                        diagnosticSeed: diagnosticSeed
                    )
                case .general:
                    await processGeneral(
                        recording: recording,
                        rememberAudio: false,
                        speechEvidence: speechEvidence,
                        diagnosticSeed: diagnosticSeed
                    )
                }
            }
        } catch {
            self.captureDestination = nil
            restoreDisclosureAfterRecording()
            outputVolumeController.restoreAfterRouteSettles()
            canRetryLastTranscription = false
            reportFailure(error, stage: .recording, hasRecoverableAudio: hasLastAudio)
        }
    }

    private func restoreDisclosureAfterRecording() {
        if let disclosureStateBeforeRecording {
            // Restore the hidden disclosure while the recording frame is still
            // active. The view reveals it only after the final state change, so
            // AppKit performs one anchored resize instead of a compact detour.
            timerPanelExpanded = disclosureStateBeforeRecording.timerPanelExpanded
            finishingActivityID = disclosureStateBeforeRecording.finishingActivityID
            activityPickerExpanded = disclosureStateBeforeRecording.activityPickerExpanded
        }
        self.disclosureStateBeforeRecording = nil
        dynamicRecordingInterfaceActive = false
    }

    private func processGeneral(
        recording: RecordedCapture,
        rememberAudio: Bool = true,
        speechEvidence: SpeechEvidenceResult? = nil,
        diagnosticSeed: CaptureDiagnosticSeed? = nil
    ) async {
        guard let recordingStore else {
            endProcessing()
            reportFailure(VoiceBridgeError.recordingUnavailable, stage: .configuration)
            return
        }
        if rememberAudio { rememberLastAudio(recording) }
        do {
            try validateRecording(recording)
        } catch {
            canRetryLastTranscription = false
            endProcessing()
            reportFailure(error, stage: .recording, hasRecoverableAudio: hasLastAudio)
            return
        }
        currentInsertionDurationSeconds = 0
        do {
            let generalPipeline = GeneralDictationPipeline(
                transcriber: GroqTranscriber(apiKey: groqKeyDraft),
                temporaryDirectory: recordingStore.temporaryDirectory,
                vocabularyPrompt: generalDictationPrompt
            )
            let result = try await generalPipeline.process(
                recordingURL: recording.url,
                durationSeconds: recording.duration,
                speechEvidence: speechEvidence,
                protectionMode: diagnosticSeed?.protectionMode
                    ?? speechProtectionMode
            )
            let transcript = result.transcription.text
            let inserted = await insertTranscript(
                transcript,
                editorText: transcript,
                showDeliveryStep: false
            )
            canRetryLastTranscription = false
            endProcessing()
            if inserted {
                clearFailureAfterSuccess()
                phase = .delivered
                contextMessage = "Dictation inserted at the cursor. Press Send when ready."
            } else {
                reportFailure(
                    VoiceBridgeError.codexUnavailable("No editable cursor was available."),
                    stage: .insertion,
                    hasRecoverableAudio: hasLastAudio
                )
            }
            if let diagnosticSeed {
                await recordDiagnostic(
                    seed: diagnosticSeed,
                    timing: result.transcription.timing,
                    segmentValidationSeconds: result.segmentValidationSeconds,
                    insertionSeconds: currentInsertionDurationSeconds,
                    omittedUnsupportedSegmentCount:
                        result.omittedUnsupportedSegmentCount,
                    outcome: inserted ? .delivered : .failed
                )
            }
        } catch {
            canRetryLastTranscription = hasLastAudio
            endProcessing()
            reportFailure(error, stage: .transcription, hasRecoverableAudio: hasLastAudio)
            if let diagnosticSeed {
                await recordDiagnostic(
                    seed: diagnosticSeed,
                    timing: nil,
                    segmentValidationSeconds: 0,
                    insertionSeconds: currentInsertionDurationSeconds,
                    omittedUnsupportedSegmentCount: 0,
                    outcome: .failed
                )
            }
        }
    }

    private func processLinked(
        recording: RecordedCapture,
        activity: FocusedVoiceActivity,
        startedAt: Date,
        generation: UUID,
        speechEvidence: SpeechEvidenceResult? = nil,
        diagnosticSeed: CaptureDiagnosticSeed? = nil
    ) async {
        do {
            try validateRecording(recording)
        } catch {
            guard generation == captureGeneration else { return }
            canRetryLastTranscription = false
            endProcessing()
            reportFailure(error, stage: .recording, hasRecoverableAudio: hasLastAudio)
            return
        }
        currentInsertionDurationSeconds = 0
        do {
            lastInsertionSucceeded = false
            let builtPipeline = try makeLinkedPipeline()
            pipeline = builtPipeline
            let result = try await builtPipeline.process(
                recordingURL: recording.url,
                durationSeconds: recording.duration,
                activity: activity,
                occurredAt: startedAt,
                speechEvidence: speechEvidence,
                protectionMode: diagnosticSeed?.protectionMode
                    ?? speechProtectionMode,
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
                reportFailure(
                    VoiceBridgeError.codexUnavailable("The answer was saved, but the focused editor was unavailable."),
                    stage: .insertion,
                    hasRecoverableAudio: hasLastAudio
                )
            } else {
                clearFailureAfterSuccess()
                phase = .delivered
                contextMessage = "Inserted at the cursor · waiting for specialist permission."
            }
            if let diagnosticSeed {
                await recordDiagnostic(
                    seed: diagnosticSeed,
                    timing: result.transcriptionTiming,
                    segmentValidationSeconds: result.segmentValidationSeconds,
                    insertionSeconds: currentInsertionDurationSeconds,
                    omittedUnsupportedSegmentCount:
                        result.omittedUnsupportedSegmentCount,
                    outcome: lastInsertionSucceeded ? .delivered : .failed
                )
            }
        } catch {
            guard generation == captureGeneration else { return }
            canRetryLastTranscription = hasLastAudio
            endProcessing()
            reportFailure(error, stage: .transcription, hasRecoverableAudio: hasLastAudio)
            if let diagnosticSeed {
                await recordDiagnostic(
                    seed: diagnosticSeed,
                    timing: nil,
                    segmentValidationSeconds: 0,
                    insertionSeconds: currentInsertionDurationSeconds,
                    omittedUnsupportedSegmentCount: 0,
                    outcome: .failed
                )
            }
        }
    }

    private func updateRetryCount() async {
        guard let recordingStore else { pendingRetryCount = 0; return }
        let queue = VoiceRetryQueue(directory: recordingStore.queueDirectory)
        let legacyCount = (try? await queue.items().count) ?? 0
        if pipeline == nil { pipeline = try? makeLinkedPipeline() }
        pendingVoiceCaptures = await pipeline?.pendingCaptures() ?? []
        legacyVoiceOrphans = await pipeline?.legacyVoiceOrphans() ?? []
        let transientCaptureCount = pendingVoiceCaptures.filter {
            $0.nextAttemptAt != nil
                && $0.localState != .waitingForSpecialist
                && $0.localState != .needsDecision
                && $0.localState != .excludedGracePeriod
                && $0.localState != .quarantinedConflict
        }.count
        pendingRetryCount = legacyCount + transientCaptureCount
        synchronizePendingReconciliationLoop()
    }

    private func synchronizePendingReconciliationLoop() {
        let policy = VoicePendingReconciliationPolicy()
        guard
            linkToInterviewArc,
            policy.delaySeconds(captures: pendingVoiceCaptures, attempt: 0) != nil
        else {
            pendingReconciliationGeneration = UUID()
            pendingReconciliationTask?.cancel()
            pendingReconciliationTask = nil
            return
        }
        guard pendingReconciliationTask == nil else { return }

        let generation = UUID()
        pendingReconciliationGeneration = generation
        pendingReconciliationTask = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                guard let self else { return }
                guard let delay = policy.delaySeconds(
                    captures: self.pendingVoiceCaptures,
                    attempt: attempt
                ) else { break }
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await self.retryPendingInBackground()
                attempt += 1
            }
            guard let self, self.pendingReconciliationGeneration == generation else { return }
            self.pendingReconciliationTask = nil
        }
    }

    func resolvePendingVoiceCapture(_ capture: PendingVoiceCapture, attach: Bool) {
        Task {
            do {
                if pipeline == nil { pipeline = try makeLinkedPipeline() }
                try await pipeline?.resolvePendingCapture(captureID: capture.id, attach: attach)
                if attach { _ = await pipeline?.retryPending() }
                await updateRetryCount()
            } catch {
                reportFailure(error, stage: .interviewArc, hasRecoverableAudio: true)
            }
        }
    }

    func deleteLegacyVoiceCapture(_ capture: LegacyVoiceCapture) {
        Task {
            do {
                if pipeline == nil { pipeline = try makeLinkedPipeline() }
                try await pipeline?.deleteLegacyVoiceCapture(clipID: capture.clipId)
                await updateRetryCount()
            } catch {
                reportFailure(error, stage: .interviewArc, hasRecoverableAudio: false)
            }
        }
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
            clearFailureAfterSuccess()
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
            if inserted {
                clearFailureAfterSuccess()
                phase = .delivered
            } else {
                reportFailure(
                    VoiceBridgeError.codexUnavailable("Click an editable text field, then try Insert again."),
                    stage: .insertion,
                    hasRecoverableAudio: hasLastAudio
                )
            }
        }
    }

    private func insertTranscript(_ transcript: String, editorText: String, showDeliveryStep: Bool) async -> Bool {
        lastTranscript = transcript
        lastInsertionText = editorText
        phase = .inserting
        if showDeliveryStep { deliveryStates[.insertion] = .working }
        let insertionStartedAt = Date()
        let output = await textInjector.deliver(text: editorText, targetPID: targetApplicationPID)
        currentInsertionDurationSeconds = Date().timeIntervalSince(insertionStartedAt)
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
            pendingCaptureStore: PendingVoiceCaptureStore(
                directory: recordingStore.pendingCapturesDirectory
            ),
            temporaryDirectory: recordingStore.temporaryDirectory,
            workspaceURL: URL(fileURLWithPath: workspacePath, isDirectory: true),
            interviewArcToken: token
        )
    }

    private func settlePhaseAfterContextRefresh(force: Bool) {
        guard force || phase == .setup || phase == .idle || phase == .refreshing else {
            return
        }
        if let failureNotice {
            phase = .failed(failureNotice.title)
            return
        }
        phase = hasGroqCredential ? .idle : .setup
    }

    private func currentInsertionTargetPID() -> pid_t? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           CaptureTargetApplicationPolicy.canReceiveDictation(
               bundleIdentifier: frontmost.bundleIdentifier
           ) {
            lastExternalApplicationPID = frontmost.processIdentifier
            return frontmost.processIdentifier
        }
        return lastExternalApplicationPID
    }

    private func retryPendingInBackground() async {
        guard linkToInterviewArc, !pendingRetryInFlight else { return }
        if pipeline == nil { pipeline = try? makeLinkedPipeline() }
        guard let pipeline else { return }
        pendingRetryInFlight = true
        defer { pendingRetryInFlight = false }
        let previousPhase = phase
        _ = await pipeline.retryPending()
        await updateRetryCount()
        if VoiceBackgroundPresentationPolicy.decision(
            foreground: foregroundPresentation(for: previousPhase),
            stateUnchangedDuringReconciliation: phase == previousPhase
        ) == .publishBackgroundStatus {
            phase = pendingRetryCount == 0 ? .idle : .queued
        }
    }

    private func foregroundPresentation(
        for phase: Phase
    ) -> VoiceForegroundPresentation {
        switch phase {
        case .idle, .delivered, .queued:
            return .idle
        case .recording:
            return .recording
        case .failed:
            return .failure
        case .setup, .refreshing, .preparingMicrophone, .transcribing, .sending, .inserting:
            return .processing
        }
    }

    private func handleUnexpectedRecorderTermination() {
        guard captureDestination != nil else { return }
        stopAndProcess(unexpectedTermination: true)
    }

    private func synchronizeFloatingPanelSize() {
        Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            FloatingPanelController.shared.setSize(
                width: self.floatingWidth,
                height: self.floatingHeight,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        }
    }

    private func endShortcutCapture() {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        shortcutCapturing = false
        registerGlobalShortcuts()
    }

    private func endLinkShortcutCapture() {
        if let linkShortcutMonitor {
            NSEvent.removeMonitor(linkShortcutMonitor)
        }
        linkShortcutMonitor = nil
        linkShortcutCapturing = false
        registerGlobalShortcuts()
    }

    private func suspendGlobalShortcuts() {
        hotKeyManager.unregister()
        linkHotKeyManager.unregister()
    }

    private func registerGlobalShortcuts() {
        hotKeyManager.register(shortcut) { [weak self] in
            self?.toggleRecording()
        }
        linkHotKeyManager.register(linkShortcut) { [weak self] in
            self?.toggleLinkMode()
        }
    }

    private func rememberLastAudio(
        _ recording: RecordedCapture,
        activityTitle: String? = nil
    ) {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingLastAudio = false
        isPlaybackExpanded = false
        playbackCurrentTime = 0
        lastAudioData = try? Data(contentsOf: recording.url, options: .mappedIfSafe)
        lastAudioURL = recording.url
        hasLastAudio = lastAudioData != nil
        lastAudioDuration = recording.duration
        playbackDuration = recording.duration
        lastMemoCreatedAt = Date()
        lastMemoActivityTitle = activityTitle
        lastTranscript = ""
        lastInsertionText = ""
    }

    private func clearLastMemo() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isPlayingLastAudio = false
        isPlaybackExpanded = false
        playbackCurrentTime = 0
        playbackDuration = 0
        lastAudioData = nil
        lastAudioURL = nil
        hasLastAudio = false
        lastAudioDuration = 0
        lastMemoActivityTitle = nil
        lastRetryDestination = nil
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

    private func recordingDiagnosticDetail(
        _ evidence: RecordingIntegrityEvidence
    ) -> String {
        let bitrate: Int
        if let audioBytes = evidence.encodedAudioBytes,
           evidence.decodedDurationSeconds > 0 {
            bitrate = Int(
                (Double(audioBytes) * 8 / evidence.decodedDurationSeconds).rounded()
            )
        } else {
            bitrate = 0
        }
        let reasons = RecordingIntegrityEvaluator.evaluate(evidence).reasons
            .map(\.rawValue)
            .joined(separator: ", ")
        let peak = evidence.peakPowerDecibels
            .map { String(format: "%.1f dB", $0) }
            ?? "unavailable"
        return "Input: \(recorder.inputDeviceName). Recorded \(clock(evidence.wallDurationSeconds)); decoded \(clock(evidence.decodedDurationSeconds)); peak \(peak); microphone payload \(bitrate) bps. Integrity signals: \(reasons.isEmpty ? "none" : reasons)."
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

    private var contextIsFreshForCapture: Bool {
        contextFreshnessPolicy.isFresh(lastVerifiedAt: contextLastVerifiedAt)
    }

    private func applyLateCaptureBinding(from refreshed: VoiceContextResponse) {
        guard linkToInterviewArc,
              captureStartedInCodex,
              case .general(let recordingStartedAt) = captureDestination,
              let activity = lateBindingPolicy.activity(
                initiallyLinkedActivityID: nil,
                recordingStartedAtMilliseconds: Int64(recordingStartedAt.timeIntervalSince1970 * 1_000),
                refreshedActivity: refreshed.focusedActivity
              ) else {
            return
        }
        captureDestination = .linked(activity, startedAt: recordingStartedAt)
    }
}

private struct VoiceSettingsWindow: View {
    @ObservedObject var model: VoiceBridgeModel

    var body: some View {
        Form {
            Section("Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Widget theme")
                        .font(.headline)
                    Text("Choose how the floating recorder looks. Its layout and controls stay the same.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 6) {
                        ForEach(VoiceWidgetTheme.allCases) { theme in
                            WidgetThemeRow(
                                theme: theme,
                                isSelected: model.widgetTheme == theme,
                                select: { model.selectWidgetTheme(theme) }
                            )
                        }
                    }
                    Text("Applies immediately and stays selected between launches.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Recording") {
                SecureField("Groq API key", text: $model.groqKeyDraft)
                    .textFieldStyle(.roundedBorder)
                Text("Required for Groq Whisper transcription. The key is stored only in macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(
                    "Silence protection",
                    selection: Binding(
                        get: { model.speechProtectionMode },
                        set: { mode in model.setSpeechProtectionMode(mode) }
                    )
                ) {
                    ForEach(SpeechProtectionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(speechProtectionDescription)
                    .font(.caption)
                    .foregroundStyle(
                        model.speechProtectionMode == .off
                            ? AnyShapeStyle(.orange)
                            : AnyShapeStyle(.secondary)
                    )
                Picker(
                    "Background audio",
                    selection: Binding(
                        get: { model.backgroundAudioMode },
                        set: { mode in model.setBackgroundAudioMode(mode) }
                    )
                ) {
                    ForEach(BackgroundAudioRecordingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                if model.backgroundAudioMode == .lower {
                    HStack {
                        Text("Recording level")
                        Slider(
                            value: Binding(
                                get: { model.backgroundAudioRelativeLevel },
                                set: { level in
                                    model.setBackgroundAudioRelativeLevel(level)
                                }
                            ),
                            in: 0.05...0.50,
                            step: 0.05
                        )
                        Text("\(Int(model.backgroundAudioRelativeLevel * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                Text("Uses the current output volume as the baseline, keeps the selected microphone, and restores only when you have not changed volume yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(
                    "Experimental dynamic recording interface",
                    isOn: Binding(
                        get: { model.dynamicRecordingInterfaceEnabled },
                        set: { enabled in
                            model.setDynamicRecordingInterfaceEnabled(enabled)
                        }
                    )
                )
                Text("Turns either compact or expanded Voice into the same focused recording capsule. Timers keep running out of view, and Stop restores the exact panel, picker, or finish drawer you left open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Interview Arc") {
                SecureField("Interview Arc token", text: $model.connectionTokenDraft)
                    .textFieldStyle(.roundedBorder)
                TextField("Interview Arc API", text: $model.apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                TextField("Interview Arc repository", text: $model.workspacePath)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Input") {
                HStack {
                    Text("Record or stop")
                    Spacer()
                    Button(model.shortcutCapturing ? "Press shortcut…" : model.shortcut.displayName) {
                        model.beginShortcutCapture()
                    }
                    .disabled(model.shortcutCapturing)
                    if model.shortcutCapturing {
                        Button("Cancel", action: model.cancelShortcutCapture)
                    }
                }
                HStack {
                    Text("Toggle Interview Arc link")
                    Spacer()
                    Button(
                        model.linkShortcutCapturing
                            ? "Press shortcut…"
                            : model.linkShortcut.displayName
                    ) {
                        model.beginLinkShortcutCapture()
                    }
                    .disabled(model.linkShortcutCapturing)
                    if model.linkShortcutCapturing {
                        Button("Cancel", action: model.cancelShortcutCapture)
                    }
                }
                if model.shortcutCapturing || model.linkShortcutCapturing {
                    Text("Press the new shortcut. Press Escape or choose Cancel to keep the current one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let shortcutMessage = model.shortcutMessage {
                    Text(shortcutMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if model.accessibilityNeeded {
                    Button("Enable Accessibility for insertion", action: model.requestAccessibilityPermission)
                } else {
                    Label("Direct insertion enabled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Section("Advanced") {
                TextField("Codex executable", text: $model.codexPath)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Diagnostics") {
                if model.diagnosticRecords.isEmpty {
                    Text("Timing details will appear after the next transcription.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.diagnosticRecords.prefix(5)) { record in
                        DisclosureGroup {
                            LabeledContent(
                                "Recording",
                                value: diagnosticDuration(record.recordingDurationSeconds)
                            )
                            LabeledContent(
                                "File finalization",
                                value: diagnosticDuration(record.fileFinalizationSeconds)
                            )
                            LabeledContent(
                                "Integrity inspection",
                                value: diagnosticDuration(record.integrityInspectionSeconds)
                            )
                            LabeledContent(
                                "Local speech scan",
                                value: diagnosticDuration(record.localSpeechScanSeconds)
                            )
                            LabeledContent(
                                "Upload and Groq",
                                value: diagnosticDuration(record.providerWaitSeconds)
                            )
                            LabeledContent(
                                "Response processing",
                                value: diagnosticDuration(record.responseProcessingSeconds)
                            )
                            LabeledContent(
                                "Segment validation",
                                value: diagnosticDuration(
                                    record.segmentValidationSeconds ?? 0
                                )
                            )
                            LabeledContent(
                                "Cursor insertion",
                                value: diagnosticDuration(record.insertionSeconds)
                            )
                            LabeledContent(
                                "Total",
                                value: diagnosticDuration(record.totalSeconds)
                            )
                            LabeledContent(
                                "Protection",
                                value: record.protectionMode.displayName
                            )
                            LabeledContent(
                                "Unsupported segments omitted",
                                value: "\(record.omittedUnsupportedSegmentCount)"
                            )
                            Button("Copy diagnostic report") {
                                model.copyDiagnostic(record)
                            }
                        } label: {
                            HStack {
                                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                                Spacer()
                                Text(record.outcome.rawValue.capitalized)
                                    .foregroundStyle(.secondary)
                                Text(diagnosticDuration(record.totalSeconds))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                HStack {
                    Button("Reveal diagnostic file", action: model.revealDiagnosticsFile)
                    Button("Clear diagnostics", role: .destructive, action: model.clearDiagnostics)
                        .disabled(model.diagnosticRecords.isEmpty)
                }
                Text("Stored locally with bounded retention. Diagnostics never include transcript text, audio, credentials, tokens, or private URLs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Save secure settings", action: model.saveSettings)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 620)
        .task {
            await model.refreshDiagnostics()
        }
    }

    private var speechProtectionDescription: String {
        switch model.speechProtectionMode {
        case .off:
            "Disables local no-speech checks. Silent audio may produce invented text."
        case .basic:
            "Rejects a complete recording when it contains no sustained speech."
        case .enhanced:
            "Also omits a returned segment only when local audio and Groq both identify its interval as non-speech."
        }
    }

    private func diagnosticDuration(_ seconds: Double) -> String {
        if seconds >= 1 {
            return String(format: "%.2f s", seconds)
        }
        return String(format: "%.0f ms", seconds * 1_000)
    }
}

private struct WidgetThemeRow: View {
    let theme: VoiceWidgetTheme
    let isSelected: Bool
    let select: () -> Void

    private var palette: VoiceWidgetPalette { .palette(for: theme) }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                WidgetThemePreview(palette: palette)
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(theme.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.teal : Color.secondary.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .frame(height: 58)
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? palette.teal.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(
                                isSelected
                                    ? palette.teal.opacity(0.78)
                                    : Color(nsColor: .separatorColor).opacity(0.45),
                                lineWidth: isSelected ? 1.2 : 0.7
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .voiceHoverFeedback(cornerRadius: 11, tint: palette.teal)
        .help("Use \(theme.displayName)")
        .accessibilityLabel("\(theme.displayName), \(theme.summary)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct WidgetThemePreview: View {
    let palette: VoiceWidgetPalette

    var body: some View {
        HStack(spacing: 4) {
            LinkStatusIcon(state: .linked, color: palette.teal, size: 10)
                .frame(width: 16, height: 18)
            Text("Course Schedule")
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Spacer(minLength: 2)
            HStack(spacing: 3) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 8, weight: .semibold))
                Text("12:48")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            }
            .foregroundStyle(palette.tealDark)
            .padding(.horizontal, 5)
            .frame(height: 22)
            .background(palette.timerSurface.opacity(palette.isDark ? 0.82 : 0.68))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Rectangle()
                .fill(palette.divider.opacity(0.75))
                .frame(width: 1, height: 16)
            Text("04:25:13")
                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(palette.tealDark)
            ZStack {
                Circle().fill(palette.glassHighlight.opacity(palette.isDark ? 0.15 : 0.58))
                Image(systemName: "mic.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.tealDark)
            }
            .frame(width: 23, height: 23)
            .overlay(Circle().stroke(palette.teal.opacity(0.66), lineWidth: 0.7))
            .shadow(color: palette.tealGlow.opacity(0.35), radius: 3)
        }
        .padding(.horizontal, 7)
        .frame(width: 255, height: 32)
        .background(
            ZStack {
                Capsule(style: .continuous).fill(palette.previewBackground.opacity(0.96))
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.glassHighlight.opacity(palette.isDark ? 0.34 : 0.62),
                                palette.glass.opacity(palette.isDark ? 0.92 : 0.76),
                                palette.timerSurface.opacity(palette.isDark ? 0.62 : 0.30),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Capsule(style: .continuous)
                    .stroke(palette.coolBorder.opacity(0.88), lineWidth: 0.8)
            }
        )
        .clipShape(Capsule(style: .continuous))
        .shadow(color: palette.coolShadow, radius: 4, y: 2)
        .accessibilityHidden(true)
    }
}

private struct VoiceBridgeMenu: View {
    @ObservedObject var model: VoiceBridgeModel
    @State private var showsAllCaptures = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader
            modeCard
            recordingControl
            if model.recorder.isRecording, model.recorder.signalHealth == .absent {
                microphoneSignalWarning
            }
            if model.isFailurePresented { failureCard }
            if model.sessionFinishResolutionRequested {
                SessionFinishResolverCard(model: model)
            }
            if model.showsDeliverySteps { deliveryProgress }
            if model.hasLastMemo { transcriptPreview }
            if !model.pendingVoiceCaptures.isEmpty { recentCapturesCard }
            if !model.legacyVoiceOrphans.isEmpty { legacyVoiceOrphansCard }
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
                Text(model.statusTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(model.statusSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
                    state: model.linkPresentationState,
                    color: model.linkStatusColor,
                    size: 14
                )
                Text(model.floatingTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var microphoneSignalWarning: some View {
        Label(
            "No microphone signal detected. Stop this capture, check the selected input, and record again.",
            systemImage: "waveform.slash"
        )
        .font(.caption)
        .foregroundStyle(Color(red: 0.65, green: 0.20, blue: 0.14))
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
    }

    private var failureCard: some View {
        Group {
            if let failure = model.failureNotice {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(red: 0.86, green: 0.30, blue: 0.20))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.title)
                                .font(.caption.weight(.bold))
                            Text(failure.message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(action: model.dismissFailure) {
                            Image(systemName: "xmark")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderless)
                        .voiceHoverFeedback(cornerRadius: 6)
                        .accessibilityLabel("Dismiss failure")
                    }
                    Text(failure.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    ForEach(failure.actions, id: \.self) { action in
                        Button {
                            model.performFailureAction(action)
                        } label: {
                            Label(failureActionLabel(action), systemImage: failureActionSymbol(action))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(action == failure.actions.first ? MenuFailureButtonStyle.primary : .secondary)
                        .voiceHoverFeedback(cornerRadius: 8, tint: .teal)
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func failureActionSymbol(_ action: VoiceFailureAction) -> String {
        switch action {
        case .recordAgain: "arrow.counterclockwise"
        case .retryTranscription, .retryConnection: "arrow.clockwise"
        case .playRecording: "play.fill"
        case .saveRecording: "square.and.arrow.down"
        case .insertAgain: "text.cursor"
        case .enableAccessibility: "hand.raised.fill"
        case .openSettings: "gearshape.fill"
        }
    }

    private func failureActionLabel(_ action: VoiceFailureAction) -> String {
        switch action {
        case .recordAgain: "Record again"
        case .retryTranscription: "Retry transcription"
        case .playRecording: "Play recording"
        case .saveRecording: "Save recording"
        case .insertAgain: "Insert transcript again"
        case .enableAccessibility: "Enable Accessibility"
        case .openSettings: "Open settings"
        case .retryConnection: "Retry Interview Arc connection"
        }
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
            enabled: model.isStartingRecording || model.isRecording || model.canRecord,
            cornerRadius: 10,
            tint: model.isRecording ? .red : .teal
        )
        .disabled(!model.isStartingRecording && !model.isRecording && !model.canRecord)
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

    private var recentCapturesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Recent Captures", systemImage: "waveform.badge.magnifyingglass")
                    .font(.caption.weight(.semibold))
                Spacer()
                if model.pendingVoiceCaptures.count > 3 {
                    Button(showsAllCaptures ? "Show less" : "Show all") {
                        showsAllCaptures.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(.semibold))
                }
            }
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(Array(model.pendingVoiceCaptures.reversed().prefix(
                        showsAllCaptures ? model.pendingVoiceCaptures.count : 3
                    ))) { capture in
                        captureRow(capture)
                    }
                }
            }
            .frame(maxHeight: showsAllCaptures ? 220 : 184)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func captureRow(_ capture: PendingVoiceCapture) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(capture.transcript)
                .font(.caption2)
                .lineLimit(2)
            HStack(spacing: 4) {
                Text(capture.activity.title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(captureStatus(capture))
                    .font(.caption2)
                    .foregroundStyle(capture.localState == .quarantinedConflict ? .red : .secondary)
            }
            HStack(spacing: 5) {
                captureAction("Insert Again", symbol: "text.cursor") {
                    model.insertPendingAgain(capture)
                }
                captureAction("Copy", symbol: "doc.on.doc") {
                    model.copyPendingCapture(capture)
                }
                Spacer()
                if capture.localState == .needsDecision {
                    Button("Delete") {
                        model.resolvePendingVoiceCapture(capture, attach: false)
                    }
                    .buttonStyle(.borderless)
                    Button("Attach") {
                        model.resolvePendingVoiceCapture(capture, attach: true)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
    }

    private func captureAction(
        _ label: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }

    private func captureStatus(_ capture: PendingVoiceCapture) -> String {
        switch capture.localState ?? .insertedRegistrationPending {
        case .insertedRegistrationPending:
            return capture.nextAttemptAt == nil ? "Syncing" : "Retry scheduled"
        case .waitingForSpecialist: return "Waiting for specialist"
        case .needsDecision: return "Needs decision"
        case .excludedGracePeriod: return "Excluded · expires in 24h"
        case .acceptedDelivering: return "Related · syncing"
        case .quarantinedConflict: return "Conflict · review required"
        case .complete: return "Complete"
        }
    }

    private var legacyVoiceOrphansCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Legacy captures to review", systemImage: "archivebox")
                .font(.caption.weight(.semibold))
            Text("These older accepted recordings have no following specialist reply. They remain in Past unless you delete them.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(model.legacyVoiceOrphans.prefix(3)) { capture in
                VStack(alignment: .leading, spacing: 6) {
                    Text(capture.excerpt)
                        .font(.caption2)
                        .lineLimit(2)
                    HStack {
                        Text(capture.durationSeconds.map { "\($0)s" } ?? "Recorded answer")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Delete") {
                            model.deleteLegacyVoiceCapture(capture)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
            if model.legacyVoiceOrphans.count > 3 {
                Text("\(model.legacyVoiceOrphans.count - 3) more remain available after this review batch.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private var settings: some View {
        ForegroundSettingsLink {
            HStack {
                Label("Settings", systemImage: "gearshape")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .voiceHoverFeedback(cornerRadius: 8, tint: .teal)
        .help("Open Interview Arc Voice settings")
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

private struct MenuFailureButtonStyle: ButtonStyle {
    let prominent: Bool

    static let primary = MenuFailureButtonStyle(prominent: true)
    static let secondary = MenuFailureButtonStyle(prominent: false)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : Color(red: 0.08, green: 0.38, blue: 0.34))
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        prominent
                            ? Color(red: 0.08, green: 0.44, blue: 0.39)
                            : Color(red: 0.82, green: 0.92, blue: 0.90)
                    )
            )
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct RecordingClock: View {
    @ObservedObject var recorder: AnswerRecorder
    var compact = false
    var foregroundColor: Color = .primary

    var body: some View {
        Text(clock(recorder.elapsedSeconds))
            .font(.system(size: compact ? 10 : 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(foregroundColor)
            .frame(minWidth: compact ? 32 : 58)
            .accessibilityLabel("Recording time \(clock(recorder.elapsedSeconds))")
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
