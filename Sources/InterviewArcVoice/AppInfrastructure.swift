import AppKit
import ApplicationServices
import Carbon
import SwiftUI
import InterviewArcVoiceCore

struct HotKeyShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let displayName: String

    static let standard = HotKeyShortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(controlKey | optionKey),
        displayName: "⌃⌥Space"
    )

    static func from(event: NSEvent) -> HotKeyShortcut? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        var modifiers: UInt32 = 0
        var display = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); display += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); display += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); display += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); display += "⌘" }
        guard modifiers != 0 else { return nil }

        let keyName: String
        switch Int(event.keyCode) {
        case kVK_Space: keyName = "Space"
        case kVK_Return: keyName = "Return"
        case kVK_Tab: keyName = "Tab"
        case kVK_Escape: return nil
        default:
            let characters = event.charactersIgnoringModifiers?.uppercased() ?? ""
            guard characters.count == 1 else { return nil }
            keyName = characters
        }
        return HotKeyShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers, displayName: display + keyName)
    }
}

private func interviewArcHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in manager.invoke() }
    return noErr
}

@MainActor
final class GlobalHotKeyManager {
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    func register(_ shortcut: HotKeyShortcut, action: @escaping () -> Void) {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            interviewArcHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        let identifier = EventHotKeyID(signature: OSType(0x49415643), id: 1) // IAVC
        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }

    func invoke() { action?() }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

enum DictationOutput: Equatable {
    case pasted
    case copied
}

@MainActor
final class DictationTextInjector {
    var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func deliver(text: String, targetPID: pid_t?, autoPaste: Bool) async -> DictationOutput {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard autoPaste, accessibilityTrusted else { return .copied }
        if let targetPID,
           let target = NSRunningApplication(processIdentifier: targetPID),
           target.bundleIdentifier != Bundle.main.bundleIdentifier {
            target.activate(options: [.activateIgnoringOtherApps])
        }
        try? await Task.sleep(for: .milliseconds(140))
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            return .copied
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .pasted
    }
}

@MainActor
final class FloatingPanelController {
    static let shared = FloatingPanelController()
    private var panel: NSPanel?

    func show(model: VoiceBridgeModel) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 126),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = NSHostingView(rootView: FloatingRecorderView(model: model))
        panel.setFrameAutosaveName("InterviewArcVoiceFloatingPanel")
        if !panel.setFrameUsingName("InterviewArcVoiceFloatingPanel") {
            panel.center()
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func toggle(model: VoiceBridgeModel) {
        guard let panel else { show(model: model); return }
        panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless()
    }
}

struct FloatingRecorderView: View {
    @ObservedObject var model: VoiceBridgeModel

    var body: some View {
        VStack(spacing: 10) {
            primaryControls
            progressRow
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(width: 390, minHeight: 102)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThickMaterial)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.18)))
        )
        .padding(8)
    }

    private var primaryControls: some View {
        HStack(spacing: 11) {
            linkButton
            activityLabel
            if model.isRecording { RecordingClock(recorder: model.recorder) }
            recordButton
        }
    }

    private var linkButton: some View {
        Button(action: model.toggleLinkMode) {
            Image(systemName: model.linkToInterviewArc ? "link.circle.fill" : "link.circle")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(model.linkToInterviewArc ? Color(red: 0.40, green: 0.84, blue: 0.79) : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(model.isRecording || model.isBusy)
        .accessibilityLabel(model.linkToInterviewArc ? "Disconnect from Interview Arc activity" : "Connect to Interview Arc activity")
    }

    private var activityLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.floatingEyebrow)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.secondary)
            Text(model.floatingTitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordButton: some View {
        Button(action: model.toggleRecording) {
            ZStack {
                Circle().fill(model.isRecording ? Color(red: 0.91, green: 0.24, blue: 0.20) : Color(red: 0.40, green: 0.84, blue: 0.79))
                Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(red: 0.04, green: 0.16, blue: 0.15))
            }
            .frame(width: 46, height: 46)
        }
        .buttonStyle(.plain)
        .disabled(!model.isRecording && !model.canRecord)
        .accessibilityLabel(model.isRecording ? "Stop recording" : "Start recording")
    }

    @ViewBuilder
    private var progressRow: some View {
        if model.showsDeliverySteps {
            HStack(spacing: 8) {
                ForEach(VoiceDeliveryComponent.allCases, id: \.self) { component in
                    DeliveryStepView(component: component, state: model.deliveryStates[component])
                }
            }
        } else {
            HStack(spacing: 7) {
                Image(systemName: model.phase.symbol)
                Text(model.compactStatus).lineLimit(1)
                Spacer()
                Text(model.shortcut.displayName).foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
        }
    }
}

private struct DeliveryStepView: View {
    let component: VoiceDeliveryComponent
    let state: VoiceDeliveryComponentState?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(label)
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(label): \(accessibilityState)")
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

    private var accessibilityState: String {
        switch state {
        case .working: "in progress"
        case .complete: "complete"
        case .queued: "retry queued"
        case nil: "waiting"
        }
    }
}
