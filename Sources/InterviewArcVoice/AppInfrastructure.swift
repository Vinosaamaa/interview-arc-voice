import AppKit
import ApplicationServices
import Carbon
import os
import QuartzCore
import SwiftUI
import InterviewArcVoiceCore

private let textInjectionLogger = Logger(
    subsystem: "app.interviewarc.voice",
    category: "TextInjection"
)

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

}

enum DictationOutput: Equatable {
    case inserted
    case accessibilityRequired
    case noFocusedEditor
}

@MainActor
final class DictationTextInjector {
    var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func deliver(text: String, targetPID: pid_t?) async -> DictationOutput {
        guard accessibilityTrusted else {
            textInjectionLogger.error("Insertion blocked because Accessibility is not trusted")
            return .accessibilityRequired
        }
        guard let targetPID,
              let target = NSRunningApplication(processIdentifier: targetPID),
              target.bundleIdentifier != Bundle.main.bundleIdentifier else {
            textInjectionLogger.error("Insertion has no valid external target")
            return .noFocusedEditor
        }

        // Use a real paste event first. Browser and Electron editors keep
        // their DOM/model state in renderer processes and can report that an
        // Accessibility value write succeeded even though the framework
        // immediately discards it. Command-V follows the same input path as a
        // user paste, so React, contenteditable, CodeMirror, Monaco, terminals,
        // and ordinary AppKit fields all receive the expected change event.
        if await pasteIntoTarget(text, targetPID: targetPID) {
            textInjectionLogger.info("Inserted through the global paste path")
            return .inserted
        }

        // Retain direct Accessibility insertion as a fallback for an unusual
        // editor that cannot receive the system paste shortcut.
        target.activate(options: [.activateIgnoringOtherApps])
        try? await Task.sleep(for: .milliseconds(220))

        let application = AXUIElementCreateApplication(targetPID)
        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
           let focusedValue {
            let focused = focusedValue as! AXUIElement
            var selectedTextSettable = DarwinBoolean(false)
            if AXUIElementIsAttributeSettable(
                focused,
                kAXSelectedTextAttribute as CFString,
                &selectedTextSettable
            ) == .success,
               selectedTextSettable.boolValue,
               AXUIElementSetAttributeValue(
                    focused,
                    kAXSelectedTextAttribute as CFString,
                    text as CFTypeRef
               ) == .success {
                textInjectionLogger.info("Inserted through the focused Accessibility text element")
                return .inserted
            }
            if replaceFocusedValue(text, in: focused) {
                textInjectionLogger.info("Inserted through the focused Accessibility value and selection range")
                return .inserted
            }
        }

        textInjectionLogger.error("Neither paste nor Accessibility could target the requested editor")
        return .noFocusedEditor
    }

    /// Chromium and Electron frequently expose an editable value while
    /// rejecting `AXSelectedText` writes. Prefer their UTF-16 selection range
    /// when one is available. Some web controls (including empty search boxes)
    /// omit that range even though their value is writable; append in that
    /// case so the insertion still lands in the focused editor.
    private func replaceFocusedValue(_ text: String, in focused: AXUIElement) -> Bool {
        var valueSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            focused,
            kAXValueAttribute as CFString,
            &valueSettable
        ) == .success,
        valueSettable.boolValue else {
            return false
        }

        var currentValue: CFTypeRef?
        let valueRead = AXUIElementCopyAttributeValue(
            focused,
            kAXValueAttribute as CFString,
            &currentValue
        )
        guard valueRead == .success else {
            textInjectionLogger.debug(
                "Focused editor exposes a writable value but reading it failed: \(valueRead.rawValue)"
            )
            return false
        }

        let currentText: String
        if let string = currentValue as? String {
            currentText = string
        } else if let attributedString = currentValue as? NSAttributedString {
            currentText = attributedString.string
        } else if currentValue == nil {
            currentText = ""
        } else {
            return false
        }

