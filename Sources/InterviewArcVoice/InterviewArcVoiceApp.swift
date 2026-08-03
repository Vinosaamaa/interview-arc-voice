import AppKit
import AVFoundation
import Carbon
import CryptoKit
import os
import SwiftUI
import UniformTypeIdentifiers
import InterviewArcVoiceCore

private let voiceBridgeLogger = Logger(
    subsystem: "app.interviewarc.voice",
    category: "VoiceBridge"
)

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

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
        .windowResizability(.contentSize)

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
        let microphoneRecoveryCount: Int
        let vadSpeechFrameCount: Int?
        let vadLongestSpeechRunFrames: Int?
        var captureTargetKind: CaptureTargetKind? = nil
        var captureRouteReason: CaptureRouteReason? = nil
    }

    private struct TranscriptionDiagnosticMetadata {
        var timing: TranscriptionTiming? = nil
        var segmentValidationSeconds = 0.0
        var omittedUnsupportedSegmentCount = 0
        var omittedUnsupportedWordCount: Int?
        var wordAlignmentComplete: Bool?
        var evaluatedSegmentCount: Int?
        var wordTimestampCount: Int?
        var providerRetryOccurred: Bool?
        var lexicalCoverageEndSeconds: Double?
        var trailingSpeechLikeFrameCount: Int?
        var trailingSpeechLikeFraction: Double?
        var integrityReasons: [TranscriptionIntegrityReason]?
        var engine: String?
        var model: String?
        var localInferenceSeconds: Double?
        var localPromptTokenCount: Int?
        var localFallbackAttempted: Bool?
        var localValidationReasons: [TranscriptionIntegrityReason]?
    }

    @Published var phase: Phase = .setup
    @Published var context: VoiceContextResponse?
    @Published private(set) var timerInstrument: VoiceTimerInstrument?
    @Published private(set) var timerMutationInFlight = false
    @Published private(set) var timerMutationMessage: String?
    @Published var timerPanelExpanded = false
    @Published var plannerPresented = false
    @Published var planningState = VoicePlanningPresentationState()
    @Published private(set) var planningResponse: VoicePlanningResponse?
    @Published private(set) var planningLoading = false
    @Published private(set) var planningMutationInFlight = false
    @Published private(set) var planningMutationStatus: String?
    @Published var planningMessage: String?
    @Published var planningDestination = "standalone"
    @Published var planningCustomPresented = false
    @Published var planningCustomTitle = ""
    @Published var planningCustomURL = ""
    @Published var planningCustomPrompt = ""
    @Published var planningCustomMinutes = 40
    @Published var planningFullCoding = VoicePlanningFullSessionPolicy.defaultCodingCount
    @Published var planningFullSystemDesign = VoicePlanningFullSessionPolicy.defaultSystemDesignCount
    @Published var planningFullBehavioral = VoicePlanningFullSessionPolicy.defaultBehavioralCount
    @Published var miniSessionTimerExpanded = false
    @Published var activityPickerExpanded = false
    @Published private(set) var finishingActivityID: String?
    @Published var sessionFinishResolutionRequested = false
    @Published var finishOutcome: VoicePracticeOutcome?
    @Published var finishStarred = false
    @Published var contextMessage = "Loading secure settings…"
    @Published var lastTranscript = ""
    @Published private(set) var transcriptHistory: [LocalTranscriptRecord] = []
    @Published private(set) var selectedTranscriptIndex = 0
    @Published private(set) var recoveryPromotionInFlightID: UUID?
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
    @Published var widgetSizeMode: VoiceWidgetSizeMode
    @Published var backgroundAudioMode: BackgroundAudioRecordingMode
    @Published var backgroundAudioRelativeLevel: Double
    @Published var dynamicRecordingInterfaceEnabled: Bool
    @Published var speechProtectionMode: SpeechProtectionMode
    @Published private(set) var diagnosticRecords: [VoiceDiagnosticRecord] = []
    @Published private(set) var diagnosticRetryInFlightID: UUID?
    @Published private(set) var diagnosticRetryMessage: String?
    @Published private(set) var localWhisperModel = LocalWhisperModelSnapshot(
        state: .notInstalled,
        model: LocalWhisperModelManager.defaultModel
    )
    @Published private(set) var localWhisperModelOperationInFlight = false
    @Published private(set) var localWhisperModelMessage: String?
    @Published private(set) var dynamicRecordingInterfaceActive = false

    var workbenchVoiceCaptures: [PendingVoiceCapture] {
        let workbenchID = timerInstrument?.workbenchId
        let currentActivityIDs = Set(timerInstrument?.activities.map(\.id) ?? [])
        return pendingVoiceCaptures.filter { capture in
            VoiceCaptureLifecyclePolicy().belongsToCurrentWorkbench(
                capture,
                workbenchID: workbenchID,
                currentActivityIDs: currentActivityIDs
            )
        }
    }
    @Published var shortcut: HotKeyShortcut
    @Published var shortcutCapturing = false
    @Published var linkShortcut: HotKeyShortcut
    @Published var linkShortcutCapturing = false
    @Published var widgetSizeShortcut: HotKeyShortcut
    @Published var widgetSizeShortcutCapturing = false
    @Published var plannerShortcut: HotKeyShortcut
    @Published var plannerShortcutCapturing = false
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
    @Published private(set) var groqCredentialRejected = false
    @Published private(set) var currentTargetDecision =
        CaptureTargetApplicationPolicy.decision(for: nil)
    @Published var failureDetailsPresented = false
    private var pendingFailurePopoverActionTask: Task<Void, Never>?
    private var pendingFailurePopoverCloseObserver: NSObjectProtocol?
    private var pendingRetryInFlight = false
    private lazy var generalDictationPrompt: String = {
        (try? VocabularyCatalog.bundled().generalDictationPrompt()) ?? "LeetCode"
    }()

    let recorder = AnswerRecorder()

    private let keychain = KeychainStore()
    private let routeEvaluationPolicy = CaptureRouteEvaluationPolicy()
    private let contextRetentionPolicy = VoiceContextRetentionPolicy()
    private let contextFreshnessPolicy = CaptureContextFreshnessPolicy()
    private let lateBindingPolicy = LateCaptureBindingPolicy()
    private let playbackCompletionPolicy = PlaybackCompletionPolicy()
    private let compactPresentationPolicy = CompactVoicePresentationPolicy()
    private let hotKeyManager = GlobalHotKeyManager(identifierID: 1)
    private let linkHotKeyManager = GlobalHotKeyManager(identifierID: 2)
    private let widgetSizeHotKeyManager = GlobalHotKeyManager(identifierID: 3)
    private let plannerHotKeyManager = GlobalHotKeyManager(identifierID: 4)
    private let textInjector = DictationTextInjector()
    private let outputVolumeController = SystemOutputVolumeController()
    private var recordingStore: RecordingStore?
    private var diagnosticsStore: VoiceDiagnosticsStore?
    private var transcriptHistoryStore: LocalTranscriptHistoryStore?
    private var recoverableRecordingStore: LocalRecoverableRecordingStore?
    private var localWhisperModelManager: LocalWhisperModelManager?
    private var localWhisperTranscriber: ManagedLocalWhisperTranscriber?
    private var pipeline: VoicePipeline?
    private var captureDestination: CaptureDestination?
    private var captureStartedInCodex = false
    private var captureRouteReason = CaptureRouteReason.linkDisabled
    private var captureGeneration = UUID()
    private var targetApplicationPID: pid_t?
    private var lastInsertionText = ""
    private var shortcutMonitor: Any?
    private var linkShortcutMonitor: Any?
    private var widgetSizeShortcutMonitor: Any?
    private var plannerShortcutMonitor: Any?
    private var lastInsertionSucceeded = false
    private var contextPollTask: Task<Void, Never>?
    private var pendingReconciliationTask: Task<Void, Never>?
    private var transcriptHistoryExpiryTask: Task<Void, Never>?
    private var transcriptHistoryRefreshRetryTask: Task<Void, Never>?
    private var pendingReconciliationGeneration = UUID()
    private var lastLiveRevision = 0
    private var contextRefreshRequestID = 0
    private var contextLastVerifiedAt: Date?
    private var timerInstrumentReceivedAt = Date()
    private var wakeObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var lastExternalApplicationPID: pid_t?
    private var rejectedGroqCredential: String?
    private var rejectedGroqCredentialFingerprint: String?
    private var lastAudioData: Data?
    private var lastAudioURL: URL?
    private var lastAudioDuration: TimeInterval = 0
    private var lastCoverageRecoveryRecordID: UUID?
    private var lastMemoCreatedAt = Date()
    private var lastMemoActivityTitle: String?
    private var lastRetryDestination: CaptureDestination?
    private var audioPlayer: AVAudioPlayer?
    private var playbackTranscriptID: UUID?
    private var playbackTimer: Timer?
    private var processingTimer: Timer?
    private var processingIndicatorTask: Task<Void, Never>?
    private var disclosureStateBeforeRecording: FloatingWidgetDisclosureState?
    private var plannerPresentedBeforeRecording: Bool?
    private var timerPanelExpandedBeforePlanner: Bool?
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
        hasGroqCredential
            && !groqCredentialRejected
            && !isBusy
            && !isStartingRecording
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
    var availableFailureActions: [VoiceFailureAction] {
        RecoveryActionAvailabilityPolicy.availableActions(
            from: failureNotice?.actions ?? [],
            hasRecoverableAudio: hasLastAudio
        )
    }
    var hasMenuTranscript: Bool { !transcriptHistory.isEmpty }
    var selectedTranscript: LocalTranscriptRecord? {
        guard transcriptHistory.indices.contains(selectedTranscriptIndex) else {
            return nil
        }
        return transcriptHistory[selectedTranscriptIndex]
    }
    var selectedTranscriptDetails: String {
        guard let selectedTranscript else { return "0 words · 00:00" }
        return "\(selectedTranscript.wordCount) words · \(clock(selectedTranscript.durationSeconds))"
    }
    var selectedTranscriptWordCountLabel: String {
        "\(selectedTranscript?.wordCount ?? 0) words"
    }
    var selectedTranscriptDurationLabel: String {
        clock(selectedTranscript?.durationSeconds ?? 0)
    }
    var selectedTranscriptPosition: String {
        guard !transcriptHistory.isEmpty else { return "0 of 0" }
        return "\(selectedTranscriptIndex + 1) of \(transcriptHistory.count)"
    }
    var canSelectNewerTranscript: Bool { selectedTranscriptIndex > 0 }
    var canSelectOlderTranscript: Bool {
        selectedTranscriptIndex + 1 < transcriptHistory.count
    }
    var selectedTranscriptOwnsAudio: Bool {
        selectedTranscript?.audioReference != nil
    }
    var selectedTranscriptCanRetry: Bool {
        selectedTranscriptIndex == 0
            && hasLastAudio
            && selectedTranscript?.transcript == lastTranscript
    }
    var selectedTranscriptCanUseRecovery: Bool {
        RecoveryTranscriptPromotionPolicy.canUse(
            recoveryStatus: selectedTranscript?.recoveryStatus,
            hasRetainedAudio: selectedTranscriptOwnsAudio,
            promotionInFlight: recoveryPromotionInFlightID != nil
        )
    }
    var failureRecoveryTranscriptCanBeUsed: Bool {
        guard let recordID = failureNotice?.recoveryTranscriptRecordID,
              let record = transcriptHistory.first(where: {
                  $0.id == recordID
              }) else {
            return false
        }
        return RecoveryTranscriptPromotionPolicy.canUse(
            recoveryStatus: record.recoveryStatus,
            hasRetainedAudio: record.audioReference != nil,
            promotionInFlight: recoveryPromotionInFlightID != nil
        )
    }
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
        if plannerPresented {
            return FloatingWidgetWindowPolicy.plannerWidth
        }
        if widgetSizeMode == .mini {
            return MiniWidgetPresentationPolicy.width(for: miniWidgetLayout)
        }
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
        if plannerPresented {
            return FloatingWidgetWindowPolicy.plannerHostHeight
        }
        if widgetSizeMode == .mini {
            return FloatingWidgetWindowPolicy.hostHeight
        }
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
    var miniWidgetLayout: MiniWidgetLayout {
        MiniWidgetPresentationPolicy.layout(
            linkEnabled: linkToInterviewArc,
            hasActivityTimer: timerInstrument?.activity?.timer != nil,
            hasSessionTimer: timerInstrument?.session?.timer != nil,
            recordingActive: isStartingRecording || isRecording,
            sessionTimerDisclosed: miniSessionTimerExpanded
        )
    }
    var canExpandMiniSessionTimer: Bool {
        MiniWidgetPresentationPolicy.canDiscloseSessionTimer(
            hasActivityTimer: timerInstrument?.activity?.timer != nil,
            hasSessionTimer: timerInstrument?.session?.timer != nil
        )
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

    var activePlanningQuery: VoicePlanningQuery {
        planningState.query(for: planningState.selectedSpecialty)
    }

    var planningSelectionCount: Int {
        planningState.selections.count
    }

    var planningTotalMinutes: Int {
        planningState.totalSelectedMinutes
    }

    var planningFullSessionMinutes: Int {
        VoicePlanningFullSessionPolicy.totalMinutes(
            coding: planningFullCoding,
            systemDesign: planningFullSystemDesign,
            behavioral: planningFullBehavioral
        )
    }

    func planningAttentionCount(_ attention: VoicePlanningAttention) -> Int {
        planningResponse?.catalog.attentionCounts?[attention.rawValue] ?? 0
    }

    func planningDifficultyCount(_ difficulty: VoicePlanningDifficulty) -> Int {
        planningResponse?.catalog.difficultyCounts?[difficulty.rawValue] ?? 0
    }

    func planningActivityStatus(
        id: String,
        declaredStatus: String? = nil
    ) -> VoicePlanningCurrentStatus {
        guard let timer = timerInstrument?.activities.first(where: { $0.id == id })?.timer else {
            return declaredStatus == "completed" ? .completed : .upcoming
        }
        if timer.completed { return .completed }
        if timer.isRunning { return .running }
        return timer.startedAt == nil ? .upcoming : .paused
    }

    func planningSessionStatus(id: String) -> VoicePlanningCurrentStatus {
        guard timerInstrument?.session?.id == id,
              let timer = timerInstrument?.session?.timer else {
            return .upcoming
        }
        if timer.completed { return .completed }
        if timer.isRunning { return .running }
        return timer.startedAt == nil ? .upcoming : .paused
    }

    func planningActivityTime(id: String, at now: Date) -> String? {
        guard let instrument = timerInstrument,
              let timer = instrument.activities.first(where: { $0.id == id })?.timer else {
            return nil
        }
        return compactClock(
            timer.elapsedSeconds(
                serverNow: instrument.serverNow,
                receivedAt: timerInstrumentReceivedAt,
                now: now
            )
        )
    }

    func canTogglePlanningActivityTimer(
        id: String,
        status: VoicePlanningCurrentStatus
    ) -> Bool {
        let runningID = timerInstrument?.activities.first(where: {
            $0.timer?.isRunning == true
        })?.id
        return VoicePlanningTimerControlPolicy.isEnabled(
            subjectID: id,
            status: status,
            runningSubjectID: runningID,
            mutationInFlight: timerMutationInFlight
        )
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

    func miniTimerText(at now: Date) -> String? {
        switch MiniWidgetPresentationPolicy.timerSource(
            hasActivityTimer: timerInstrument?.activity?.timer != nil,
            hasSessionTimer: timerInstrument?.session?.timer != nil
        ) {
        case .activity:
            return compactActivityTime(at: now)
        case .session:
            return compactSessionTime(at: now)
        case nil:
            return nil
        }
    }

    func toggleMiniSessionTimer() {
        guard canExpandMiniSessionTimer else { return }
        miniSessionTimerExpanded.toggle()
    }
    private var compactLinkPresentation: CompactVoicePresentation {
        compactPresentationPolicy.presentation(
            linkEnabled: linkToInterviewArc,
            activeActivityTitle: currentTargetDecision.canAttach
                ? context?.focusedActivity?.title
                : nil,
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
        workspacePath = defaults.string(forKey: "voice.workspacePath")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Projects/Interview Prep/interview-arc")
                .path
        codexPath = defaults.string(forKey: "voice.codexPath") ?? "/Applications/ChatGPT.app/Contents/Resources/codex"
        linkToInterviewArc = defaults.object(forKey: "voice.linkToInterviewArc") as? Bool ?? true
        widgetTheme = VoiceWidgetTheme.load(from: defaults)
        widgetSizeMode = VoiceWidgetSizeMode.load(from: defaults)
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
        let resolvedWidgetSizeShortcut: HotKeyShortcut
        if let data = defaults.data(forKey: "voice.widgetSizeShortcut"),
           let saved = try? JSONDecoder().decode(HotKeyShortcut.self, from: data),
           saved != resolvedShortcut,
           saved != resolvedLinkShortcut {
            resolvedWidgetSizeShortcut = saved
        } else {
            resolvedWidgetSizeShortcut = .widgetSizeToggle
        }
        widgetSizeShortcut = resolvedWidgetSizeShortcut
        if resolvedWidgetSizeShortcut == .widgetSizeToggle,
           let data = try? JSONEncoder().encode(resolvedWidgetSizeShortcut) {
            defaults.set(data, forKey: "voice.widgetSizeShortcut")
        }
        let resolvedPlannerShortcut: HotKeyShortcut
        if let data = defaults.data(forKey: "voice.plannerShortcut"),
           let saved = try? JSONDecoder().decode(HotKeyShortcut.self, from: data),
           saved != resolvedShortcut,
           saved != resolvedLinkShortcut,
           saved != resolvedWidgetSizeShortcut {
            resolvedPlannerShortcut = saved
        } else {
            resolvedPlannerShortcut = .plannerToggle
        }
        plannerShortcut = resolvedPlannerShortcut
        if resolvedPlannerShortcut == .plannerToggle,
           let data = try? JSONEncoder().encode(resolvedPlannerShortcut) {
            defaults.set(data, forKey: "voice.plannerShortcut")
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
            transcriptHistoryStore = try? LocalTranscriptHistoryStore(
                directory: recordingStore.transcriptHistoryDirectory,
                audioDirectory: recordingStore.recentHistoryDirectory
            )
            recoverableRecordingStore = try? LocalRecoverableRecordingStore(
                directory: recordingStore.recoveryDirectory
            )
            if let manager = try? LocalWhisperModelManager(
                rootDirectory: recordingStore.localModelsDirectory
            ) {
                localWhisperModelManager = manager
                localWhisperTranscriber = ManagedLocalWhisperTranscriber(
                    manager: manager
                )
            }
        }
        groqCredentialRejected = defaults.bool(
            forKey: "voice.groqCredentialRejected"
        )
        rejectedGroqCredentialFingerprint = defaults.string(
            forKey: "voice.rejectedGroqCredentialFingerprint"
        )
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           CaptureTargetApplicationPolicy.canReceiveDictation(
               bundleIdentifier: frontmost.bundleIdentifier
           ) {
            rememberExternalApplication(frontmost)
        }
        recorder.onUnexpectedTermination = { [weak self] in
            self?.handleUnexpectedRecorderTermination()
        }

        // Present visible UI before touching Keychain. A credential prompt or
        // error must never make this agent-style app appear to launch and quit.
        Task {
            await Task.yield()
            FloatingPanelController.shared.show(model: self)
            // Recent Transcripts is local state. Load it before Keychain,
            // network context, pending reconciliation, or live updates so a
            // cold launch never presents an empty history while remote startup
            // work is slow.
            await refreshTranscriptHistory()
            outputVolumeController.recoverInterruptedSessionIfNeeded()
            registerGlobalShortcuts()
            restoreRecoverableRecordingIfNeeded()
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
                self?.rememberExternalApplication(application)
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
            if plannerPresented {
                plannerPresented = false
                timerPanelExpanded = true
                timerPanelExpandedBeforePlanner = nil
                synchronizeFloatingPanelSize()
                return
            }
            timerPanelExpanded.toggle()
            if !timerPanelExpanded {
                cancelFinishDrawer()
                activityPickerExpanded = false
            }
        }
        synchronizeFloatingPanelSize()
    }

    func togglePlanner() {
        guard linkToInterviewArc, !isRecording, !isStartingRecording else { return }
        withAnimation(.easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds)) {
            if plannerPresented {
                plannerPresented = false
                timerPanelExpanded = timerPanelExpandedBeforePlanner ?? false
                timerPanelExpandedBeforePlanner = nil
            } else {
                timerPanelExpandedBeforePlanner = timerPanelExpanded
                plannerPresented = true
                timerPanelExpanded = false
                finishingActivityID = nil
                activityPickerExpanded = false
                sessionFinishResolutionRequested = false
            }
        }
        synchronizeFloatingPanelSize()
        if plannerPresented {
            Task { await refreshPlanning() }
        }
    }

    func showPlanner() {
        if !plannerPresented { togglePlanner() }
    }

    func showFocusSurface() {
        guard hasTimerInstrument else { return }
        withAnimation(.easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds)) {
            plannerPresented = false
            timerPanelExpanded = true
            timerPanelExpandedBeforePlanner = nil
        }
        synchronizeFloatingPanelSize()
    }

    func setPlanningSurface(_ surface: VoicePlanningSurface) {
        planningState.surface = surface
    }

    func setPlanningSpecialty(_ specialty: VoicePlanningSpecialty) {
        planningState.selectedCategory = VoicePlanningCategory(
            rawValue: specialty.rawValue
        ) ?? .leetcode
        planningState.selectedSpecialty = specialty
        Task { await refreshPlanning() }
    }

    func setPlanningCategory(_ category: VoicePlanningCategory) {
        planningState.selectedCategory = category
        guard let specialty = category.specialty else { return }
        planningState.selectedSpecialty = specialty
        Task { await refreshPlanning() }
    }

    func planningCatalogScrollAnchor(
        for specialty: VoicePlanningSpecialty
    ) -> String? {
        planningState.catalogScrollAnchor(for: specialty)
    }

    func updatePlanningCatalogScrollAnchor(
        _ itemID: String?,
        for specialty: VoicePlanningSpecialty
    ) {
        planningState.updateCatalogScrollAnchor(itemID, for: specialty)
    }

    func updatePlanningQuery(_ transform: (inout VoicePlanningQuery) -> Void) {
        var query = activePlanningQuery
        transform(&query)
        planningState.updateQuery(query, for: planningState.selectedSpecialty)
    }

    func applyPlanningQuery() {
        Task { await refreshPlanning() }
    }

    func togglePlanningSelection(_ item: VoicePlanningCatalogItem) {
        guard item.eligible else { return }
        planningState.toggleSelection(
            .practice(
                specialty: planningState.selectedSpecialty,
                questionID: item.id,
                title: item.title,
                minutes: item.targetMinutes,
                url: item.url,
                prompt: item.prompt,
                topics: item.topics ?? []
            )
        )
    }

    func addJobApplicationsSelection() {
        planningState.toggleSelection(
            .focus(
                title: "Job applications",
                minutes: VoicePlanningCareerPolicy.jobApplicationMinutes,
                note: nil
            )
        )
    }

    func addCustomPlanningSelection() {
        let title = planningCustomTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        planningState.toggleSelection(
            .practice(
                specialty: planningState.selectedSpecialty,
                questionID: nil,
                title: title,
                minutes: max(1, planningCustomMinutes),
                url: planningCustomURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                prompt: planningCustomPrompt.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                topics: []
            )
        )
        planningCustomTitle = ""
        planningCustomURL = ""
        planningCustomPrompt = ""
        planningCustomPresented = false
    }

    func removePlanningSelection(_ id: String) {
        planningState.removeSelection(id: id)
    }

    func submitPlanningSelection() {
        guard !planningState.selections.isEmpty,
              let workbenchID = planningResponse?.workbench?.id else { return }
        let request = VoicePlanningMutationRequest(
            type: "add_selection",
            workbenchId: workbenchID,
            destination: planningDestination,
            selections: planningState.selections.map(VoicePlanningSelectionPayload.init)
        )
        Task { await performPlanningMutation(request, clearSelection: true) }
    }

    func createPlanningFullSession() {
        guard let workbenchID = planningResponse?.workbench?.id else { return }
        let request = VoicePlanningMutationRequest(
            type: "create_full_session",
            workbenchId: workbenchID,
            coding: planningFullCoding,
            systemDesign: planningFullSystemDesign,
            behavioral: planningFullBehavioral
        )
        Task { await performPlanningMutation(request) }
    }

    func startFreshPlanningDay() {
        guard let workbenchID = planningResponse?.workbench?.id else { return }
        let date = planningResponse?.date ?? ""
        let request = VoicePlanningMutationRequest(
            type: "start_fresh_today",
            workbenchId: workbenchID,
            newWorkbenchId: "workbench-\(date)-\(UUID().uuidString.lowercased())"
        )
        Task { await performPlanningMutation(request) }
    }

    func togglePlanningStar(_ item: VoicePlanningCatalogItem) {
        guard let workbenchID = planningResponse?.workbench?.id else { return }
        let request = VoicePlanningMutationRequest(
            type: "problem_star",
            workbenchId: workbenchID,
            specialty: planningState.selectedSpecialty,
            questionId: item.id,
            starred: !item.starred
        )
        Task { await performPlanningMutation(request) }
    }

    func removePlanningItem(kind: String, id: String) {
        guard let workbenchID = planningResponse?.workbench?.id else { return }
        let request = VoicePlanningMutationRequest(
            type: "remove",
            workbenchId: workbenchID,
            kind: kind,
            id: id
        )
        Task { await performPlanningMutation(request) }
    }

    func refreshPlanning(clearMessage: Bool = true) async {
        guard plannerPresented else { return }
        planningLoading = true
        if clearMessage { planningMessage = nil }
        defer { planningLoading = false }
        do {
            let client = try timerAPIClient()
            planningResponse = try await client.planning(
                specialty: planningState.selectedSpecialty,
                query: activePlanningQuery,
                pageSize: 60
            )
        } catch {
            planningMessage = error.localizedDescription
        }
    }

    private func performPlanningMutation(
        _ request: VoicePlanningMutationRequest,
        clearSelection: Bool = false
    ) async {
        planningMutationInFlight = true
        planningMutationStatus = planningMutationStatus(for: request)
        planningMessage = planningMutationStatus
        do {
            let response = try await timerAPIClient().mutatePlanning(request)
            guard response.protocolVersion == 1 else {
                throw VoiceBridgeError.protocolMismatch(response.protocolVersion)
            }
            if clearSelection {
                planningState.clearSelections()
            }
            if let authoritative = response.authoritative,
               let current = planningResponse {
                planningResponse = current.applying(authoritative)
            }
            planningMessage = response.duplicate == true
                ? "Already applied."
                : planningMutationCompletionMessage(for: request)
            planningMutationInFlight = false
            planningMutationStatus = nil
            reconcilePlanningAfterMutation()
        } catch {
            planningMessage = error.localizedDescription
            await refreshPlanning(clearMessage: false)
            planningMutationInFlight = false
            planningMutationStatus = nil
        }
    }

    private func reconcilePlanningAfterMutation() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            async let planningRefresh: Void = refreshPlanning(clearMessage: false)
            async let contextRefresh: Void = refreshContext(showProgress: false)
            _ = await (planningRefresh, contextRefresh)
        }
    }

    private func planningMutationStatus(
        for request: VoicePlanningMutationRequest
    ) -> String {
        switch request.type {
        case "create_full_session": "Creating full session…"
        case "remove": request.kind == "session" ? "Deleting session…" : "Removing item…"
        case "start_fresh_today": "Starting fresh Today…"
        case "problem_star": "Updating favorite…"
        default: "Adding to Today…"
        }
    }

    private func planningMutationCompletionMessage(
        for request: VoicePlanningMutationRequest
    ) -> String {
        switch request.type {
        case "create_full_session": "Full session created."
        case "remove": request.kind == "session" ? "Session deleted." : "Item removed."
        case "start_fresh_today": "Today is fresh."
        case "problem_star": "Favorite updated."
        default: "Added to Today."
        }
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

    func togglePlanningActivityTimer(id: String, status: VoicePlanningCurrentStatus) {
        guard !timerMutationInFlight, status != .completed else { return }
        let action = status == .running ? "pause" : "start"
        Task {
            let succeeded = await runTimerMutation {
                try await self.timerAPIClient().mutateTimer(
                    subjectID: id,
                    kind: "activity",
                    action: action
                )
            }
            if succeeded {
                await refreshPlanning(clearMessage: false)
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

    func copySelectedTranscript() {
        guard let selectedTranscript else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedTranscript.editorText, forType: .string)
        contextMessage = selectedTranscript.editorText == selectedTranscript.transcript
            ? "Transcript copied."
            : "Transcript and Voice v2 envelope copied."
    }

    func selectNewerTranscript() {
        guard canSelectNewerTranscript else { return }
        stopLastAudioPlayback()
        selectedTranscriptIndex -= 1
    }

    func selectOlderTranscript() {
        guard canSelectOlderTranscript else { return }
        stopLastAudioPlayback()
        selectedTranscriptIndex += 1
    }

    func insertSelectedTranscriptFromMenu(
        dismissMenu: @escaping @MainActor () -> Void
    ) {
        guard let selectedTranscript else { return }
        let targetPID = manualInsertionTargetPID(surface: .menuBar)
        let menuWindow = NSApp.keyWindow
        dismissMenu()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await waitForMenuDismissal(menuWindow)
            targetApplicationPID = targetPID
            let inserted = await insertTranscript(
                selectedTranscript.transcript,
                editorText: selectedTranscript.editorText,
                showDeliveryStep: selectedTranscript.editorText
                    != selectedTranscript.transcript
            )
            switch CaptureActionPolicy.insertionCompletion(inserted: inserted) {
            case .delivered:
                clearFailureAfterSuccess()
                phase = .delivered
                contextMessage = "Transcript inserted again."
            case .needsAttention:
                reportFailure(
                    VoiceBridgeError.codexUnavailable(
                        "Focus an editable text field, then try Insert again."
                    ),
                    stage: .insertion,
                    hasRecoverableAudio: selectedTranscriptOwnsAudio
                )
            }
        }
    }

    func useSelectedRecoveryTranscriptFromMenu(
        dismissMenu: @escaping @MainActor () -> Void
    ) {
        guard let recordID = selectedTranscript?.id else { return }
        let targetPID = manualInsertionTargetPID(surface: .menuBar)
        let menuWindow = NSApp.keyWindow
        promoteRecoveryTranscript(
            recordID: recordID,
            targetPID: targetPID
        ) {
            dismissMenu()
            await self.waitForMenuDismissal(menuWindow)
        }
    }

    func useFailureRecoveryTranscriptFromFloatingWidget() {
        guard let recordID = failureNotice?.recoveryTranscriptRecordID else {
            return
        }
        promoteRecoveryTranscript(
            recordID: recordID,
            targetPID: manualInsertionTargetPID(surface: .floatingWidget)
        ) {}
    }

    private func promoteRecoveryTranscript(
        recordID: UUID,
        targetPID: pid_t?,
        beforeInsertion: @escaping @MainActor () async -> Void
    ) {
        guard let selectedTranscript = transcriptHistory.first(where: {
                  $0.id == recordID
              }),
              selectedTranscript.recoveryStatus == .coverageUncertain,
              selectedTranscript.audioReference != nil,
              let transcriptHistoryStore,
              recoveryPromotionInFlightID == nil else {
            return
        }
        recoveryPromotionInFlightID = selectedTranscript.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { recoveryPromotionInFlightID = nil }
            guard let audioURL = await transcriptHistoryStore.audioURL(
                for: selectedTranscript
            ) else {
                reportFailure(
                    VoiceBridgeError.recordingUnavailable,
                    stage: .transcription,
                    hasRecoverableAudio: false
                )
                return
            }

            do {
                let editorText: String
                let captureID: String?
                if let linkedContext = selectedTranscript.linkedRecoveryContext {
                    guard recoveryActivityIsEligible(
                        linkedContext.activity.activityId
                    ) else {
                        throw VoiceBridgeError.invalidResponse(
                            409,
                            "The original Interview Arc activity is no longer active. Keep this transcript local or start a new recording for the current activity."
                        )
                    }
                    if pipeline == nil { pipeline = try makeLinkedPipeline() }
                    guard let pipeline else {
                        throw VoiceBridgeError.recordingUnavailable
                    }
                    let envelope = try await pipeline.promoteRecoveryTranscript(
                        record: selectedTranscript,
                        audioURL: audioURL
                    )
                    editorText = envelope.editorText
                    captureID = envelope.captureID
                } else {
                    editorText = selectedTranscript.transcript
                    captureID = nil
                }
                guard try await transcriptHistoryStore.replaceTranscript(
                    id: selectedTranscript.id,
                    transcript: selectedTranscript.transcript,
                    editorText: editorText,
                    captureID: captureID
                ) != nil else {
                    throw VoiceBridgeError.recordingUnavailable
                }
                if lastCoverageRecoveryRecordID == selectedTranscript.id {
                    lastCoverageRecoveryRecordID = nil
                }
                await refreshTranscriptHistory()
                selectedTranscriptIndex = transcriptHistory.firstIndex {
                    $0.id == selectedTranscript.id
                } ?? 0
                await updateRetryCount()

                await beforeInsertion()
                targetApplicationPID = targetPID
                let inserted = await insertTranscript(
                    selectedTranscript.transcript,
                    editorText: editorText,
                    showDeliveryStep: captureID != nil
                )
                if inserted {
                    clearFailureAfterSuccess()
                    phase = .delivered
                    contextMessage = captureID == nil
                        ? "Recovered transcript inserted."
                        : "Recovered capture inserted and awaiting specialist decision."
                } else {
                    reportFailure(
                        VoiceBridgeError.codexUnavailable(
                            "Focus an editable text field, then insert the recovered transcript again."
                        ),
                        stage: .insertion,
                        hasRecoverableAudio: true
                    )
                }
            } catch {
                reportFailure(
                    error,
                    stage: .transcription,
                    hasRecoverableAudio: true
                )
            }
        }
    }

    private func recoveryActivityIsEligible(_ activityID: String) -> Bool {
        if context?.focusedActivity?.activityId == activityID {
            return true
        }
        guard let timer = timerInstrument?.activities.first(where: {
            $0.id == activityID
        })?.timer else {
            return false
        }
        return !timer.completed
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

    func insertPendingAgain(
        _ capture: PendingVoiceCapture,
        dismissMenu: @escaping @MainActor () -> Void
    ) {
        let envelope = VoiceCaptureEnvelope(
            captureID: capture.id,
            activityID: capture.activity.activityId,
            turnID: capture.turnID,
            transcript: capture.transcript
        )
        let targetPID = manualInsertionTargetPID(surface: .menuBar)
        let menuWindow = NSApp.keyWindow
        dismissMenu()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await waitForMenuDismissal(menuWindow)
            targetApplicationPID = targetPID
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

    private func waitForMenuDismissal(_ window: NSWindow?) async {
        guard let window else {
            await Task.yield()
            return
        }
        for _ in 0..<MenuInsertionDismissalPolicy.maximumChecks {
            if MenuInsertionDismissalPolicy.hasDismissed(
                windowIsVisible: window.isVisible,
                windowIsKey: window.isKeyWindow
            ) {
                await Task.yield()
                return
            }
            try? await Task.sleep(
                for: .milliseconds(
                    MenuInsertionDismissalPolicy.pollingMilliseconds
                )
            )
        }
    }

    func toggleLastAudioPlayback() {
        guard let lastAudioData else { return }
        playbackTranscriptID = nil
        toggleAudioPlayback(data: lastAudioData)
    }

    func toggleSelectedTranscriptPlayback() {
        guard let selectedTranscript,
              selectedTranscript.audioReference != nil,
              let transcriptHistoryStore else {
            return
        }
        if playbackTranscriptID == selectedTranscript.id,
           audioPlayer != nil {
            toggleAudioPlayback(data: Data())
            return
        }
        Task { [weak self] in
            guard let self,
                  let url = await transcriptHistoryStore.audioURL(
                      for: selectedTranscript
                  ),
                  let data = try? Data(
                      contentsOf: url,
                      options: .mappedIfSafe
                  ),
                  !data.isEmpty else {
                await self?.refreshTranscriptHistory()
                return
            }
            self.stopLastAudioPlayback()
            self.playbackTranscriptID = selectedTranscript.id
            self.toggleAudioPlayback(data: data)
        }
    }

    private func toggleAudioPlayback(data: Data) {
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
                player = try AVAudioPlayer(data: data)
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
        playbackTranscriptID = nil
    }

    func seekLastAudio(to progress: Double) {
        guard let audioPlayer else { return }
        let time = min(1, max(0, progress)) * audioPlayer.duration
        audioPlayer.currentTime = time
        playbackCurrentTime = time
    }

    func exportLastMemo() {
        guard hasLastMemo else { return }
        NSApp.activate(ignoringOtherApps: true)
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
        panel.level = .floating
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

    func exportSelectedTranscriptMemo() {
        guard let selectedTranscript,
              selectedTranscript.audioReference != nil,
              let transcriptHistoryStore else {
            return
        }
        Task { [weak self] in
            guard let self,
                  let retainedURL = await transcriptHistoryStore.audioURL(
                      for: selectedTranscript
                  ),
                  let audioData = try? Data(
                      contentsOf: retainedURL,
                      options: .mappedIfSafe
                  ),
                  !audioData.isEmpty else {
                await self?.refreshTranscriptHistory()
                return
            }
            NSApp.activate(ignoringOtherApps: true)
            let plan = VoiceMemoExportPlan(
                activityTitle: selectedTranscript.activityTitle,
                createdAt: selectedTranscript.createdAt
            )
            let panel = NSSavePanel()
            panel.title = "Save Voice Memo"
            panel.message = selectedTranscript.activityTitle.map {
                "Linked to \($0)"
            } ?? "General dictation · not linked to Interview Arc"
            panel.prompt = "Save"
            panel.canCreateDirectories = true
            panel.level = .floating
            panel.allowedContentTypes = [.mpeg4Audio]
            panel.nameFieldStringValue = plan.suggestedAudioFilename
            let transcriptCheckbox = NSButton(
                checkboxWithTitle: "Also save transcript as .txt",
                target: nil,
                action: nil
            )
            transcriptCheckbox.state = .on
            panel.accessoryView = transcriptCheckbox
            guard panel.runModal() == .OK, let audioURL = panel.url else {
                return
            }
            do {
                try audioData.write(to: audioURL, options: .atomic)
                if transcriptCheckbox.state == .on {
                    try selectedTranscript.transcript.write(
                        to: plan.transcriptURL(forAudioURL: audioURL),
                        atomically: true,
                        encoding: .utf8
                    )
                }
                self.contextMessage = "Voice memo saved."
            } catch {
                self.reportFailure(
                    error,
                    stage: .export,
                    hasRecoverableAudio: true
                )
            }
        }
    }

    func deleteSelectedTranscript() {
        guard let selectedTranscript else { return }
        let id = selectedTranscript.id
        if lastCoverageRecoveryRecordID == id {
            lastCoverageRecoveryRecordID = nil
        }
        Task { [weak self] in
            guard let self else { return }
            if selectedTranscript.recoveryStatus == .coverageUncertain {
                try? await transcriptHistoryStore?.discardRecovery(id: id)
            } else {
                try? await transcriptHistoryStore?.delete(id: id)
            }
            await refreshTranscriptHistory()
        }
    }

    func clearRecentTranscriptHistory() {
        lastCoverageRecoveryRecordID = nil
        Task { [weak self] in
            guard let self else { return }
            try? await transcriptHistoryStore?.clear()
            selectedTranscriptIndex = 0
            await refreshTranscriptHistory()
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
            let speechEvidence = try LocalSpeechEvidenceAnalyzer.inspect(retryURL)
            let speechScanSeconds = Date()
                .timeIntervalSince(speechScanStartedAt)
            guard speechProtectionMode == .off
                || speechEvidence.containsSpeech else {
                canRetryLastTranscription = false
                reportFailure(
                    kind: .recording,
                    title: "No speech detected",
                    message: "Nothing was inserted or sent · record again when ready",
                    detail: "Local voice-activity checks found no sustained speech in the preserved recording.",
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
                protectionMode: speechProtectionMode,
                microphoneRecoveryCount: 0,
                vadSpeechFrameCount: speechEvidence.vadSpeechFrameCount,
                vadLongestSpeechRunFrames:
                    speechEvidence.vadLongestSpeechRunFrames
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
                        isRetry: true,
                        speechEvidence: speechEvidence,
                        diagnosticSeed: diagnosticSeed
                    )
                case .general, nil:
                    await processGeneral(
                        recording: recording,
                        rememberAudio: false,
                        isRetry: true,
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

    func selectWidgetSizeMode(_ mode: VoiceWidgetSizeMode) {
        guard widgetSizeMode != mode else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let update = {
            self.widgetSizeMode = mode
            if mode == .mini {
                self.timerPanelExpanded = false
                self.activityPickerExpanded = false
                self.finishingActivityID = nil
                self.finishOutcome = nil
                self.finishStarred = false
                self.sessionFinishResolutionRequested = false
                SessionFinishResolverWindowPresenter.shared.dismiss()
            }
        }
        if reduceMotion {
            update()
        } else {
            withAnimation(.easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds)) {
                update()
            }
        }
        mode.save()
        synchronizeFloatingPanelSize()
    }

    func toggleWidgetSizeMode() {
        selectWidgetSizeMode(widgetSizeMode == .standard ? .mini : .standard)
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

    func refreshLocalWhisperModel() async {
        guard let localWhisperModelManager else { return }
        localWhisperModel = await localWhisperModelManager.snapshot()
    }

    func installLocalWhisperModel() {
        guard !localWhisperModelOperationInFlight,
              let localWhisperModelManager else { return }
        localWhisperModelOperationInFlight = true
        localWhisperModelMessage = "Installing the private local recovery model…"
        Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await localWhisperModelManager.install()
                self.localWhisperModel = snapshot
                let size = snapshot.sizeBytes.map {
                    ByteCountFormatter.string(
                        fromByteCount: $0,
                        countStyle: .file
                    )
                } ?? "an unknown size"
                self.localWhisperModelMessage = "Local recovery is ready (\(size))."
            } catch is CancellationError {
                self.localWhisperModelMessage = "Local model installation was cancelled."
            } catch {
                self.localWhisperModel = await localWhisperModelManager.snapshot()
                self.localWhisperModelMessage = "Installation failed: \(error.localizedDescription)"
            }
            self.localWhisperModelOperationInFlight = false
        }
    }

    func deleteLocalWhisperModel() {
        guard !localWhisperModelOperationInFlight,
              let localWhisperModelManager else { return }
        localWhisperModelOperationInFlight = true
        Task { [weak self] in
            guard let self else { return }
            do {
                try await localWhisperModelManager.deleteModel()
                self.localWhisperModelMessage = "Local recovery model removed."
            } catch {
                self.localWhisperModelMessage = "Removal failed: \(error.localizedDescription)"
            }
            self.localWhisperModel = await localWhisperModelManager.snapshot()
            self.localWhisperModelOperationInFlight = false
        }
    }

    func refreshDiagnostics() async {
        diagnosticRecords = (try? await diagnosticsStore?.records()) ?? []
    }

    func refreshTranscriptHistory() async {
        guard let transcriptHistoryStore else { return }
        do {
            let records = try await transcriptHistoryStore.records()
            applyTranscriptHistory(records)
            transcriptHistoryRefreshRetryTask?.cancel()
            transcriptHistoryRefreshRetryTask = nil
        } catch {
            // Preserve the last successfully loaded history. Replacing it with
            // [] made a transient file-coordination or cleanup failure look
            // like the user's Recent Transcripts had disappeared.
            scheduleTranscriptHistoryRefreshRetry()
        }
    }

    private func applyTranscriptHistory(
        _ records: [LocalTranscriptRecord]
    ) {
        transcriptHistory = records
        if lastCoverageRecoveryRecordID == nil {
            lastCoverageRecoveryRecordID = records.first(where: {
                $0.recoveryStatus == .coverageUncertain
            })?.id
        }
        selectedTranscriptIndex = min(
            selectedTranscriptIndex,
            max(0, transcriptHistory.count - 1)
        )
        scheduleTranscriptHistoryExpiry()
    }

    private func scheduleTranscriptHistoryRefreshRetry() {
        guard transcriptHistoryRefreshRetryTask == nil else { return }
        transcriptHistoryRefreshRetryTask = Task { [weak self] in
            let delays = [
                Duration.milliseconds(200),
                .seconds(1),
                .seconds(3),
            ]
            for delay in delays {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard let self,
                      let store = self.transcriptHistoryStore else {
                    return
                }
                do {
                    let records = try await store.records()
                    self.applyTranscriptHistory(records)
                    self.transcriptHistoryRefreshRetryTask = nil
                    return
                } catch {
                    continue
                }
            }
            self?.transcriptHistoryRefreshRetryTask = nil
        }
    }

    @discardableResult
    private func rememberTranscriptHistory(
        transcript: String,
        editorText: String,
        durationSeconds: Double,
        activityTitle: String?,
        captureID: String? = nil,
        recoveryStatus: LocalTranscriptRecoveryStatus? = nil,
        linkedRecoveryContext: LinkedTranscriptRecoveryContext? = nil,
        recordingURL: URL? = nil,
        recordID: UUID = UUID()
    ) async -> UUID? {
        guard let transcriptHistoryStore else { return nil }
        let record = LocalTranscriptRecord(
            id: recordID,
            transcript: transcript,
            editorText: editorText,
            durationSeconds: durationSeconds,
            activityTitle: activityTitle,
            captureID: captureID,
            recoveryStatus: recoveryStatus,
            linkedRecoveryContext: linkedRecoveryContext
        )
        let archived = try? await transcriptHistoryStore.append(
            record,
            recordingURL: recordingURL
        )
        await refreshTranscriptHistory()
        selectedTranscriptIndex = 0
        return archived?.id
    }

    private func preserveCoverageRecoveryCandidate(
        from error: Error,
        recording: RecordedCapture,
        activity: FocusedVoiceActivity?
    ) async {
        guard let failure = error as? TranscriptionIntegrityFailure,
              failure.reasons.contains(.missingSpeechCoverage),
              let candidate = failure.recoveryCandidate else {
            return
        }
        let transcript = candidate.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !transcript.isEmpty else { return }
        let recordID = lastCoverageRecoveryRecordID ?? UUID()
        let existingLinkedContext = transcriptHistory.first(where: {
            $0.id == recordID
        })?.linkedRecoveryContext
        let checksum = SHA256.hash(data: Data(transcript.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let linkedContext = activity.map { activity in
            LinkedTranscriptRecoveryContext(
                captureID: existingLinkedContext?.captureID
                    ?? "capture-\(UUID().uuidString.lowercased())",
                turnID: existingLinkedContext?.turnID
                    ?? "voice-\(UUID().uuidString.lowercased())",
                clipID: existingLinkedContext?.clipID
                    ?? "clip-\(UUID().uuidString.lowercased())",
                checksum: checksum,
                activity: existingLinkedContext?.activity ?? activity,
                transcription: candidate,
                occurredAt: existingLinkedContext?.occurredAt ?? Date()
            )
        }
        lastCoverageRecoveryRecordID = await rememberTranscriptHistory(
            transcript: transcript,
            editorText: transcript,
            durationSeconds: recording.duration,
            activityTitle: activity?.title,
            recoveryStatus: .coverageUncertain,
            linkedRecoveryContext: linkedContext,
            recordingURL: recording.url,
            recordID: recordID
        )
        lastTranscript = transcript
        lastInsertionText = transcript
    }

    private func scheduleTranscriptHistoryExpiry() {
        transcriptHistoryExpiryTask?.cancel()
        transcriptHistoryExpiryTask = Task { [weak self] in
            guard let self,
                  let expiry = try? await transcriptHistoryStore?
                      .nextExpiryDate() else {
                return
            }
            let delay = max(0, expiry.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self.refreshTranscriptHistory()
        }
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

    func canRetryDiagnostic(_ diagnostic: VoiceDiagnosticRecord) -> Bool {
        guard !isBusy, diagnosticRetryInFlightID == nil else { return false }
        return DiagnosticTranscriptionRetryPolicy.supportsLocalRetry(
            diagnosticHistoryRecord(for: diagnostic)
        )
    }

    func diagnosticRetryHelp(_ diagnostic: VoiceDiagnosticRecord) -> String {
        guard let record = diagnosticHistoryRecord(for: diagnostic) else {
            return "The retained audio for this diagnostic is unavailable."
        }
        if record.captureID != nil {
            return "Linked transcript correction requires the server supersede contract; retry is disabled to avoid creating a duplicate D1 turn."
        }
        return "Retranscribe the retained audio and replace this local Recent Transcript after review."
    }

    func retryDiagnostic(_ diagnostic: VoiceDiagnosticRecord) {
        guard canRetryDiagnostic(diagnostic),
              let record = diagnosticHistoryRecord(for: diagnostic) else {
            return
        }
        diagnosticRetryInFlightID = diagnostic.id
        diagnosticRetryMessage = nil
        Task { [weak self] in
            await self?.performDiagnosticRetry(record: record)
        }
    }

    private func diagnosticHistoryRecord(
        for diagnostic: VoiceDiagnosticRecord
    ) -> LocalTranscriptRecord? {
        DiagnosticTranscriptionRetryPolicy.matchingRecord(
            for: diagnostic,
            in: transcriptHistory
        )
    }

    private func performDiagnosticRetry(
        record: LocalTranscriptRecord
    ) async {
        defer { diagnosticRetryInFlightID = nil }
        guard let recordingStore,
              let transcriptHistoryStore,
              let audioURL = await transcriptHistoryStore.audioURL(for: record)
        else {
            diagnosticRetryMessage = "Retry unavailable: retained audio could not be opened."
            return
        }

        let startedAt = Date()
        do {
            let speechScanStartedAt = Date()
            let speechEvidence = try LocalSpeechEvidenceAnalyzer.inspect(
                audioURL
            )
            let speechScanSeconds = Date().timeIntervalSince(
                speechScanStartedAt
            )
            let pipeline = GeneralDictationPipeline(
                transcriber: GroqTranscriber(apiKey: groqKeyDraft),
                localFallback: localWhisperTranscriber,
                temporaryDirectory: recordingStore.temporaryDirectory,
                vocabularyPrompt: generalDictationPrompt
            )
            let result = try await pipeline.process(
                recordingURL: audioURL,
                durationSeconds: record.durationSeconds,
                speechEvidence: speechEvidence,
                protectionMode: speechProtectionMode
            )
            let transcript = result.transcription.text
            guard try await transcriptHistoryStore.replaceTranscript(
                id: record.id,
                transcript: transcript,
                editorText: transcript
            ) != nil else {
                diagnosticRetryMessage = "Retry completed, but the original Recent Transcript no longer exists."
                return
            }

            rememberLastAudio(RecordedCapture(
                url: audioURL,
                duration: record.durationSeconds,
                writtenFrameCount: 1,
                writeErrorDescription: nil
            ))
            lastTranscript = transcript
            lastInsertionText = transcript
            await refreshTranscriptHistory()
            selectedTranscriptIndex = transcriptHistory.firstIndex {
                $0.id == record.id
            } ?? 0
            diagnosticRetryMessage = "Retry complete. Review the updated transcript in Recent Transcripts before inserting it."

            await recordDiagnostic(
                seed: CaptureDiagnosticSeed(
                    id: record.id,
                    startedAt: startedAt,
                    recordingDurationSeconds: record.durationSeconds,
                    fileFinalizationSeconds: 0,
                    integrityInspectionSeconds: 0,
                    localSpeechScanSeconds: speechScanSeconds,
                    protectionMode: speechProtectionMode,
                    microphoneRecoveryCount: 0,
                    vadSpeechFrameCount: speechEvidence.vadSpeechFrameCount,
                    vadLongestSpeechRunFrames:
                        speechEvidence.vadLongestSpeechRunFrames
                ),
                insertionSeconds: 0,
                transcription: TranscriptionDiagnosticMetadata(
                    timing: result.transcription.timing,
                    segmentValidationSeconds:
                        result.segmentValidationSeconds,
                    omittedUnsupportedSegmentCount:
                        result.omittedUnsupportedSegmentCount,
                    omittedUnsupportedWordCount:
                        result.omittedUnsupportedWordCount,
                    wordAlignmentComplete: result.wordAlignmentComplete,
                    evaluatedSegmentCount: result.evaluatedSegmentCount,
                    wordTimestampCount: result.wordTimestampCount,
                    providerRetryOccurred: result.wasRetried,
                    lexicalCoverageEndSeconds:
                        result.providerLexicalCoverageEndSeconds,
                    trailingSpeechLikeFrameCount:
                        result.trailingSpeechLikeFrameCount,
                    trailingSpeechLikeFraction:
                        result.trailingSpeechLikeFraction,
                    engine: result.engine,
                    model: result.model,
                    localInferenceSeconds: result.localInferenceSeconds,
                    localPromptTokenCount: result.localPromptTokenCount,
                    localFallbackAttempted: result.engine == "whisperkit"
                ),
                outcome: .delivered
            )
        } catch {
            diagnosticRetryMessage = "Retry failed: \(error.localizedDescription)"
        }
    }

    private func recordDiagnostic(
        seed: CaptureDiagnosticSeed,
        insertionSeconds: Double,
        transcription: TranscriptionDiagnosticMetadata = .init(),
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
                (transcription.timing?.chunkPreparationSeconds ?? 0)
                + (transcription.timing?.providerWaitSeconds ?? 0),
            responseProcessingSeconds:
                transcription.timing?.responseProcessingSeconds ?? 0,
            segmentValidationSeconds:
                transcription.segmentValidationSeconds,
            insertionSeconds: insertionSeconds,
            totalSeconds: Date().timeIntervalSince(seed.startedAt),
            protectionMode: seed.protectionMode,
            omittedUnsupportedSegmentCount:
                transcription.omittedUnsupportedSegmentCount,
            omittedUnsupportedWordCount:
                transcription.omittedUnsupportedWordCount,
            wordAlignmentComplete: transcription.wordAlignmentComplete,
            evaluatedSegmentCount: transcription.evaluatedSegmentCount,
            wordTimestampCount: transcription.wordTimestampCount,
            microphoneRecoveryCount: seed.microphoneRecoveryCount,
            vadSpeechFrameCount: seed.vadSpeechFrameCount,
            vadLongestSpeechRunFrames: seed.vadLongestSpeechRunFrames,
            providerRetryOccurred: transcription.providerRetryOccurred,
            lexicalCoverageEndSeconds:
                transcription.lexicalCoverageEndSeconds,
            trailingSpeechLikeFrameCount:
                transcription.trailingSpeechLikeFrameCount,
            trailingSpeechLikeFraction:
                transcription.trailingSpeechLikeFraction,
            integrityReasons: transcription.integrityReasons,
            transcriptionEngine: transcription.engine,
            transcriptionModel: transcription.model,
            localInferenceSeconds: transcription.localInferenceSeconds,
            localPromptTokenCount: transcription.localPromptTokenCount,
            localFallbackAttempted: transcription.localFallbackAttempted,
            localValidationReasons: transcription.localValidationReasons,
            captureTargetKind: seed.captureTargetKind,
            captureRouteReason: seed.captureRouteReason,
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
            if groqCredentialRejected {
                let changedInMemory = RejectedCredentialPolicy().canRetry(
                    rejectedCredential: rejectedGroqCredential,
                    submittedCredential: submittedGroqKey
                )
                let changedSinceRelaunch = rejectedGroqCredentialFingerprint
                    .map { $0 != credentialFingerprint(submittedGroqKey) }
                    ?? changedInMemory
                guard changedInMemory && changedSinceRelaunch else {
                    reportFailure(
                        kind: .configuration,
                        title: "Replace the rejected Groq key",
                        message: "The saved key is still rejected",
                        detail: "Enter a different valid Groq API key before retrying the preserved recording.",
                        actions: [.openSettings, .playRecording, .saveRecording]
                    )
                    return
                }
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
            groqCredentialRejected = false
            rejectedGroqCredential = nil
            rejectedGroqCredentialFingerprint = nil
            UserDefaults.standard.removeObject(
                forKey: "voice.groqCredentialRejected"
            )
            UserDefaults.standard.removeObject(
                forKey: "voice.rejectedGroqCredentialFingerprint"
            )
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
        guard shortcutMonitor == nil,
              linkShortcutMonitor == nil,
              widgetSizeShortcutMonitor == nil,
              plannerShortcutMonitor == nil else { return }
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
            guard shortcut != self.linkShortcut,
                  shortcut != self.widgetSizeShortcut,
                  shortcut != self.plannerShortcut else {
                self.shortcutMessage = "Record/Stop, link mode, widget size, and Plan Today need different shortcuts."
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
        guard shortcutMonitor == nil,
              linkShortcutMonitor == nil,
              widgetSizeShortcutMonitor == nil,
              plannerShortcutMonitor == nil else { return }
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
            guard shortcut != self.shortcut,
                  shortcut != self.widgetSizeShortcut,
                  shortcut != self.plannerShortcut else {
                self.shortcutMessage = "Record/Stop, link mode, widget size, and Plan Today need different shortcuts."
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

    func beginWidgetSizeShortcutCapture() {
        guard shortcutMonitor == nil,
              linkShortcutMonitor == nil,
              widgetSizeShortcutMonitor == nil,
              plannerShortcutMonitor == nil else { return }
        shortcutMessage = nil
        widgetSizeShortcutCapturing = true
        suspendGlobalShortcuts()
        widgetSizeShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if Int(event.keyCode) == kVK_Escape {
                self.endWidgetSizeShortcutCapture()
                return nil
            }
            guard let shortcut = HotKeyShortcut.from(event: event) else { return nil }
            guard shortcut != self.shortcut,
                  shortcut != self.linkShortcut,
                  shortcut != self.plannerShortcut else {
                self.shortcutMessage = "Record/Stop, link mode, widget size, and Plan Today need different shortcuts."
                self.endWidgetSizeShortcutCapture()
                return nil
            }
            self.widgetSizeShortcut = shortcut
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: "voice.widgetSizeShortcut")
            }
            self.endWidgetSizeShortcutCapture()
            return nil
        }
    }

    func beginPlannerShortcutCapture() {
        guard shortcutMonitor == nil,
              linkShortcutMonitor == nil,
              widgetSizeShortcutMonitor == nil,
              plannerShortcutMonitor == nil else { return }
        shortcutMessage = nil
        plannerShortcutCapturing = true
        suspendGlobalShortcuts()
        plannerShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if Int(event.keyCode) == kVK_Escape {
                self.endPlannerShortcutCapture()
                return nil
            }
            guard let shortcut = HotKeyShortcut.from(event: event) else { return nil }
            guard shortcut != self.shortcut,
                  shortcut != self.linkShortcut,
                  shortcut != self.widgetSizeShortcut else {
                self.shortcutMessage = "Record/Stop, link mode, widget size, and Plan Today need different shortcuts."
                self.endPlannerShortcutCapture()
                return nil
            }
            self.plannerShortcut = shortcut
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: "voice.plannerShortcut")
            }
            self.endPlannerShortcutCapture()
            return nil
        }
    }

    func cancelShortcutCapture() {
        if shortcutCapturing {
            endShortcutCapture()
        } else if linkShortcutCapturing {
            endLinkShortcutCapture()
        } else if widgetSizeShortcutCapturing {
            endWidgetSizeShortcutCapture()
        } else if plannerShortcutCapturing {
            endPlannerShortcutCapture()
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
        case .useRecoveryTranscript:
            useFailureRecoveryTranscriptFromFloatingWidget()
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
        case .afterPopoverDismissalDelay:
            pendingFailurePopoverActionTask = Task { [weak self] in
                try? await Task.sleep(
                    for: .milliseconds(
                        FloatingWidgetRecoveryPolicy.dismissalSettleMilliseconds
                    )
                )
                guard !Task.isCancelled else { return }
                self?.completeFailurePopoverActionAfterClose(
                    action,
                    trigger: .fallbackTimer
                )
            }
            failureDetailsPresented = false
        case .afterPopoverDismissal:
            pendingFailurePopoverCloseObserver = NotificationCenter.default
                .addObserver(
                    forName: NSPopover.didCloseNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.completeFailurePopoverActionAfterClose(
                            action,
                            trigger: .popoverDidClose
                        )
                    }
                }
            pendingFailurePopoverActionTask = Task { [weak self] in
                try? await Task.sleep(
                    for: .milliseconds(
                        FloatingWidgetRecoveryPolicy.dismissalSettleMilliseconds
                    )
                )
                guard !Task.isCancelled else { return }
                self?.completeFailurePopoverActionAfterClose(
                    action,
                    trigger: .fallbackTimer
                )
            }
            // Arm the fallback before requesting dismissal. SwiftUI/AppKit may
            // deliver didClose synchronously; if dismissal happened first, the
            // close handler would run the action and a newly armed fallback
            // would run it a second time (Play immediately became Pause).
            failureDetailsPresented = false
        }
    }

    private func completeFailurePopoverActionAfterClose(
        _ action: VoiceFailureAction,
        trigger: FloatingWidgetRecoveryCompletionTrigger
    ) {
        if FloatingWidgetRecoveryPolicy.shouldCancelFallback(for: trigger) {
            pendingFailurePopoverActionTask?.cancel()
        }
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
        actions: [VoiceFailureAction],
        recoveryTranscriptRecordID: UUID? = nil
    ) {
        let notice = VoiceFailureNotice(
            kind: kind,
            title: title,
            message: message,
            detail: detail,
            actions: actions,
            recoveryTranscriptRecordID: recoveryTranscriptRecordID
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
        hasRecoverableAudio: Bool = false,
        recoveryTranscriptRecordID: UUID? = nil
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
                    : [.recordAgain],
                recoveryTranscriptRecordID: recoveryTranscriptRecordID
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
        guard !groqCredentialRejected else { return }
        let retainedFailure = CredentialFailureRecoveryPolicy().retainedFailure(
            failureNotice,
            configurationIsReady: configurationIsReady
        )
        guard failureNotice != nil, retainedFailure == nil else { return }
        clearFailureAfterSuccess()
    }

    private func credentialFingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func rejectCurrentGroqCredential() {
        let value = groqKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        rejectedGroqCredential = value
        rejectedGroqCredentialFingerprint = credentialFingerprint(value)
        groqCredentialRejected = true
        UserDefaults.standard.set(true, forKey: "voice.groqCredentialRejected")
        UserDefaults.standard.set(
            rejectedGroqCredentialFingerprint,
            forKey: "voice.rejectedGroqCredentialFingerprint"
        )
    }

    private func reportTranscriptionFailure(
        _ error: Error,
        diagnosticSeed: CaptureDiagnosticSeed?
    ) async {
        let integrityFailure = error as? TranscriptionIntegrityFailure
        let recoveryTranscriptRecordID = integrityFailure?.reasons.contains(
            .missingSpeechCoverage
        ) == true ? lastCoverageRecoveryRecordID : nil
        canRetryLastTranscription = false
        endProcessing()
        if TranscriptionFailurePolicy.disposition(for: error)
            == .replaceCredential {
            rejectCurrentGroqCredential()
            reportFailure(
                kind: .configuration,
                title: "Groq key rejected",
                message: "Recording preserved · replace the key in Settings",
                detail: "Groq rejected the saved API key. Voice stopped automatic retries so the protected recording cannot enter a failure loop.",
                actions: [.openSettings, .playRecording, .saveRecording]
            )
        } else {
            canRetryLastTranscription = hasLastAudio
            reportFailure(
                error,
                stage: .transcription,
                hasRecoverableAudio: hasLastAudio,
                recoveryTranscriptRecordID: recoveryTranscriptRecordID
            )
        }
        if let diagnosticSeed {
            let integrityReasons: [TranscriptionIntegrityReason]?
            if let integrityFailure {
                integrityReasons = integrityFailure.reasons
            } else if case let VoiceBridgeError.suspiciousTranscript(reasons) = error {
                integrityReasons = reasons
            } else {
                integrityReasons = nil
            }
            await recordDiagnostic(
                seed: diagnosticSeed,
                insertionSeconds: currentInsertionDurationSeconds,
                transcription: TranscriptionDiagnosticMetadata(
                    timing: integrityFailure?.timing,
                    providerRetryOccurred:
                        integrityFailure?.providerRetryOccurred,
                    lexicalCoverageEndSeconds:
                        integrityFailure?.lexicalCoverageEndSeconds,
                    trailingSpeechLikeFrameCount:
                        integrityFailure?.trailingSpeechLikeFrameCount,
                    trailingSpeechLikeFraction:
                        integrityFailure?.trailingSpeechLikeFraction,
                    integrityReasons: integrityReasons,
                    engine: integrityFailure?.localFallbackAttempted == true
                        ? integrityFailure?.localFallbackEngine
                        : "groq",
                    model: integrityFailure?.localFallbackAttempted == true
                        ? integrityFailure?.localFallbackModel
                        : "whisper-large-v3",
                    localInferenceSeconds:
                        integrityFailure?.localInferenceSeconds,
                    localPromptTokenCount:
                        integrityFailure?.localPromptTokenCount,
                    localFallbackAttempted:
                        integrityFailure?.localFallbackAttempted,
                    localValidationReasons:
                        integrityFailure?.localValidationReasons
                ),
                outcome: .failed
            )
        }
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
        if let failureNotice,
           failureNotice.kind == .transcription,
           failureNotice.detail.localizedCaseInsensitiveContains(
               "invalid api key"
           ) || failureNotice.detail.contains("Request failed (401)") {
            rejectCurrentGroqCredential()
            reportFailure(
                kind: .configuration,
                title: "Groq key rejected",
                message: "Recording preserved · replace the key in Settings",
                detail: "Groq rejected the saved API key. Voice stopped automatic retries so the protected recording cannot enter a failure loop.",
                actions: [.openSettings, .playRecording, .saveRecording]
            )
        }
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
                if !isRecording && !isBusy {
                    contextMessage = currentTargetDecision.canAttach
                        ? "Linked to \(activity.title)"
                        : "Activity ready · current app uses general dictation."
                }
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
                            if self.plannerPresented {
                                await self.refreshPlanning()
                            }
                        case .practiceChanged(let update):
                            self.lastLiveRevision = max(self.lastLiveRevision, update.revision)
                            if ["voice_intent", "voice_capture"].contains(update.scope) {
                                await self.retryPendingInBackground()
                            } else if !self.timerMutationInFlight {
                                await self.refreshContext(showProgress: false)
                                if self.plannerPresented {
                                    await self.refreshPlanning()
                                }
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
            rememberExternalApplication(targetApplication)
            captureStartedInCodex = currentTargetDecision.canAttach
        } else {
            currentTargetDecision = CaptureTargetApplicationPolicy.decision(for: nil)
            captureStartedInCodex = false
        }
        deliveryStates = [:]
        canRetryLastTranscription = false
        captureGeneration = UUID()

        // Context is refreshed continuously while idle. Opening the
        // microphone must not wait for a network round trip because that
        // loses the first words of an answer.
        let recordingStartedAt = Date()
        let routeEvaluation = routeEvaluationPolicy.evaluate(
            linkEnabled: linkToInterviewArc,
            target: currentTargetDecision,
            hasFocusedActivity: context?.focusedActivity != nil,
            contextIsFresh: contextIsFreshForCapture
        )
        captureRouteReason = routeEvaluation.reason
        voiceBridgeLogger.info(
            "Capture route evaluated: target=\(self.currentTargetDecision.kind.rawValue, privacy: .public) targetReason=\(self.currentTargetDecision.reason.rawValue, privacy: .public) route=\(String(describing: routeEvaluation.route), privacy: .public) routeReason=\(routeEvaluation.reason.rawValue, privacy: .public)"
        )
        switch routeEvaluation.route {
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
            plannerPresentedBeforeRecording = plannerPresented
            plannerPresented = false
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
                rememberLastAudio(
                    recording,
                    activityTitle: memoActivityTitle
                )
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
            if recovery == .transcribe {
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
                protectionMode: speechProtectionMode,
                microphoneRecoveryCount: recorder.automaticRecoveryCount,
                vadSpeechFrameCount: speechEvidence?.vadSpeechFrameCount,
                vadLongestSpeechRunFrames:
                    speechEvidence?.vadLongestSpeechRunFrames,
                captureTargetKind: currentTargetDecision.kind,
                captureRouteReason: captureRouteReason
            )

            switch recovery {
            case .transcribe:
                if let speechEvidence {
                    voiceBridgeLogger.info(
                        "Local speech evidence: speech=\(speechEvidence.containsSpeech, privacy: .public) duration=\(speechEvidence.analyzedDurationSeconds, privacy: .public)s frames=\(speechEvidence.speechLikeFrameCount, privacy: .public) run=\(speechEvidence.longestSpeechRunFrames, privacy: .public) vadFrames=\(speechEvidence.vadSpeechFrameCount, privacy: .public) vadRun=\(speechEvidence.vadLongestSpeechRunFrames, privacy: .public) floor=\(speechEvidence.noiseFloorDecibels, privacy: .public)dB peak=\(speechEvidence.peakFrameDecibels, privacy: .public)dB"
                    )
                    guard speechProtectionMode == .off
                        || speechEvidence.containsSpeech else {
                        Task {
                            await recordDiagnostic(
                                seed: diagnosticSeed,
                                insertionSeconds: 0,
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
                            detail: "Local voice-activity checks found no sustained speech in the finalized recording.",
                            actions: [.recordAgain]
                        )
                        return
                    }
                }
                rememberLastAudio(
                    recording,
                    activityTitle: memoActivityTitle
                )
            case .preserveWithoutRetry:
                rememberLastAudio(
                    recording,
                    activityTitle: memoActivityTitle
                )
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
                rememberLastAudio(
                    recording,
                    activityTitle: memoActivityTitle
                )
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
        if let plannerPresentedBeforeRecording {
            plannerPresented = plannerPresentedBeforeRecording
        }
        self.plannerPresentedBeforeRecording = nil
    }

    private func processGeneral(
        recording: RecordedCapture,
        rememberAudio: Bool = true,
        isRetry: Bool = false,
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
                localFallback: localWhisperTranscriber,
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
            if isRetry,
               let recordID = lastCoverageRecoveryRecordID,
               let transcriptHistoryStore {
                _ = try? await transcriptHistoryStore.replaceTranscript(
                    id: recordID,
                    transcript: transcript,
                    editorText: transcript
                )
                await refreshTranscriptHistory()
                selectedTranscriptIndex = 0
            } else {
                await rememberTranscriptHistory(
                    transcript: transcript,
                    editorText: transcript,
                    durationSeconds: recording.duration,
                    activityTitle: nil,
                    recordingURL: recording.url
                )
            }
            lastCoverageRecoveryRecordID = nil
            try? recoverableRecordingStore?.clear()
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
                    insertionSeconds: currentInsertionDurationSeconds,
                    transcription: TranscriptionDiagnosticMetadata(
                        timing: result.transcription.timing,
                        segmentValidationSeconds:
                            result.segmentValidationSeconds,
                        omittedUnsupportedSegmentCount:
                            result.omittedUnsupportedSegmentCount,
                        omittedUnsupportedWordCount:
                            result.omittedUnsupportedWordCount,
                        wordAlignmentComplete: result.wordAlignmentComplete,
                        evaluatedSegmentCount: result.evaluatedSegmentCount,
                        wordTimestampCount: result.wordTimestampCount,
                        providerRetryOccurred: result.wasRetried,
                        lexicalCoverageEndSeconds:
                            result.providerLexicalCoverageEndSeconds,
                        trailingSpeechLikeFrameCount:
                            result.trailingSpeechLikeFrameCount,
                        trailingSpeechLikeFraction:
                            result.trailingSpeechLikeFraction,
                        engine: result.engine,
                        model: result.model,
                        localInferenceSeconds:
                            result.localInferenceSeconds,
                        localPromptTokenCount:
                            result.localPromptTokenCount,
                        localFallbackAttempted:
                            result.engine == "whisperkit"
                    ),
                    outcome: inserted ? .delivered : .failed
                )
            }
        } catch {
            await preserveCoverageRecoveryCandidate(
                from: error,
                recording: recording,
                activity: nil
            )
            await reportTranscriptionFailure(
                error,
                diagnosticSeed: diagnosticSeed
            )
        }
    }

    private func processLinked(
        recording: RecordedCapture,
        activity: FocusedVoiceActivity,
        startedAt: Date,
        generation: UUID,
        isRetry: Bool = false,
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
                    await self.handleLinkedTranscriptReady(
                        capture,
                        recordingDuration: recording.duration,
                        activityTitle: activity.title,
                        isRetry: isRetry
                    )
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
                    insertionSeconds: currentInsertionDurationSeconds,
                    transcription: TranscriptionDiagnosticMetadata(
                        timing: result.transcriptionTiming,
                        segmentValidationSeconds:
                            result.segmentValidationSeconds,
                        omittedUnsupportedSegmentCount:
                            result.omittedUnsupportedSegmentCount,
                        omittedUnsupportedWordCount:
                            result.omittedUnsupportedWordCount,
                        wordAlignmentComplete: result.wordAlignmentComplete,
                        evaluatedSegmentCount: result.evaluatedSegmentCount,
                        wordTimestampCount: result.wordTimestampCount,
                        providerRetryOccurred:
                            result.transcriptionWasRetried,
                        lexicalCoverageEndSeconds:
                            result.providerLexicalCoverageEndSeconds,
                        trailingSpeechLikeFrameCount:
                            result.trailingSpeechLikeFrameCount,
                        trailingSpeechLikeFraction:
                            result.trailingSpeechLikeFraction,
                        engine: result.transcriptionEngine,
                        model: result.transcriptionModel,
                        localInferenceSeconds:
                            result.localInferenceSeconds,
                        localPromptTokenCount:
                            result.localPromptTokenCount,
                        localFallbackAttempted:
                            result.transcriptionEngine == "whisperkit"
                    ),
                    outcome: lastInsertionSucceeded ? .delivered : .failed
                )
            }
        } catch {
            await preserveCoverageRecoveryCandidate(
                from: error,
                recording: recording,
                activity: activity
            )
            guard generation == captureGeneration else { return }
            await reportTranscriptionFailure(
                error,
                diagnosticSeed: diagnosticSeed
            )
        }
    }

    private func handleLinkedTranscriptReady(
        _ capture: VoiceCaptureEnvelope,
        recordingDuration: Double,
        activityTitle: String,
        isRetry: Bool
    ) async {
        if isRetry,
           let recordID = lastCoverageRecoveryRecordID,
           let transcriptHistoryStore {
            _ = try? await transcriptHistoryStore.replaceTranscript(
                id: recordID,
                transcript: capture.transcript,
                editorText: capture.editorText,
                captureID: capture.captureID
            )
            await refreshTranscriptHistory()
            selectedTranscriptIndex = 0
        } else {
            await rememberTranscriptHistory(
                transcript: capture.transcript,
                editorText: capture.editorText,
                durationSeconds: recordingDuration,
                activityTitle: activityTitle,
                captureID: capture.captureID
            )
        }
        lastCoverageRecoveryRecordID = nil
        _ = await insertTranscript(
            capture.transcript,
            editorText: capture.editorText,
            showDeliveryStep: true
        )
        finishForegroundInsertion()
    }

    private func updateRetryCount() async {
        guard let recordingStore else { pendingRetryCount = 0; return }
        let queue = VoiceRetryQueue(directory: recordingStore.queueDirectory)
        let legacyCount = (try? await queue.items().count) ?? 0
        if pipeline == nil { pipeline = try? makeLinkedPipeline() }
        if contextLastVerifiedAt != nil {
            await pipeline?.removeSettledCaptures(
                outsideWorkbenchID: timerInstrument?.workbenchId
            )
        }
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
                await refreshTranscriptHistory()
            } catch {
                reportFailure(error, stage: .interviewArc, hasRecoverableAudio: true)
            }
        }
    }

    func acknowledgePendingAudioLoss(_ capture: PendingVoiceCapture) {
        Task {
            do {
                if pipeline == nil { pipeline = try makeLinkedPipeline() }
                try await pipeline?.acknowledgeAudioLoss(captureID: capture.id)
                await updateRetryCount()
            } catch {
                reportFailure(error, stage: .interviewArc, hasRecoverableAudio: false)
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
        targetApplicationPID = manualInsertionTargetPID(surface: .floatingWidget)
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
            localFallback: localWhisperTranscriber,
            codex: CodexBridge(executableURL: URL(fileURLWithPath: codexPath)),
            vocabularyResolver: VocabularyResolver(catalog: try .bundled()),
            retryQueue: VoiceRetryQueue(directory: recordingStore.queueDirectory),
            pendingCaptureStore: PendingVoiceCaptureStore(
                directory: recordingStore.pendingCapturesDirectory
            ),
            transcriptHistoryStore: transcriptHistoryStore,
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
        if let frontmost = eligibleFrontmostApplication {
            rememberExternalApplication(frontmost)
            return frontmost.processIdentifier
        }
        return eligibleRememberedApplication?.processIdentifier
    }

    private func rememberExternalApplication(
        _ application: NSRunningApplication
    ) {
        lastExternalApplicationPID = application.processIdentifier
        currentTargetDecision = CaptureTargetApplicationPolicy.decision(
            for: CaptureTargetInspector.descriptor(for: application)
        )
    }

    private func manualInsertionTargetPID(
        surface: ManualInsertionSurface
    ) -> pid_t? {
        let current = eligibleFrontmostApplication?.processIdentifier
        let remembered = eligibleRememberedApplication?.processIdentifier
        let resolved = ManualInsertionTargetPolicy().targetPID(
            surface: surface,
            currentEligiblePID: current,
            rememberedEligiblePID: remembered
        )
        if let resolved {
            lastExternalApplicationPID = resolved
        }
        return resolved
    }

    private var eligibleFrontmostApplication: NSRunningApplication? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              !frontmost.isTerminated,
              CaptureTargetApplicationPolicy.canReceiveDictation(
                  bundleIdentifier: frontmost.bundleIdentifier
              ) else {
            return nil
        }
        return frontmost
    }

    private var eligibleRememberedApplication: NSRunningApplication? {
        guard let lastExternalApplicationPID,
              let application = NSRunningApplication(
                  processIdentifier: lastExternalApplicationPID
              ),
              !application.isTerminated,
              CaptureTargetApplicationPolicy.canReceiveDictation(
                  bundleIdentifier: application.bundleIdentifier
              ) else {
            return nil
        }
        return application
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
        await refreshTranscriptHistory()
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

    private func endWidgetSizeShortcutCapture() {
        if let widgetSizeShortcutMonitor {
            NSEvent.removeMonitor(widgetSizeShortcutMonitor)
        }
        widgetSizeShortcutMonitor = nil
        widgetSizeShortcutCapturing = false
        registerGlobalShortcuts()
    }

    private func endPlannerShortcutCapture() {
        if let plannerShortcutMonitor {
            NSEvent.removeMonitor(plannerShortcutMonitor)
        }
        plannerShortcutMonitor = nil
        plannerShortcutCapturing = false
        registerGlobalShortcuts()
    }

    private func suspendGlobalShortcuts() {
        hotKeyManager.unregister()
        linkHotKeyManager.unregister()
        widgetSizeHotKeyManager.unregister()
        plannerHotKeyManager.unregister()
    }

    private func registerGlobalShortcuts() {
        hotKeyManager.register(shortcut) { [weak self] in
            self?.toggleRecording()
        }
        linkHotKeyManager.register(linkShortcut) { [weak self] in
            self?.toggleLinkMode()
        }
        widgetSizeHotKeyManager.register(widgetSizeShortcut) { [weak self] in
            self?.toggleWidgetSizeMode()
        }
        plannerHotKeyManager.register(plannerShortcut) { [weak self] in
            self?.togglePlanner()
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
        lastCoverageRecoveryRecordID = nil
        playbackDuration = recording.duration
        lastMemoCreatedAt = Date()
        lastMemoActivityTitle = activityTitle
        lastTranscript = ""
        lastInsertionText = ""
        if hasLastAudio {
            try? recoverableRecordingStore?.save(
                LocalRecoverableRecordingReference(
                    audioURL: recording.url,
                    durationSeconds: recording.duration,
                    createdAt: lastMemoCreatedAt,
                    activityTitle: activityTitle
                )
            )
        }
    }

    private func restoreRecoverableRecordingIfNeeded() {
        guard let failureNotice,
              failureNotice.actions.contains(.playRecording)
                || failureNotice.actions.contains(.saveRecording),
              let recordingStore,
              let recoverableRecordingStore else {
            return
        }
        let allowedDirectories = [
            recordingStore.recordingsDirectory,
            recordingStore.legacyRecordingsDirectory,
            recordingStore.recentHistoryDirectory,
            recordingStore.temporaryDirectory,
        ]
        var reference = try? recoverableRecordingStore.load(
            allowedDirectories: allowedDirectories
        )
        if reference == nil,
           let migratedURL = LocalRecoverableRecordingStore
            .discoverNewestAudio(in: allowedDirectories) {
            let values = try? migratedURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            )
            reference = LocalRecoverableRecordingReference(
                audioURL: migratedURL,
                durationSeconds: 0,
                createdAt: values?.contentModificationDate ?? Date()
            )
            if let reference {
                try? recoverableRecordingStore.save(reference)
            }
        }
        guard let reference,
              let data = try? Data(
                  contentsOf: reference.audioURL,
                  options: .mappedIfSafe
              ),
              !data.isEmpty else {
            return
        }
        lastAudioData = data
        lastAudioURL = reference.audioURL
        hasLastAudio = true
        lastMemoCreatedAt = reference.createdAt
        lastMemoActivityTitle = reference.activityTitle
        if let player = try? AVAudioPlayer(data: data) {
            lastAudioDuration = reference.durationSeconds > 0
                ? reference.durationSeconds
                : player.duration
            playbackDuration = lastAudioDuration
        } else {
            lastAudioDuration = reference.durationSeconds
            playbackDuration = reference.durationSeconds
        }
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
        lastCoverageRecoveryRecordID = nil
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
        captureRouteReason = .linkedAfterContextRefresh
        voiceBridgeLogger.info(
            "Capture late-bound after context refresh: routeReason=\(self.captureRouteReason.rawValue, privacy: .public)"
        )
    }
}

private struct VoiceSettingsWindow: View {
    @ObservedObject var model: VoiceBridgeModel

    var body: some View {
        Form {
            Section("Appearance") {
                VStack(alignment: .leading, spacing: 7) {
                    Picker(
                        "Widget size",
                        selection: Binding(
                            get: { model.widgetSizeMode },
                            set: { mode in model.selectWidgetSizeMode(mode) }
                        )
                    ) {
                        ForEach(VoiceWidgetSizeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(
                        model.widgetSizeMode == .mini
                            ? "Mini keeps only the microphone and an active linked timer. Detailed controls remain in the menu-bar panel."
                            : "Standard shows the activity identity, memo actions, timers, and recording instrument."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Widget theme")
                        .font(.headline)
                    Text("Choose the floating recorder's material and color treatment.")
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
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Local recovery")
                                .font(.headline)
                            Text(localWhisperStatusText)
                                .font(.caption)
                                .foregroundStyle(
                                    model.localWhisperModel.state == .corrupt
                                        ? AnyShapeStyle(.orange)
                                        : AnyShapeStyle(.secondary)
                                )
                        }
                        Spacer()
                        if model.localWhisperModelOperationInFlight {
                            ProgressView()
                                .controlSize(.small)
                        } else if model.localWhisperModel.state == .notInstalled {
                            Button(
                                "Install",
                                action: model.installLocalWhisperModel
                            )
                        } else {
                            Button(
                                "Delete",
                                role: .destructive,
                                action: model.deleteLocalWhisperModel
                            )
                        }
                    }
                    if let message = model.localWhisperModelMessage {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("Optional \(LocalWhisperModelManager.defaultModel) model. It runs only after both Groq coverage attempts remain incomplete, stays in private app-owned storage, and never delays a healthy transcription. Offline use requires a completed installation.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
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
                HStack {
                    Text("Toggle Standard / Mini")
                    Spacer()
                    Button(
                        model.widgetSizeShortcutCapturing
                            ? "Press shortcut…"
                            : model.widgetSizeShortcut.displayName
                    ) {
                        model.beginWidgetSizeShortcutCapture()
                    }
                    .disabled(model.widgetSizeShortcutCapturing)
                    if model.widgetSizeShortcutCapturing {
                        Button("Cancel", action: model.cancelShortcutCapture)
                    }
                }
                HStack {
                    Text("Open or close Plan Today")
                    Spacer()
                    Button(
                        model.plannerShortcutCapturing
                            ? "Press shortcut…"
                            : model.plannerShortcut.displayName
                    ) {
                        model.beginPlannerShortcutCapture()
                    }
                    .disabled(model.plannerShortcutCapturing)
                    if model.plannerShortcutCapturing {
                        Button("Cancel", action: model.cancelShortcutCapture)
                    }
                }
                if model.shortcutCapturing
                    || model.linkShortcutCapturing
                    || model.widgetSizeShortcutCapturing
                    || model.plannerShortcutCapturing {
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
                            if let count = record.omittedUnsupportedWordCount {
                                LabeledContent(
                                    "Unsupported words omitted",
                                    value: "\(count)"
                                )
                            }
                            if let complete = record.wordAlignmentComplete {
                                LabeledContent(
                                    "Word alignment complete",
                                    value: complete ? "Yes" : "No"
                                )
                            }
                            if let count = record.evaluatedSegmentCount {
                                LabeledContent(
                                    "Segments evaluated",
                                    value: "\(count)"
                                )
                            }
                            if let count = record.wordTimestampCount {
                                LabeledContent(
                                    "Word timestamps",
                                    value: "\(count)"
                                )
                            }
                            Button("Copy diagnostic report") {
                                model.copyDiagnostic(record)
                            }
                            Button {
                                model.retryDiagnostic(record)
                            } label: {
                                if model.diagnosticRetryInFlightID == record.id {
                                    Label(
                                        "Retrying transcription…",
                                        systemImage: "arrow.clockwise"
                                    )
                                } else {
                                    Label(
                                        "Retry transcription",
                                        systemImage: "arrow.clockwise"
                                    )
                                }
                            }
                            .disabled(!model.canRetryDiagnostic(record))
                            .help(model.diagnosticRetryHelp(record))
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
                if let diagnosticRetryMessage = model.diagnosticRetryMessage {
                    Text(diagnosticRetryMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            await model.refreshLocalWhisperModel()
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

    private var localWhisperStatusText: String {
        switch model.localWhisperModel.state {
        case .notInstalled:
            "Not installed · Groq recovery remains available"
        case .installing:
            "Installing \(model.localWhisperModel.model)…"
        case .available:
            "Ready · \(model.localWhisperModel.model) · \(localWhisperSizeText)"
        case .corrupt:
            "Integrity check failed · delete and reinstall"
        }
    }

    private var localWhisperSizeText: String {
        guard let bytes = model.localWhisperModel.sizeBytes else {
            return "size unavailable"
        }
        return ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }

    private func diagnosticDuration(_ seconds: Double) -> String {
        if seconds >= 1 {
            return String(format: "%.2f s", seconds)
        }
        let milliseconds = seconds * 1_000
        if milliseconds > 0, milliseconds < 1 { return "<1 ms" }
        return String(format: "%.0f ms", milliseconds)
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

private struct VoiceMenuContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct VoiceBridgeMenu: View {
    @ObservedObject var model: VoiceBridgeModel
    @Environment(\.dismiss) private var dismiss
    @State private var measuredContentHeight: CGFloat = 0
    @State private var confirmingRecoveryPromotion = false

    @ViewBuilder
    var body: some View {
        switch VoiceMenuWindowLayoutPolicy.presentation(
            measuredContentHeight: measuredContentHeight,
            maximumHeight: maximumHeight
        ) {
        case .intrinsic:
            measuredMenuContent
                .frame(width: 260)
                .onPreferenceChange(
                    VoiceMenuContentHeightPreferenceKey.self,
                    perform: updateMeasuredContentHeight
                )
                .task {
                    await model.refreshTranscriptHistory()
                }
        case .scrolling(let height):
            ScrollView(.vertical) {
                measuredMenuContent
            }
            .frame(width: 260, height: height, alignment: .top)
            .onPreferenceChange(
                VoiceMenuContentHeightPreferenceKey.self,
                perform: updateMeasuredContentHeight
            )
            .task {
                await model.refreshTranscriptHistory()
            }
        }
    }

    private var measuredMenuContent: some View {
        menuContent
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: VoiceMenuContentHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            }
    }

    private func updateMeasuredContentHeight(_ height: CGFloat) {
        guard height > 0, abs(height - measuredContentHeight) > 0.5 else {
            return
        }
        measuredContentHeight = height
    }

    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusHeader
            modeCard
            if model.linkToInterviewArc { planTodayControl }
            recordingControl
            if model.recorder.isRecording, model.recorder.signalHealth == .absent {
                microphoneSignalWarning
            }
            if model.isFailurePresented { failureCard }
            if model.sessionFinishResolutionRequested {
                SessionFinishResolverCard(model: model)
            }
            if model.showsDeliverySteps { deliveryProgress }
            if model.hasLastMemo || model.hasMenuTranscript { transcriptPreview }
            if !model.workbenchVoiceCaptures.isEmpty { recentCapturesCard }
            if !model.legacyVoiceOrphans.isEmpty { legacyVoiceOrphansCard }
            if model.pendingRetryCount > 0 { retryRow }
            settings
            providerFooter
        }
        .padding(12)
        .frame(width: 260)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(
            "Use this possibly incomplete transcript?",
            isPresented: $confirmingRecoveryPromotion,
            titleVisibility: .visible
        ) {
            Button("Use this transcript") {
                model.useSelectedRecoveryTranscriptFromMenu {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Voice will use the exact text shown and the retained original recording. If linked, Voice will insert the normal Voice v2 metadata and register the capture as pending so the specialist can Attach it, Exclude it, or ask you to decide.")
        }
    }

    private var maximumHeight: CGFloat {
        VoiceMenuWindowLayoutPolicy.maximumHeight(
            visibleScreenHeight: NSScreen.main?.visibleFrame.height ?? 768
        )
    }

    private var planTodayControl: some View {
        Button {
            model.togglePlanner()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                Text(model.plannerPresented ? "Close Plan Today" : "Plan Today")
                Spacer()
                Text(model.plannerShortcut.displayName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 38)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(model.plannerPresented ? 0.2 : 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.45), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .voiceHoverFeedback(
            enabled: !model.isRecording && !model.isStartingRecording,
            cornerRadius: 9,
            tint: .accentColor
        )
        .disabled(model.isRecording || model.isStartingRecording)
        .accessibilityLabel(model.plannerPresented ? "Close Plan Today" : "Open Plan Today")
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
                    ForEach(model.availableFailureActions, id: \.self) { action in
                        if action == .openSettings {
                            ForegroundSettingsLink {
                                Label(
                                    failureActionLabel(action),
                                    systemImage: failureActionSymbol(action)
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(
                                action == model.availableFailureActions.first
                                    ? MenuFailureButtonStyle.primary
                                    : .secondary
                            )
                            .voiceHoverFeedback(cornerRadius: 8, tint: .teal)
                        } else {
                            Button {
                                model.performFailureAction(action)
                            } label: {
                                Label(
                                    failureActionLabel(action),
                                    systemImage: failureActionSymbol(action)
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(
                                action == model.availableFailureActions.first
                                    ? MenuFailureButtonStyle.primary
                                    : .secondary
                            )
                            .voiceHoverFeedback(cornerRadius: 8, tint: .teal)
                        }
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
        case .useRecoveryTranscript: "checkmark.circle.fill"
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
        case .useRecoveryTranscript: "Use this transcript"
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
                Text("RECENT TRANSCRIPTS")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(model.selectedTranscriptPosition)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
                    .opacity(model.transcriptHistory.count > 1 ? 1 : 0)
                    .accessibilityLabel(
                        "Transcript \(model.selectedTranscriptPosition)"
                    )
                memoAction(
                    symbol: "chevron.left",
                    label: "Newer transcript",
                    disabled: !model.canSelectNewerTranscript,
                    action: model.selectNewerTranscript
                )
                .opacity(model.transcriptHistory.count > 1 ? 1 : 0)
                memoAction(
                    symbol: "chevron.right",
                    label: "Older transcript",
                    disabled: !model.canSelectOlderTranscript,
                    action: model.selectOlderTranscript
                )
                .opacity(model.transcriptHistory.count > 1 ? 1 : 0)
                memoAction(
                    symbol: "trash.slash",
                    label: "Clear recent history",
                    disabled: !model.hasMenuTranscript,
                    action: model.clearRecentTranscriptHistory
                )
            }
            ZStack(alignment: .bottomTrailing) {
                if let selectedTranscript = model.selectedTranscript {
                    VStack(alignment: .leading, spacing: 4) {
                        if selectedTranscript.recoveryStatus == .coverageUncertain {
                            HStack(spacing: 6) {
                                Label(
                                    "Coverage uncertain · review first",
                                    systemImage: "exclamationmark.triangle"
                                )
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.orange)
                                .lineLimit(1)
                                Spacer(minLength: 4)
                                Button("Use this transcript") {
                                    confirmingRecoveryPromotion = true
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.mini)
                                .disabled(!model.selectedTranscriptCanUseRecovery)
                            }
                            .accessibilityElement(children: .contain)
                        }
                        ScrollView {
                            Text(selectedTranscript.transcript)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .topLeading
                                )
                                .padding(.trailing, 4)
                        }
                    }
                } else {
                    Text("The recording is safe in memory. Retry transcription when ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if model.canRetryLastTranscription,
                   model.selectedTranscriptCanRetry {
                    Button(action: model.retryLastTranscription) {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .voiceHoverFeedback(
                        enabled: !model.isBusy && !model.isRecording,
                        cornerRadius: 6
                    )
                    .disabled(model.isBusy || model.isRecording)
                    .help("Retry transcription")
                    .accessibilityLabel("Retry transcription")
                }
            }
            .frame(height: RecentTranscriptCardLayoutPolicy.previewHeight)
            .clipped()
            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.selectedTranscriptWordCountLabel)
                    Text(model.selectedTranscriptDurationLabel)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(
                    width: RecentTranscriptCardLayoutPolicy.metadataWidth,
                    alignment: .leading
                )
                Spacer(minLength: 0)
                memoAction(
                    symbol: "doc.on.doc",
                    label: "Copy transcript",
                    disabled: model.selectedTranscript == nil,
                    action: model.copySelectedTranscript
                )
                memoAction(
                    symbol: model.isPlayingLastAudio
                        ? "pause.fill"
                        : "play.fill",
                    label: model.isPlayingLastAudio
                        ? "Pause recording"
                        : "Play recording",
                    disabled: !model.selectedTranscriptOwnsAudio,
                    action: model.toggleSelectedTranscriptPlayback
                )
                memoAction(
                    symbol: "square.and.arrow.down",
                    label: "Save audio and transcript",
                    disabled: !model.selectedTranscriptOwnsAudio,
                    action: model.exportSelectedTranscriptMemo
                )
                memoAction(
                    symbol: "trash",
                    label: "Delete transcript",
                    disabled: model.selectedTranscript == nil,
                    action: model.deleteSelectedTranscript
                )
                memoAction(
                    symbol: "text.cursor",
                    label: "Insert transcript again",
                    disabled: model.selectedTranscript == nil,
                    action: {
                        model.insertSelectedTranscriptFromMenu {
                            dismiss()
                        }
                    }
                )
            }
            .frame(height: RecentTranscriptCardLayoutPolicy.footerHeight)
        }
        .padding(9)
        .frame(height: RecentTranscriptCardLayoutPolicy.cardHeight)
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
                Label("Captures in this Workbench", systemImage: "waveform.badge.magnifyingglass")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(model.workbenchVoiceCaptures.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(Array(model.workbenchVoiceCaptures.reversed())) { capture in
                        captureRow(capture)
                    }
                }
            }
            .frame(maxHeight: 220)
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
                    model.insertPendingAgain(capture) {
                        dismiss()
                    }
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
                } else if capture.localState == .acceptedDelivering {
                    Button("Retry upload", action: model.retryPending)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                } else if capture.localState == .audioLostNeedsAcknowledgement {
                    Button("Acknowledge") {
                        model.acknowledgePendingAudioLoss(capture)
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
        case .acceptedDelivering:
            return capture.lastErrorCode == nil
                ? "Related · uploading audio"
                : "Upload failed · recording safe locally"
        case .audioLostNeedsAcknowledgement:
            return "Recording unavailable · acknowledge"
        case .audioLostAcknowledged:
            return "Recording unavailable · acknowledged"
        case .quarantinedConflict: return "Conflict · review required"
        case .complete: return "R2 available · complete"
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