        var selectedRangeValue: CFTypeRef?
        let selectedRangeRead = AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        )

        let currentNSString = currentText as NSString
        var selectedRange = CFRange(location: currentNSString.length, length: 0)
        if selectedRangeRead == .success, let selectedRangeValue {
            let selectedRangeAXValue = selectedRangeValue as! AXValue
            guard AXValueGetType(selectedRangeAXValue) == .cfRange,
                  AXValueGetValue(selectedRangeAXValue, .cfRange, &selectedRange) else {
                return false
            }
        } else {
            textInjectionLogger.debug(
                "Focused editor omitted its selection range; inserting at the end of its value"
            )
        }
        guard selectedRange.location >= 0,
              selectedRange.length >= 0,
              selectedRange.location + selectedRange.length <= currentNSString.length else {
            return false
        }

        let updatedText = currentNSString.replacingCharacters(
            in: NSRange(location: selectedRange.location, length: selectedRange.length),
            with: text
        )
        guard AXUIElementSetAttributeValue(
            focused,
            kAXValueAttribute as CFString,
            updatedText as CFTypeRef
        ) == .success else {
            return false
        }

        // Some Chromium controls report a successful AX write while silently
        // keeping their old DOM value. Treat that as a rejected direct write
        // so the real Command-V fallback can dispatch the browser's expected
        // paste/input events instead of claiming the transcript was inserted.
        var verifiedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXValueAttribute as CFString,
            &verifiedValue
        ) == .success else {
            return false
        }
        let verifiedText: String?
        if let string = verifiedValue as? String {
            verifiedText = string
        } else if let attributedString = verifiedValue as? NSAttributedString {
            verifiedText = attributedString.string
        } else {
            verifiedText = nil
        }
        guard verifiedText == updatedText else {
            textInjectionLogger.debug(
                "Focused editor ignored its direct Accessibility value write; falling back to paste"
            )
            return false
        }

        var updatedRange = CFRange(
            location: selectedRange.location + (text as NSString).length,
            length: 0
        )
        if let updatedRangeValue = AXValueCreate(.cfRange, &updatedRange) {
            _ = AXUIElementSetAttributeValue(
                focused,
                kAXSelectedTextRangeAttribute as CFString,
                updatedRangeValue
            )
        }
        return true
    }

    /// Web `contenteditable` controls and terminal emulators often reject
    /// synthetic Unicode key events even though native AppKit fields accept
    /// direct AX replacement. A transient paste is the common denominator
    /// across those editors. Post the shortcut through the active HID event
    /// stream: Chromium and Electron put their editable controls in renderer
    /// processes, so posting Command-V only to the parent application's PID
    /// never reaches the focused editor. The user's pasteboard is restored
    /// immediately afterward, unless another app changed it during insertion.
    private func pasteIntoTarget(_ text: String, targetPID: pid_t) async -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              ) else {
            return false
        }

        guard await activateTarget(targetPID) else { return false }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore(to: pasteboard)
            return false
        }

        let transientChangeCount = pasteboard.changeCount
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(35))
        keyUp.post(tap: .cghidEventTap)

        // Renderer-backed editors consume the HID shortcut asynchronously.
        // Keep the transient value alive through that handoff, but do not make
        // the visible completion state wait 1.5 seconds after text has already
        // appeared in the editor.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_500))
            if pasteboard.changeCount == transientChangeCount {
                snapshot.restore(to: pasteboard)
            }
        }
        return true
    }

    private func activateTarget(_ targetPID: pid_t) async -> Bool {
        guard let target = NSRunningApplication(processIdentifier: targetPID) else {
            return false
        }
        target.activate(options: [.activateIgnoringOtherApps])
        for _ in 0..<6 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID {
                return true
            }
            try? await Task.sleep(for: .milliseconds(75))
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID
    }
}

private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }

        let restoredItems = items.map { storedItem in
            let item = NSPasteboardItem()
            for (type, data) in storedItem {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restoredItems)
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
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 40),
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
        panel.setContentSize(NSSize(width: 250, height: 40))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func toggle(model: VoiceBridgeModel) {
        guard let panel else { show(model: model); return }
        panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless()
    }

    func setPlaybackExpanded(_ expanded: Bool, reduceMotion: Bool) {
        guard let panel else { return }
        let width: CGFloat = expanded ? 360 : 250
        guard abs(panel.frame.width - width) > 0.5 else { return }
        var frame = panel.frame
        let rightEdge = frame.maxX
        frame.size.width = width
        frame.origin.x = rightEdge - width
        if reduceMotion {
            panel.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }
}

struct FloatingRecorderView: View {
    @ObservedObject var model: VoiceBridgeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            linkButton
            if model.isRecording {
                LiveVoiceWaveform(recorder: model.recorder)
                RecordingClock(recorder: model.recorder, compact: true)
            } else if model.isPlaybackExpanded {
                playbackControls
            } else if model.isBusy, model.showProcessingIndicator {
                processingLabel
            } else {
                activityLabel
                if model.hasLastAudio {
                    memoButton(
                        symbol: model.isPlayingLastAudio ? "pause.fill" : "play.fill",
                        label: model.isPlayingLastAudio ? "Pause last recording" : "Play last recording",
                        action: model.toggleLastAudioPlayback
                    )
                }
                if !model.lastTranscript.isEmpty {
                    memoButton(
                        symbol: "doc.on.doc",
                        label: "Copy last transcript",
                        action: model.copyLastTranscript
                    )
                }
                if model.hasLastAudio {
                    memoButton(
                        symbol: "square.and.arrow.down",
                        label: "Save last audio and transcript",
                        action: model.exportLastMemo
                    )
                }
            }
            recordButton
        }
        .padding(.horizontal, 3)
        .frame(width: model.isPlaybackExpanded ? 360 : 250, height: 40)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color(red: 0.78, green: 0.92, blue: 0.90).opacity(0.08),
                                    Color.black.opacity(0.04),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.34), lineWidth: 0.8))
                .shadow(color: Color.black.opacity(0.20), radius: 9, y: 4)
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.isPlaybackExpanded)
        .onChange(of: model.isPlaybackExpanded) { _, expanded in
            FloatingPanelController.shared.setPlaybackExpanded(
                expanded,
                reduceMotion: reduceMotion
            )
        }
    }

    private var linkButton: some View {
        Button(action: model.toggleLinkMode) {
            ZStack {
                Circle()
                    .fill(
                        model.linkToInterviewArc
                            ? model.linkStatusColor.opacity(0.14)
                            : Color(red: 0.72, green: 0.82, blue: 0.96).opacity(0.42)
                    )
                LinkStatusIcon(
                    isLinked: model.linkToInterviewArc,
                    symbol: model.linkStatusSymbol,
                    color: model.linkStatusColor,
                    size: 19
                )
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(LayeredWidgetButtonStyle(tint: model.linkStatusColor))
        .frame(width: 28, height: 36)
        .voiceHoverFeedback(
            enabled: !model.isRecording,
            cornerRadius: 14,
            tint: model.linkStatusColor
        )
        .disabled(model.isRecording)
        .help(model.linkStatusAccessibilityLabel)
        .accessibilityLabel(model.linkStatusAccessibilityLabel)
    }

    private var activityLabel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.floatingEyebrow)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(model.floatingTitle)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var processingLabel: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(model.processingStatus)
    }

    private var playbackControls: some View {
        HStack(spacing: 6) {
            memoButton(
                symbol: model.isPlayingLastAudio ? "pause.fill" : "play.fill",
                label: model.isPlayingLastAudio ? "Pause last recording" : "Resume last recording",
                action: model.toggleLastAudioPlayback
            )
            Text(model.playbackTimeLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Slider(
                value: Binding(
                    get: { model.playbackProgress },
                    set: { model.seekLastAudio(to: $0) }
                ),
                in: 0...1
            )
            .controlSize(.mini)
            .tint(Color(red: 0.24, green: 0.72, blue: 0.68))
            memoButton(
                symbol: "doc.on.doc",
                label: "Copy last transcript",
                action: model.copyLastTranscript
            )
            memoButton(
                symbol: "square.and.arrow.down",
                label: "Save last audio and transcript",
                action: model.exportLastMemo
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func memoButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(LayeredWidgetButtonStyle(tint: Color(red: 0.30, green: 0.72, blue: 0.68)))
        .foregroundStyle(Color.primary)
        .voiceHoverFeedback(
            enabled: !model.isBusy,
            cornerRadius: 11,
            tint: Color(red: 0.30, green: 0.72, blue: 0.68)
        )
        .disabled(model.isBusy)
        .help(label)
        .accessibilityLabel(label)
    }

    private var recordButton: some View {
        Button(action: model.toggleRecording) {
            ZStack {
                Circle().fill(
                    model.isRecording
                        ? Color(red: 0.96, green: 0.29, blue: 0.25)
                        : (model.isBusy ? Color.secondary.opacity(0.22) : Color(red: 0.40, green: 0.84, blue: 0.79))
                )
                if model.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(red: 0.04, green: 0.16, blue: 0.15))
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(
            LayeredWidgetButtonStyle(
                tint: model.isRecording ? .red : Color(red: 0.40, green: 0.84, blue: 0.79),
                prominent: true
            )
        )
        .voiceHoverFeedback(
            enabled: model.isRecording || model.canRecord,
            cornerRadius: 18,
            tint: model.isRecording ? .red : .teal
        )
        .disabled(!model.isRecording && !model.canRecord)
        .accessibilityLabel(
            model.isBusy
                ? model.processingStatus
                : (model.isRecording ? "Stop recording" : "Start recording")
        )
    }

}

private struct LayeredWidgetButtonStyle: ButtonStyle {
    let tint: Color
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(configuration.isPressed ? 0.16 : 0.34),
                                tint.opacity(configuration.isPressed ? 0.18 : 0.10),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.38), lineWidth: 0.7))
                    .shadow(
                        color: Color.black.opacity(configuration.isPressed ? 0.10 : 0.22),
                        radius: configuration.isPressed ? 1 : (prominent ? 5 : 3),
                        y: configuration.isPressed ? 0 : 2
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct LinkStatusIcon: View {
    let isLinked: Bool
    let symbol: String
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
            if !isLinked {
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: 2.2, height: size + 4)
                    .rotationEffect(.degrees(42))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.75), lineWidth: 0.7)
                    }
            }
        }
        .foregroundStyle(color)
    }
}

private struct VoiceHoverFeedbackModifier: ViewModifier {
    let enabled: Bool
    let cornerRadius: CGFloat
    let tint: Color
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint.opacity(isHovering && enabled ? 0.13 : 0))
                    .allowsHitTesting(false)
            }
            .scaleEffect(isHovering && enabled ? 1.045 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func voiceHoverFeedback(
        enabled: Bool = true,
        cornerRadius: CGFloat = 8,
        tint: Color = .accentColor
    ) -> some View {
        modifier(
            VoiceHoverFeedbackModifier(
                enabled: enabled,
                cornerRadius: cornerRadius,
                tint: tint
            )
        )
    }
}

private struct LiveVoiceWaveform: View {
    @ObservedObject var recorder: AnswerRecorder
    private let shape: [CGFloat] = [0.42, 0.70, 0.52, 0.88, 0.60, 0.78, 1.00, 0.62, 0.84, 0.56, 0.76, 0.48, 0.68, 0.40]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(shape.enumerated()), id: \.offset) { index, multiplier in
                Capsule(style: .continuous)
                    .fill(Color(red: 0.18, green: 0.58, blue: 0.48))
                    .frame(width: 2.5, height: barHeight(multiplier, index: index))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.linear(duration: 0.09), value: recorder.averagePower)
        .accessibilityLabel("Live microphone level")
    }

    private func barHeight(_ multiplier: CGFloat, index: Int) -> CGFloat {
        let normalized = max(0.08, min(1, CGFloat((recorder.averagePower + 55) / 45)))
        let pulse = 0.82 + 0.18 * sin(recorder.elapsedSeconds * 11 + Double(index) * 0.72)
        return max(3, 27 * normalized * multiplier * pulse)
    }
}
