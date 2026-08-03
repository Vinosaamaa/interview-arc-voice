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

struct VoiceWidgetPalette {
    let glass: Color
    let glassHighlight: Color
    let coolBorder: Color
    let timerSurface: Color
    let teal: Color
    let tealDark: Color
    let tealGlow: Color
    let ink: Color
    let secondaryInk: Color
    let divider: Color
    let coolShadow: Color
    let linkOff: Color
    let connectedIdle: Color
    let warning: Color
    let previewBackground: Color
    let isDark: Bool

    static func palette(for theme: VoiceWidgetTheme) -> VoiceWidgetPalette {
        switch theme {
        case .arcticTeal:
            VoiceWidgetPalette(
                glass: Color(red: 0.957, green: 0.980, blue: 0.980),
                glassHighlight: .white,
                coolBorder: Color(red: 0.784, green: 0.855, blue: 0.859),
                timerSurface: Color(red: 0.898, green: 0.953, blue: 0.949),
                teal: Color(red: 0.078, green: 0.557, blue: 0.537),
                tealDark: Color(red: 0.031, green: 0.482, blue: 0.467),
                tealGlow: Color(red: 0.749, green: 0.929, blue: 0.910),
                ink: Color(red: 0.090, green: 0.165, blue: 0.196),
                secondaryInk: Color(red: 0.345, green: 0.439, blue: 0.455),
                divider: Color(red: 0.729, green: 0.800, blue: 0.804),
                coolShadow: Color(red: 0.333, green: 0.482, blue: 0.490).opacity(0.16),
                linkOff: Color(red: 0.090, green: 0.227, blue: 0.408),
                connectedIdle: Color(red: 0.651, green: 0.365, blue: 0.110),
                warning: Color(red: 0.722, green: 0.353, blue: 0.196),
                previewBackground: Color(red: 0.941, green: 0.963, blue: 0.963),
                isDark: false
            )
        case .neonCircuit:
            VoiceWidgetPalette(
                glass: Color(red: 0.018, green: 0.035, blue: 0.078),
                glassHighlight: Color(red: 0.075, green: 0.129, blue: 0.224),
                coolBorder: Color(red: 0.000, green: 0.831, blue: 1.000),
                timerSurface: Color(red: 0.018, green: 0.063, blue: 0.118),
                teal: Color(red: 0.000, green: 0.902, blue: 1.000),
                tealDark: Color(red: 0.239, green: 0.937, blue: 1.000),
                tealGlow: Color(red: 0.678, green: 0.188, blue: 1.000),
                ink: Color(red: 0.929, green: 0.980, blue: 1.000),
                secondaryInk: Color(red: 0.611, green: 0.761, blue: 0.827),
                divider: Color(red: 0.294, green: 0.326, blue: 0.561),
                coolShadow: Color(red: 0.000, green: 0.702, blue: 1.000).opacity(0.24),
                linkOff: Color(red: 0.420, green: 0.619, blue: 0.902),
                connectedIdle: Color(red: 1.000, green: 0.636, blue: 0.239),
                warning: Color(red: 1.000, green: 0.404, blue: 0.337),
                previewBackground: Color(red: 0.018, green: 0.027, blue: 0.059),
                isDark: true
            )
        case .auroraNight:
            VoiceWidgetPalette(
                glass: Color(red: 0.020, green: 0.067, blue: 0.129),
                glassHighlight: Color(red: 0.075, green: 0.180, blue: 0.286),
                coolBorder: Color(red: 0.243, green: 0.741, blue: 0.788),
                timerSurface: Color(red: 0.031, green: 0.118, blue: 0.208),
                teal: Color(red: 0.310, green: 0.929, blue: 0.820),
                tealDark: Color(red: 0.565, green: 0.953, blue: 0.937),
                tealGlow: Color(red: 0.259, green: 0.435, blue: 1.000),
                ink: Color(red: 0.914, green: 0.980, blue: 0.976),
                secondaryInk: Color(red: 0.607, green: 0.769, blue: 0.808),
                divider: Color(red: 0.263, green: 0.407, blue: 0.612),
                coolShadow: Color(red: 0.145, green: 0.435, blue: 0.776).opacity(0.23),
                linkOff: Color(red: 0.431, green: 0.616, blue: 0.863),
                connectedIdle: Color(red: 0.965, green: 0.651, blue: 0.310),
                warning: Color(red: 0.976, green: 0.424, blue: 0.345),
                previewBackground: Color(red: 0.024, green: 0.055, blue: 0.110),
                isDark: true
            )
        case .solarEmber:
            VoiceWidgetPalette(
                glass: Color(red: 0.070, green: 0.063, blue: 0.055),
                glassHighlight: Color(red: 0.176, green: 0.145, blue: 0.118),
                coolBorder: Color(red: 0.710, green: 0.416, blue: 0.208),
                timerSurface: Color(red: 0.118, green: 0.094, blue: 0.067),
                teal: Color(red: 1.000, green: 0.627, blue: 0.188),
                tealDark: Color(red: 1.000, green: 0.737, blue: 0.337),
                tealGlow: Color(red: 1.000, green: 0.514, blue: 0.110),
                ink: Color(red: 1.000, green: 0.946, blue: 0.855),
                secondaryInk: Color(red: 0.792, green: 0.706, blue: 0.596),
                divider: Color(red: 0.482, green: 0.337, blue: 0.220),
                coolShadow: Color(red: 0.663, green: 0.294, blue: 0.086).opacity(0.23),
                linkOff: Color(red: 0.456, green: 0.596, blue: 0.792),
                connectedIdle: Color(red: 1.000, green: 0.702, blue: 0.310),
                warning: Color(red: 1.000, green: 0.388, blue: 0.259),
                previewBackground: Color(red: 0.086, green: 0.075, blue: 0.063),
                isDark: true
            )
        case .sakuraGlass:
            VoiceWidgetPalette(
                glass: Color(red: 1.000, green: 0.973, blue: 0.976),
                glassHighlight: .white,
                coolBorder: Color(red: 0.890, green: 0.710, blue: 0.745),
                timerSurface: Color(red: 0.984, green: 0.890, blue: 0.906),
                teal: Color(red: 0.776, green: 0.337, blue: 0.431),
                tealDark: Color(red: 0.674, green: 0.278, blue: 0.369),
                tealGlow: Color(red: 0.969, green: 0.718, blue: 0.780),
                ink: Color(red: 0.278, green: 0.141, blue: 0.247),
                secondaryInk: Color(red: 0.486, green: 0.337, blue: 0.420),
                divider: Color(red: 0.855, green: 0.710, blue: 0.749),
                coolShadow: Color(red: 0.565, green: 0.302, blue: 0.408).opacity(0.16),
                linkOff: Color(red: 0.169, green: 0.298, blue: 0.510),
                connectedIdle: Color(red: 0.682, green: 0.365, blue: 0.118),
                warning: Color(red: 0.745, green: 0.294, blue: 0.235),
                previewBackground: Color(red: 0.996, green: 0.957, blue: 0.965),
                isDark: false
            )
        }
    }
}

struct HotKeyShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let displayName: String

    static let standard = HotKeyShortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(controlKey | optionKey),
        displayName: "⌃⌥Space"
    )

    static let linkToggle = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_L),
        carbonModifiers: UInt32(controlKey | optionKey),
        displayName: "⌃⌥L"
    )

    static let widgetSizeToggle = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_M),
        carbonModifiers: UInt32(optionKey),
        displayName: "⌥M"
    )

    static let plannerToggle = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_P),
        carbonModifiers: UInt32(controlKey | optionKey),
        displayName: "⌃⌥P"
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
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    var identifier = EventHotKeyID(signature: 0, id: 0)
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr, manager.handles(identifier) else {
        return OSStatus(eventNotHandledErr)
    }
    Task { @MainActor in manager.invoke() }
    return noErr
}

@MainActor
final class GlobalHotKeyManager {
    private nonisolated let identifierID: UInt32
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    init(identifierID: UInt32 = 1) {
        self.identifierID = identifierID
    }

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
        let identifier = EventHotKeyID(
            signature: OSType(0x49415643),
            id: identifierID
        ) // IAVC
        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
    }

    nonisolated func handles(_ identifier: EventHotKeyID) -> Bool {
        identifier.signature == OSType(0x49415643)
            && identifier.id == identifierID
    }

    func invoke() { action?() }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
    }

}

@MainActor
enum SettingsWindowPresenter {
    static func present(openSettings: () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        Task { @MainActor in
            for delay in [40, 100, 180] {
                try? await Task.sleep(for: .milliseconds(delay))
                NSApp.activate(ignoringOtherApps: true)
                if let settingsWindow = NSApp.windows.first(where: { window in
                    window.title.localizedCaseInsensitiveContains("settings")
                        || window.identifier?.rawValue
                            .localizedCaseInsensitiveContains("settings") == true
                }) {
                    settingsWindow.makeKeyAndOrderFront(nil)
                    settingsWindow.orderFrontRegardless()
                    break
                }
            }
        }
    }
}

@MainActor
final class SessionFinishResolverWindowPresenter {
    static let shared = SessionFinishResolverWindowPresenter()

    private var panel: NSPanel?

    func present(model: VoiceBridgeModel) {
        let content = SessionFinishResolverCard(
            model: model,
            onDismiss: { [weak self] in self?.dismiss() }
        )
        if let panel {
            panel.contentViewController = NSHostingController(rootView: content)
            show(panel)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 330),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Finish Interview Arc Session"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: content)
        panel.center()
        self.panel = panel
        show(panel)
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    private func show(_ panel: NSPanel) {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }
}

struct SessionFinishResolverCard: View {
    @ObservedObject var model: VoiceBridgeModel
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FINISH SESSION")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Text("Choose a result for each started activity.")
                        .font(.caption)
                }
                Spacer()
                Button {
                    model.cancelSessionFinishResolution()
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Cancel finishing session")
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.sessionFinishBlockers) { activity in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(activity.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                resultButton("Solved", outcome: .solved, activity: activity)
                                resultButton(
                                    "With help",
                                    outcome: .solvedAfterReviewingApproach,
                                    activity: activity
                                )
                                resultButton("Failed", outcome: .failed, activity: activity)
                            }
                        }
                        .padding(8)
                        .background(
                            Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: model.sessionFinishResolutionRequested) { _, requested in
            if !requested { onDismiss?() }
        }
    }

    private func resultButton(
        _ label: String,
        outcome: VoicePracticeOutcome,
        activity: VoiceTimerActivity
    ) -> some View {
        Button(label) {
            model.resolveSessionActivity(activity, outcome: outcome)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(model.timerMutationInFlight)
    }
}

struct ForegroundSettingsLink<Label: View>: View {
    @Environment(\.openSettings) private var openSettings
    private let label: Label

    init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }

    var body: some View {
        Button {
            SettingsWindowPresenter.present {
                openSettings()
            }
        } label: {
            label
        }
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
              CaptureTargetApplicationPolicy.canReceiveDictation(
                  bundleIdentifier: target.bundleIdentifier
              ) else {
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
        target.activate()
        try? await Task.sleep(for: .milliseconds(220))

        let application = AXUIElementCreateApplication(targetPID)
        AXUIElementSetMessagingTimeout(application, 1)
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
        target.activate()
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
private final class VoiceFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            // The planner lives above the recorder. Only the bottom capsule is
            // window chrome; lists, selection rails, and text fields must keep
            // their native click/scroll/drag behavior.
            if event.locationInWindow.y <= FloatingWidgetWindowPolicy.hostHeight {
                FloatingPanelController.shared.beginMiniDrag(
                    pointerLocation: NSEvent.mouseLocation
                )
            }
        case .leftMouseDragged:
            if FloatingPanelController.shared.updateMiniDrag(
                pointerLocation: NSEvent.mouseLocation
            ) {
                return
            }
        case .leftMouseUp:
            // A stationary click is forwarded unchanged. Once the pointer has
            // crossed the drag threshold, swallow mouse-up so the Button under
            // the original down event cannot fire after moving the window.
            if FloatingPanelController.shared.endMiniDrag() {
                return
            }
        default:
            break
        }
        super.sendEvent(event)
    }
}

@MainActor
final class FloatingPanelController {
    static let shared = FloatingPanelController()
    private var panel: NSPanel?
    private var previousFrontmostApplication: NSRunningApplication?
    private var miniDragStartFrame: NSRect?
    private var miniDragStartPointer: CGPoint?
    private var miniDragDidMove = false

    func show(model: VoiceBridgeModel) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let initialSize = model.floatingSize
        let panel = VoiceFloatingPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: initialSize.width,
                height: initialSize.height
            ),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = FloatingWidgetWindowPolicy.hostIsOpaque
        panel.backgroundColor = .clear
        // NSPanel shadows are rectangular even when SwiftUI draws a capsule.
        // The capsule supplies its own shadow so the transparent window never
        // exposes a rectangular border around the widget.
        panel.hasShadow = FloatingWidgetWindowPolicy.usesNativeWindowShadow
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground =
            FloatingWidgetWindowPolicy.usesNativeBackgroundDrag(for: model.widgetSizeMode)
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        let hostingView = TransparentHostingView(
            rootView: FloatingRecorderView(model: model)
        )
        panel.contentView = hostingView
        panel.setFrameAutosaveName("InterviewArcVoiceFloatingPanel")
        if !panel.setFrameUsingName("InterviewArcVoiceFloatingPanel") {
            panel.center()
        }
        panel.setFrame(
            FloatingWidgetGeometryPolicy.anchoredFrame(
                currentFrame: panel.frame,
                targetSize: initialSize
            ),
            display: true
        )
        panel.invalidateShadow()
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func toggle(model: VoiceBridgeModel) {
        guard let panel else { show(model: model); return }
        panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless()
    }

    func beginPlannerTextEntry() {
        guard let panel else { return }
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousFrontmostApplication = frontmost
        }
        panel.becomesKeyOnlyIfNeeded = false
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func endPlannerTextEntry() {
        panel?.becomesKeyOnlyIfNeeded = true
        if let previousFrontmostApplication,
           !previousFrontmostApplication.isTerminated {
            previousFrontmostApplication.activate(options: [.activateIgnoringOtherApps])
        }
        previousFrontmostApplication = nil
    }

    func setSize(width: CGFloat, height: CGFloat, reduceMotion: Bool) {
        guard let panel else { return }
        let visibleFrame = panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? panel.frame
        let inset: CGFloat = 6
        let targetSize = CGSize(
            width: min(width, max(1, visibleFrame.width - inset * 2)),
            height: min(height, max(1, visibleFrame.height - inset * 2))
        )
        var frame = FloatingWidgetGeometryPolicy.anchoredFrame(
            currentFrame: panel.frame,
            targetSize: targetSize
        )
        frame.origin.x = min(
            max(frame.origin.x, visibleFrame.minX + inset),
            visibleFrame.maxX - inset - frame.width
        )
        frame.origin.y = min(
            max(frame.origin.y, visibleFrame.minY + inset),
            visibleFrame.maxY - inset - frame.height
        )
        guard abs(panel.frame.width - frame.width) > 0.5
                || abs(panel.frame.height - frame.height) > 0.5
                || abs(panel.frame.minX - frame.minX) > 0.5
                || abs(panel.frame.minY - frame.minY) > 0.5 else { return }
        if reduceMotion {
            panel.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = FloatingWidgetMotionPolicy.durationSeconds
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        }
    }

    func setNativeBackgroundDragging(for mode: VoiceWidgetSizeMode) {
        panel?.isMovableByWindowBackground =
            FloatingWidgetWindowPolicy.usesNativeBackgroundDrag(for: mode)
    }

    func beginMiniDrag(pointerLocation: CGPoint) {
        guard let panel, miniDragStartFrame == nil else { return }
        miniDragStartFrame = panel.frame
        miniDragStartPointer = pointerLocation
        miniDragDidMove = false
    }

    @discardableResult
    func updateMiniDrag(pointerLocation: CGPoint) -> Bool {
        guard let panel,
              let startFrame = miniDragStartFrame,
              let startPointer = miniDragStartPointer else {
            return false
        }
        let translation = MiniWidgetPointerPolicy.screenTranslation(
            from: startPointer,
            to: pointerLocation
        )
        guard miniDragDidMove
                || MiniWidgetPointerPolicy.isDrag(translation: translation) else {
            return false
        }

        miniDragDidMove = true
        let proposed = MiniWidgetPointerPolicy.translatedOrigin(
            startOrigin: startFrame.origin,
            startPointer: startPointer,
            currentPointer: pointerLocation
        )
        let screen = NSScreen.screens.first {
            $0.frame.contains(pointerLocation)
        } ?? panel.screen ?? NSScreen.main
        let origin = screen.map {
            MiniWidgetPointerPolicy.clampedOrigin(
                proposed: proposed,
                panelSize: panel.frame.size,
                visibleFrame: $0.visibleFrame
            )
        } ?? proposed
        panel.contentView?.layer?.removeAllAnimations()
        panel.setFrameOrigin(origin)
        return true
    }

    @discardableResult
    func endMiniDrag() -> Bool {
        let didMove = miniDragDidMove
        miniDragStartFrame = nil
        miniDragStartPointer = nil
        miniDragDidMove = false
        return didMove
    }
}

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparentSurface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTransparentSurface()
    }

    private func configureTransparentSurface() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private struct FrostedInstrumentCapsule: View {
    let palette: VoiceWidgetPalette
    let isRecording: Bool

    var body: some View {
        ZStack {
            InstrumentBlurView(isDark: palette.isDark)
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.glassHighlight.opacity(palette.isDark ? 0.80 : 0.58),
                            palette.glass.opacity(palette.isDark ? 0.92 : 0.72),
                            palette.timerSurface.opacity(palette.isDark ? 0.76 : 0.36),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Capsule(style: .continuous)
                .stroke(
                    isRecording
                        ? palette.warning.opacity(0.92)
                        : palette.coolBorder.opacity(0.90),
                    lineWidth: isRecording ? 1.3 : 0.9
                )
            Capsule(style: .continuous)
                .inset(by: 1.4)
                .stroke(palette.glassHighlight.opacity(palette.isDark ? 0.40 : 0.72), lineWidth: 0.7)
            if isRecording {
                Capsule(style: .continuous)
                    .fill(palette.warning.opacity(palette.isDark ? 0.10 : 0.07))
            }
        }
        .clipShape(Capsule(style: .continuous))
    }
}

private struct InstrumentBlurView: NSViewRepresentable {
    let isDark: Bool

    private static let capsuleMask: NSImage = {
        let size = NSSize(width: 42, height: 40)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(
                roundedRect: rect,
                xRadius: 20,
                yRadius: 20
            ).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: 19, left: 20, bottom: 19, right: 20)
        image.resizingMode = .stretch
        return image
    }()

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = isDark ? .hudWindow : .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 20
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.maskImage = Self.capsuleMask
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = isDark ? .hudWindow : .popover
        view.layer?.cornerRadius = 20
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.maskImage = Self.capsuleMask
    }
}

private final class HorizontalDragScrollNSView: NSScrollView {
    private var dragStartOrigin: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        wantsLayer = true
        layer?.masksToBounds = true
        contentView.wantsLayer = true
        contentView.layer?.masksToBounds = true
        hasHorizontalScroller = false
        hasVerticalScroller = false
        horizontalScrollElasticity = .automatic
        verticalScrollElasticity = .none

        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.buttonMask = 0x1
        pan.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func scrollWheel(with event: NSEvent) {
        let horizontalDelta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
            ? event.scrollingDeltaX
            : event.scrollingDeltaY
        guard abs(horizontalDelta) > 0.01 else {
            super.scrollWheel(with: event)
            return
        }
        scrollDocument(to: contentView.bounds.origin.x + horizontalDelta)
    }

    @objc private func handlePan(_ recognizer: NSPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            dragStartOrigin = contentView.bounds.origin
        case .changed:
            guard let dragStartOrigin else { return }
            let translation = recognizer.translation(in: self)
            scrollDocument(to: dragStartOrigin.x - translation.x)
        case .ended, .cancelled, .failed:
            dragStartOrigin = nil
        default:
            break
        }
    }

    private func scrollDocument(to proposedX: CGFloat) {
        guard let documentView else { return }
        let maximumX = max(0, documentView.frame.width - contentView.bounds.width)
        let clampedX = min(max(0, proposedX), maximumX)
        contentView.scroll(to: NSPoint(x: clampedX, y: contentView.bounds.origin.y))
        reflectScrolledClipView(contentView)
    }
}

private struct HorizontalDragScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> HorizontalDragScrollNSView {
        let scrollView = HorizontalDragScrollNSView()
        let hostingView = TransparentHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: hostingView.fittingSize)
        scrollView.documentView = hostingView
        return scrollView
    }

    func updateNSView(_ scrollView: HorizontalDragScrollNSView, context: Context) {
        guard let hostingView = scrollView.documentView as? TransparentHostingView<Content> else {
            return
        }
        hostingView.rootView = content
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: max(fittingSize.width, scrollView.contentSize.width),
                height: max(fittingSize.height, scrollView.contentSize.height)
            )
        )
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct OverflowMarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measuredTextWidth: CGFloat = 0
    @State private var animationStartedAt = Date()

    private let gap: CGFloat = 22
    private let pointsPerSecond: CGFloat = 21

    var body: some View {
        GeometryReader { geometry in
            let overflows = measuredTextWidth > geometry.size.width + 1
            Group {
                if overflows && !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                        let cycle = max(1, measuredTextWidth + gap)
                        let elapsed = timeline.date.timeIntervalSince(animationStartedAt)
                        let offset = -(CGFloat(elapsed) * pointsPerSecond)
                            .truncatingRemainder(dividingBy: cycle)
                        HStack(spacing: gap) {
                            marqueeLabel
                            marqueeLabel
                        }
                        .offset(x: offset)
                    }
                } else {
                    marqueeLabel
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .leading
            )
            .clipped()
        }
        .background {
            marqueeLabel
                .fixedSize()
                .hidden()
                .background {
                    GeometryReader { measurement in
                        Color.clear.preference(
                            key: MarqueeTextWidthKey.self,
                            value: measurement.size.width
                        )
                    }
                }
        }
        .onPreferenceChange(MarqueeTextWidthKey.self) { measuredTextWidth = $0 }
        .onChange(of: text) { _, _ in animationStartedAt = Date() }
        .accessibilityLabel(text)
    }

    private var marqueeLabel: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct FloatingRecorderView: View {
    @ObservedObject var model: VoiceBridgeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var miniSmoothedLevel = 0.0
    @State private var retainedUpperSurface: FloatingWidgetUpperSurface?
    @State private var upperSurfaceRetentionGeneration = 0

    private var palette: VoiceWidgetPalette { model.widgetPalette }

    private var desiredUpperSurface: FloatingWidgetUpperSurface? {
        if model.plannerPresented, !model.isRecording {
            return .planToday
        }
        if model.widgetSizeMode == .standard,
           !model.dynamicRecordingInterfaceActive,
           model.timerPanelExpanded,
           model.hasTimerInstrument {
            return .focus
        }
        return nil
    }

    private var renderedUpperSurface: FloatingWidgetUpperSurface? {
        FloatingWidgetUpperSurfaceTransitionPolicy.renderedSurface(
            desired: desiredUpperSurface,
            retained: retainedUpperSurface
        )
    }

    var body: some View {
        GeometryReader { host in
            let upperSurfaceViewportHeight =
                FloatingWidgetWindowPolicy.upperSurfaceViewportHeight(
                    hostHeight: host.size.height
                )
            let upperSurfaceContentHeight =
                FloatingWidgetWindowPolicy.upperSurfaceContentHeight(
                    hostHeight: host.size.height
                )

            VStack(alignment: .trailing, spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    if renderedUpperSurface == .planToday {
                        FloatingTodayPlannerPanel(model: model)
                            .frame(
                                width: FloatingWidgetWindowPolicy.plannerWidth,
                                height: upperSurfaceContentHeight
                            )
                            .padding(.bottom, FloatingWidgetWindowPolicy.timerGap)
                            .transition(.identity)
                    } else if renderedUpperSurface == .focus,
                              let instrument = model.timerInstrument {
                        FloatingTimerInstrumentPanel(
                            model: model,
                            instrument: instrument,
                            contentHeight: upperSurfaceContentHeight
                        )
                        .frame(width: FloatingWidgetWindowPolicy.expandedWidth)
                        .padding(.bottom, FloatingWidgetWindowPolicy.timerGap)
                        .transition(.identity)
                    }
                }
                .frame(
                    width: host.size.width,
                    height: upperSurfaceViewportHeight,
                    alignment: .bottomTrailing
                )
                // The stable viewport ends at the recorder capsule's top edge.
                // During removal it clips planner pixels before they can show
                // through the translucent microphone control.
                .clipped()
                recorderCapsule(
                    width: FloatingWidgetGeometryPolicy.visibleCapsuleWidth(
                        hostWidth: host.size.width
                    )
                )
            }
            .padding(.vertical, FloatingWidgetWindowPolicy.hostVerticalInset)
            .frame(
                width: host.size.width,
                height: host.size.height,
                alignment: .bottomTrailing
            )
        }
        .onAppear {
            retainedUpperSurface = desiredUpperSurface
        }
        .onChange(of: desiredUpperSurface) { previous, desired in
            updateRetainedUpperSurface(from: previous, to: desired)
        }
        .onChange(of: model.floatingSize) { _, _ in resizeWindow() }
        .onChange(of: model.widgetSizeMode) { _, mode in
            FloatingPanelController.shared.setNativeBackgroundDragging(
                for: mode
            )
        }
        .onChange(of: model.plannerPresented) { _, presented in
            if presented {
                FloatingPanelController.shared.beginPlannerTextEntry()
            } else {
                FloatingPanelController.shared.endPlannerTextEntry()
            }
        }
        .onChange(of: model.planningCustomPresented) { _, _ in
            resizeWindow()
        }
        .onChange(of: model.isRecording) { _, isRecording in
            if !isRecording { miniSmoothedLevel = 0 }
        }
        .onReceive(model.recorder.$averagePower) { averagePower in
            guard model.widgetSizeMode == .mini, model.isRecording else { return }
            let current = MiniWidgetExpandingStopPolicy.normalizedLevel(
                decibels: Double(averagePower)
            )
            miniSmoothedLevel = MiniWidgetExpandingStopPolicy.smoothedLevel(
                previous: miniSmoothedLevel,
                current: current
            )
        }
    }

    private func recorderCapsule(width: CGFloat) -> some View {
        ZStack {
            ZStack {
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.001))
                    .shadow(
                        color: palette.coolShadow,
                        radius: 7,
                        y: 3
                    )
                FrostedInstrumentCapsule(
                    palette: palette,
                    isRecording: model.isRecording
                )
                standardCapsuleContent(width: width)
                    .frame(
                        width: width,
                        height: FloatingWidgetWindowPolicy.capsuleHeight
                    )
                    .clipped()
                    .opacity(model.widgetSizeMode == .standard ? 1 : 0)
                    .allowsHitTesting(model.widgetSizeMode == .standard)
                miniCapsuleContent
                    .frame(
                        width: width,
                        height: FloatingWidgetWindowPolicy.capsuleHeight
                    )
                    .clipped()
                    .opacity(model.widgetSizeMode == .mini ? 1 : 0)
                    .allowsHitTesting(model.widgetSizeMode == .mini)
            }
            .clipShape(Capsule(style: .continuous))
            .opacity(showsSharedCapsuleSurface ? 1 : 0)
            .allowsHitTesting(showsSharedCapsuleSurface)
            HStack {
                Spacer(minLength: 0)
                recordButton
            }
            .padding(.horizontal, 4)
            .frame(
                width: width,
                height: FloatingWidgetWindowPolicy.capsuleHeight
            )
        }
        .frame(
            width: width,
            height: FloatingWidgetWindowPolicy.capsuleHeight
        )
        .contentShape(Capsule(style: .continuous))
        .frame(width: width, alignment: .trailing)
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds),
            value: model.widgetSizeMode
        )
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds),
            value: showsSharedCapsuleSurface
        )
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds),
            value: model.miniWidgetLayout
        )
    }

    private var showsSharedCapsuleSurface: Bool {
        model.widgetSizeMode == .standard
            || model.miniWidgetLayout != .microphoneOnly
    }

    private func standardCapsuleContent(width: CGFloat) -> some View {
        HStack(spacing: model.isRecording ? 4 : 6) {
            linkButton
            if model.isStartingRecording {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing mic…")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.tealDark)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                // Keep the center slot flexible while the microphone route
                // starts. Without this fill, the HStack collapses to its
                // intrinsic width and the trailing record control jumps.
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Preparing microphone")
            } else if model.isRecording {
                if model.dynamicRecordingInterfaceActive {
                    Circle()
                        .fill(palette.warning)
                        .frame(width: 7, height: 7)
                        .shadow(color: palette.warning.opacity(0.65), radius: 4)
                        .accessibilityLabel("Recording live")
                }
                if model.recorder.signalHealth == .absent {
                    microphoneSignalWarning
                } else {
                    LiveVoiceWaveform(
                        recorder: model.recorder,
                        color: model.dynamicRecordingInterfaceActive
                            ? palette.warning
                            : palette.teal,
                        historical: model.dynamicRecordingInterfaceActive
                    )
                }
                RecordingClock(
                    recorder: model.recorder,
                    compact: true,
                    foregroundColor: palette.ink
                )
            } else if model.isPlaybackExpanded {
                playbackControls
            } else if model.isFailurePresented {
                failureControls
            } else if model.isBusy, model.showProcessingIndicator {
                processingLabel
            } else {
                activityLabel
                if !model.hasTimerInstrument
                    || model.timerPanelExpanded
                    || model.plannerPresented {
                    memoActionShelf(
                        presentation:
                            FloatingWidgetMemoActionLayoutPolicy.presentation(
                                capsuleWidth: width
                            )
                    )
                }
            }
            Color.clear
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func memoActionShelf(
        presentation: FloatingWidgetMemoActionPresentation
    ) -> some View {
        let hasTranscript = !model.lastTranscript.isEmpty
        let hasAudio = model.hasLastAudio
        let canPlanToday = model.linkToInterviewArc
            && !model.isRecording
            && !model.isBusy
        let actions = FloatingWidgetMemoActionPolicy.actions(
            for: presentation
        )
        Group {
            ForEach(actions, id: \.self) { action in
                memoActionButton(
                    action,
                    enabled: FloatingWidgetMemoActionPolicy.isEnabled(
                        action,
                        hasTranscript: hasTranscript,
                        hasAudio: hasAudio,
                        canPlanToday: canPlanToday
                    )
                )
                .transition(
                    reduceMotion
                        ? .opacity
                        : .opacity.combined(with: .scale(scale: 0.94))
                )
            }
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds),
            value: presentation
        )
    }

    @ViewBuilder
    private func memoActionButton(
        _ action: FloatingWidgetMemoAction,
        enabled: Bool
    ) -> some View {
        switch action {
        case .play:
            memoButton(
                symbol: model.isPlayingLastAudio ? "pause.fill" : "play.fill",
                label: model.isPlayingLastAudio
                    ? "Pause last recording"
                    : "Play last recording",
                enabled: enabled,
                action: model.toggleLastAudioPlayback
            )
        case .insert:
            memoButton(
                symbol: "text.cursor",
                label: "Insert last transcript",
                enabled: enabled,
                action: model.reinsertLastTranscript
            )
        case .copy:
            memoButton(
                symbol: "doc.on.doc",
                label: "Copy last transcript",
                enabled: enabled,
                action: model.copyLastTranscript
            )
        case .save:
            memoButton(
                symbol: "square.and.arrow.down",
                label: "Save last audio and transcript",
                enabled: enabled,
                action: model.exportLastMemo
            )
        case .planToday:
            memoButton(
                symbol: model.plannerPresented
                    ? "calendar.badge.minus"
                    : "calendar.badge.plus",
                label: model.plannerPresented
                    ? "Close Plan Today"
                    : "Plan today",
                enabled: enabled
            ) {
                model.togglePlanner()
            }
        }
    }

    @ViewBuilder
    private var miniCapsuleContent: some View {
        if model.miniWidgetLayout != .microphoneOnly {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                HStack(spacing: 0) {
                    if model.canExpandMiniSessionTimer {
                        Button {
                            model.toggleMiniSessionTimer()
                        } label: {
                            HStack(spacing: 0) {
                                if model.miniWidgetLayout == .dualTimer {
                                    miniTimerCell(
                                        model.compactSessionTime(at: timeline.date)
                                            ?? "00:00",
                                        color: palette.connectedIdle,
                                        label: "Session timer"
                                    )
                                    ZStack {
                                        Rectangle()
                                            .fill(palette.divider.opacity(0.72))
                                            .frame(width: 1, height: 22)
                                    }
                                    .frame(
                                        width: FloatingWidgetWindowPolicy
                                            .miniTimerDividerWidth
                                    )
                                }
                                miniTimerCell(
                                    model.compactActivityTime(at: timeline.date)
                                        ?? "00:00",
                                    color: palette.tealDark,
                                    label: "Activity timer"
                                )
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .voiceHoverFeedback(
                            cornerRadius: 8,
                            tint: palette.teal
                        )
                        .help(
                            model.miniWidgetLayout == .dualTimer
                                ? "Hide session timer"
                                : "Show session timer"
                        )
                    } else {
                        miniTimerCell(
                            model.miniTimerText(at: timeline.date) ?? "00:00",
                            color: palette.tealDark,
                            label: "Current timer"
                        )
                    }
                    Color.clear
                        .frame(width: 36, height: 36)
                        .padding(.leading, 4)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func miniTimerCell(
        _ text: String,
        color: Color,
        label: String
    ) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(
                width: FloatingWidgetWindowPolicy.miniTimerCellWidth,
                height: 32,
                alignment: .center
            )
            .accessibilityLabel(label)
            .accessibilityValue(text)
    }

    private func resizeWindow() {
        FloatingPanelController.shared.setSize(
            width: model.floatingWidth,
            height: model.floatingHeight,
            reduceMotion: reduceMotion
        )
    }

    private func updateRetainedUpperSurface(
        from previous: FloatingWidgetUpperSurface?,
        to desired: FloatingWidgetUpperSurface?
    ) {
        upperSurfaceRetentionGeneration += 1
        let generation = upperSurfaceRetentionGeneration
        if let desired {
            // Switching Focus ↔ Plan Today renders only the destination. AppKit
            // remains the sole owner of the bottom-anchored frame animation.
            retainedUpperSurface = desired
            return
        }
        guard FloatingWidgetUpperSurfaceTransitionPolicy.shouldRetainOutgoing(
            from: retainedUpperSurface ?? previous,
            to: desired,
            reduceMotion: reduceMotion
        ) else {
            retainedUpperSurface = nil
            return
        }
        Task { @MainActor in
            try? await Task.sleep(
                for: .seconds(
                    FloatingWidgetUpperSurfaceTransitionPolicy
                        .collapseRetentionSeconds
                )
            )
            guard generation == upperSurfaceRetentionGeneration,
                  desiredUpperSurface == nil else { return }
            retainedUpperSurface = nil
        }
    }

    private var linkButton: some View {
        Button {
            model.toggleLinkMode()
        } label: {
            LinkStatusIcon(
                state: model.linkPresentationState,
                color: model.linkStatusColor,
                size: 19
            )
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
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
        Group {
            if FloatingWidgetCoverageNoticePolicy.showsInlineNotice(
                noticePresented: model.coverageUncertainNoticePresented,
                hasTimerInstrument: model.hasTimerInstrument,
                isBusy: model.isBusy
            ) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.warning)
                    Text("Best available transcript inserted · may be incomplete")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(palette.warning)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, minHeight: 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Best available transcript inserted. It may be incomplete."
                )
            } else if model.hasTimerInstrument, !model.isBusy {
                if (model.timerPanelExpanded || model.plannerPresented),
                   FloatingWidgetCompactTimerLayoutPolicy.showsPreviousMemoActionsWhenExpanded {
                    Button {
                        if model.plannerPresented {
                            model.togglePlanner()
                        } else {
                            model.toggleTimerPanel()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            OverflowMarqueeText(
                                text: model.compactTimerTitle,
                                font: .system(size: 11, weight: .semibold),
                                color: palette.ink
                            )
                            .frame(
                                minWidth: FloatingWidgetCompactTimerLayoutPolicy.minimumTitleWidth,
                                maxWidth: .infinity,
                                minHeight: 24
                            )
                            .layoutPriority(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(palette.secondaryInk)
                                .frame(width: 10, alignment: .trailing)
                        }
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .voiceHoverFeedback(cornerRadius: 7, tint: palette.teal)
                    .help(model.plannerPresented ? "Close Plan Today" : "Hide timers")
                    .accessibilityLabel(
                        model.plannerPresented ? "Close Plan Today" : "Hide timers"
                    )
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Button {
                            model.toggleTimerPanel()
                        } label: {
                            HStack(spacing: 3) {
                                OverflowMarqueeText(
                                    text: model.compactTimerTitle,
                                    font: .system(size: 11, weight: .semibold),
                                    color: palette.ink
                                )
                                .frame(
                                    minWidth: FloatingWidgetCompactTimerLayoutPolicy.minimumTitleWidth,
                                    maxWidth: .infinity,
                                    minHeight: 24
                                )
                                .layoutPriority(1)
                                compactTimerCluster(at: timeline.date)
                                Image(systemName: model.timerPanelExpanded ? "chevron.down" : "chevron.up")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(palette.secondaryInk)
                                    .frame(width: 10, alignment: .trailing)
                            }
                            .foregroundStyle(palette.ink)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .voiceHoverFeedback(cornerRadius: 7, tint: palette.teal)
                        .help(model.timerPanelExpanded ? "Hide timers" : "Show timers")
                    }
                }
            } else {
                Text(model.floatingTitle)
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .multilineTextAlignment(model.shouldCenterFloatingTitle ? .center : .leading)
                    .frame(
                        maxWidth: .infinity,
                        alignment: model.shouldCenterFloatingTitle ? .center : .leading
                    )
                    .contentShape(Rectangle())
            }
        }
    }

    @ViewBuilder
    private func compactTimerCluster(at date: Date) -> some View {
        let activityTime = model.compactActivityTime(at: date)
        let sessionTime = model.compactSessionTime(at: date)
        HStack(spacing: FloatingWidgetCompactTimerLayoutPolicy.clusterSpacing) {
            if let activityTime {
                compactClock(
                    activityTime,
                    width: FloatingWidgetCompactTimerLayoutPolicy.activityClockWidth,
                    label: "Activity time",
                    role: .activity
                )
            }
            if activityTime != nil, sessionTime != nil {
                Rectangle()
                    .fill(palette.divider.opacity(0.75))
                    .frame(
                        width: FloatingWidgetCompactTimerLayoutPolicy.dividerWidth,
                        height: 15
                    )
            }
            if let sessionTime {
                compactClock(
                    sessionTime,
                    width: FloatingWidgetCompactTimerLayoutPolicy.sessionClockWidth(
                        for: sessionTime
                    ),
                    label: "Session time",
                    role: .session
                )
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func compactClock(
        _ value: String,
        width: CGFloat,
        label: String,
        role: CompactClockRole
    ) -> some View {
        Text(value)
            .font(
                .system(
                    size: role == .activity ? 9.5 : 8.5,
                    weight: role == .activity ? .bold : .regular,
                    design: .monospaced
                )
            )
            .monospacedDigit()
            .foregroundStyle(
                role == .activity ? palette.tealDark : palette.secondaryInk
            )
            .lineLimit(1)
            .minimumScaleFactor(0.92)
            .frame(width: width, height: 24, alignment: .center)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }

    private enum CompactClockRole {
        case activity
        case session
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

    private var microphoneSignalWarning: some View {
        HStack(spacing: 5) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.86, green: 0.30, blue: 0.20))
            Text("No microphone signal")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(Color(red: 0.62, green: 0.20, blue: 0.14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("No microphone signal detected")
    }

    private var failureControls: some View {
        HStack(spacing: 5) {
            Button(action: model.showFailureDetails) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(red: 0.86, green: 0.30, blue: 0.20))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.failureNotice?.title.uppercased() ?? "NEEDS ATTENTION")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Text(model.failureNotice?.message ?? "Open details for recovery")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .voiceHoverFeedback(cornerRadius: 8, tint: .orange)
            .popover(isPresented: $model.failureDetailsPresented, arrowEdge: .bottom) {
                FailureRecoveryPopover(model: model)
            }
            ForEach(Array(model.availableFailureActions.prefix(2)), id: \.self) { action in
                if action == .openSettings {
                    ForegroundSettingsLink {
                        Image(systemName: failureSymbol(action))
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .voiceHoverFeedback(cornerRadius: 11, tint: .teal)
                    .help(failureLabel(action))
                    .accessibilityLabel(failureLabel(action))
                } else {
                    memoButton(
                        symbol: failureSymbol(action),
                        label: failureLabel(action),
                        action: { model.performFailureAction(action) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var playbackControls: some View {
        HStack(spacing: 6) {
            memoButton(
                symbol: model.isPlayingLastAudio ? "pause.fill" : "play.fill",
                label: model.isPlayingLastAudio ? "Pause last recording" : "Resume last recording",
                action: model.toggleLastAudioPlayback
            )
            memoButton(
                symbol: "stop.fill",
                label: "Stop playback",
                action: model.stopLastAudioPlayback
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
            .tint(palette.teal)
            memoButton(
                symbol: "text.cursor",
                label: "Insert last transcript",
                action: model.reinsertLastTranscript
            )
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
            if model.hasTimerInstrument {
                memoButton(
                    symbol: model.timerPanelExpanded ? "chevron.down" : "chevron.up",
                    label: model.timerPanelExpanded ? "Hide timers" : "Show timers",
                    action: model.toggleTimerPanel
                )
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func memoButton(
        symbol: String,
        label: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(LayeredWidgetButtonStyle(tint: palette.teal, palette: palette))
        .foregroundStyle(palette.ink)
        .voiceHoverFeedback(
            enabled: !model.isBusy && enabled,
            cornerRadius: 11,
            tint: palette.teal
        )
        .disabled(model.isBusy || !enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    private func failureSymbol(_ action: VoiceFailureAction) -> String {
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

    private func failureLabel(_ action: VoiceFailureAction) -> String {
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

    private var recordButton: some View {
        Button {
            model.toggleRecording()
        } label: {
            ZStack {
                Circle()
                    .fill(recordHaloColor.opacity(model.isBusy ? 0.12 : 0.46))
                    .frame(
                        width: recordSurfaceDiameter,
                        height: recordSurfaceDiameter
                    )
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.94),
                                recordFaceColor.opacity(0.72),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                model.isBusy
                                    ? palette.coolBorder
                                    : recordIconColor.opacity(0.72),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: recordHaloColor.opacity(0.34), radius: 4, y: 2)
                    .frame(width: 32, height: 32)
                if model.isBusy {
                    ProgressView().controlSize(.small)
                } else if model.widgetSizeMode == .mini, model.isRecording {
                    miniExpandingStop
                } else {
                    Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(recordIconColor)
                }
                if model.widgetSizeMode == .mini,
                   model.linkToInterviewArc,
                   !model.isRecording,
                   !model.isBusy {
                    Image(systemName: "link")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(3)
                        .background(
                            Circle()
                                .fill(model.linkStatusColor)
                        )
                        .offset(x: -10, y: 10)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 36, height: 36)
        }
        .buttonStyle(
            LayeredWidgetButtonStyle(
                tint: model.isRecording ? .red : palette.teal,
                palette: palette,
                prominent: true
            )
        )
        .voiceHoverFeedback(
            enabled: model.isStartingRecording || model.isRecording || model.canRecord,
            cornerRadius: 18,
            tint: model.isRecording ? .red : palette.teal
        )
        .disabled(!model.isStartingRecording && !model.isRecording && !model.canRecord)
        .accessibilityLabel(
            model.isBusy
                ? model.processingStatus
                : (
                    model.isRecording
                        ? (
                            model.widgetSizeMode == .mini
                                ? "Stop recording, \(MiniWidgetExpandingStopPolicy.accessibilityDescription(level: miniSmoothedLevel))"
                                : "Stop recording"
                        )
                        : (
                            model.widgetSizeMode == .mini
                                ? "Start recording, \(model.linkStatusAccessibilityLabel)"
                                : "Start recording"
                        )
                )
        )
    }

    private var miniExpandingStop: some View {
        let size = MiniWidgetExpandingStopPolicy.stopSize(
            level: miniSmoothedLevel
        )
        return RoundedRectangle(
            cornerRadius: MiniWidgetExpandingStopPolicy.cornerRadius(for: size),
            style: .continuous
        )
        .fill(recordIconColor)
        .frame(width: size, height: size)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.10),
            value: size
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var recordHaloColor: Color {
        if model.isRecording {
            return Color(red: 0.96, green: 0.29, blue: 0.25)
        }
        if model.widgetSizeMode == .mini, !model.linkToInterviewArc {
            return palette.linkOff
        }
        return palette.tealGlow
    }

    private var recordSurfaceDiameter: CGFloat {
        model.widgetSizeMode == .mini
            ? FloatingWidgetWindowPolicy.miniMicrophoneSurfaceDiameter
            : 38
    }

    private var recordFaceColor: Color {
        model.isRecording ? Color(red: 1.00, green: 0.78, blue: 0.76) : palette.timerSurface
    }

    private var recordIconColor: Color {
        if model.isRecording {
            return Color(red: 0.72, green: 0.12, blue: 0.10)
        }
        if model.widgetSizeMode == .mini {
            return model.linkToInterviewArc ? model.linkStatusColor : palette.linkOff
        }
        return palette.tealDark
    }

}

private struct FloatingTodayPlannerPanel: View {
    @ObservedObject var model: VoiceBridgeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filterPresented = false
    @State private var sortPresented = false
    @State private var selectionTrayExpanded = false
    @State private var collapsedSessionIDs: Set<String> = []
    @FocusState private var customTitleFocused: Bool

    private var palette: VoiceWidgetPalette { model.widgetPalette }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(palette.divider.opacity(0.65))
            surfaceTabs

            Group {
                switch model.planningState.surface {
                case .current:
                    currentToday
                case .activities:
                    activityComposer
                case .fullSession:
                    fullSessionComposer
                }
            }
            .id(model.planningState.surface)
            .transition(.opacity)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .background {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            palette.glassHighlight.opacity(palette.isDark ? 0.74 : 0.56),
                            palette.glass.opacity(palette.isDark ? 0.95 : 0.76),
                            palette.timerSurface.opacity(palette.isDark ? 0.72 : 0.34),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .stroke(palette.coolBorder.opacity(0.92), lineWidth: 0.9)
                )
                .shadow(color: palette.coolShadow, radius: 10, y: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            if let message = model.planningMessage {
                HStack(spacing: 6) {
                    if model.planningMutationInFlight {
                        ProgressView().controlSize(.mini)
                    }
                    Text(message)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(2)
                }
                .foregroundStyle(
                    model.planningMutationInFlight
                        ? palette.linkOff
                        : planningMessageIsSuccess(message)
                            ? palette.tealDark
                            : palette.warning
                )
                .padding(.horizontal, 10)
                .frame(minHeight: 27)
                .background(
                    Capsule(style: .continuous)
                        .fill(palette.timerSurface.opacity(palette.isDark ? 0.96 : 0.92))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(palette.coolBorder.opacity(0.72), lineWidth: 0.8)
                        )
                        .shadow(color: palette.coolShadow, radius: 5, y: 2)
                )
                .padding(10)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan today")
    }

    private func planningMessageIsSuccess(_ message: String) -> Bool {
        [
            "Added to Today.",
            "Already applied.",
            "Full session created.",
            "Session deleted.",
            "Item removed.",
            "Today is fresh.",
            "Favorite updated.",
        ].contains(message)
    }

    private var header: some View {
        HStack(spacing: 5) {
            upperTab(
                "Focus",
                symbol: "timer",
                selected: false,
                action: model.showFocusSurface
            )
            upperTab(
                "Plan today",
                symbol: "calendar.badge.plus",
                selected: true
            ) {}
            if model.planningLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 27, height: 27)
                    .accessibilityLabel("Refreshing Today")
            } else {
                plannerIconButton(
                    "arrow.clockwise",
                    label: "Refresh planning"
                ) {
                    Task { await model.refreshPlanning() }
                }
            }
            plannerIconButton("xmark", label: "Close Plan Today") {
                model.togglePlanner()
            }
        }
        .padding(.horizontal, 7)
        .padding(.top, 6)
        .padding(.bottom, 3)
    }

    private var surfaceTabs: some View {
        HStack(spacing: 0) {
            ForEach(VoicePlanningSurface.allCases, id: \.rawValue) { surface in
                Button {
                    withAnimation(plannerAnimation) {
                        model.setPlanningSurface(surface)
                    }
                } label: {
                    Text(surface.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .contentShape(Rectangle())
                        .foregroundStyle(
                            model.planningState.surface == surface
                                ? Color.white
                                : palette.secondaryInk
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(
                                    model.planningState.surface == surface
                                        ? palette.linkOff.opacity(palette.isDark ? 0.92 : 0.96)
                                        : Color.clear
                                )
                                .animation(
                                    plannerAnimation,
                                    value: model.planningState.surface == surface
                                )
                        )
                }
                .buttonStyle(PlannerPressButtonStyle())
                .voiceHoverFeedback(cornerRadius: 9, tint: palette.linkOff)
                .accessibilityAddTraits(
                    model.planningState.surface == surface ? .isSelected : []
                )
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.glassHighlight.opacity(palette.isDark ? 0.12 : 0.38))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(palette.coolBorder.opacity(0.68), lineWidth: 0.8)
                )
        )
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 7)
    }

    private var currentToday: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let current = model.planningResponse?.current
            let sessions = current?.sessions ?? []
            let activities = current?.activities ?? []
            let standalone = activities.filter { $0.sessionId == nil }
            let focusBlocks = current?.focusBlocks ?? []

            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if !sessions.isEmpty {
                            planningSectionHeader("Sessions")
                            ForEach(sessions) { session in
                                sessionCard(
                                    session,
                                    activities: activities.filter {
                                        $0.sessionId == session.id
                                            || session.activityIds.contains($0.id)
                                    },
                                    now: timeline.date
                                )
                            }
                        }

                        if !standalone.isEmpty || !focusBlocks.isEmpty {
                            planningSectionHeader("Standalone")
                            ForEach(standalone) { activity in
                                currentActivityRow(activity, now: timeline.date)
                            }
                            ForEach(focusBlocks) { focus in
                                currentFocusRow(focus, now: timeline.date)
                            }
                        }

                        if sessions.isEmpty,
                           activities.isEmpty,
                           focusBlocks.isEmpty {
                            ContentUnavailableView(
                                "Today is open",
                                systemImage: "calendar",
                                description: Text("Add activities or build a full session.")
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 330)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                }

                Divider().overlay(palette.divider.opacity(0.55))
                startFreshControl
            }
        }
    }

    private var startFreshControl: some View {
        Button(action: model.startFreshPlanningDay) {
            HStack(spacing: 6) {
                Image(systemName: "sunrise.fill")
                Text("Start fresh today")
                Spacer()
                Text("Available after active work is finished")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(palette.secondaryInk)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(palette.secondaryInk)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(palette.glassHighlight.opacity(palette.isDark ? 0.14 : 0.44))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(palette.coolBorder.opacity(0.76), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(PlannerPressButtonStyle())
        .voiceHoverFeedback(
            enabled: !model.planningMutationInFlight
                && model.planningResponse?.workbench != nil,
            cornerRadius: 9,
            tint: palette.linkOff
        )
        .disabled(
            model.planningMutationInFlight
                || model.planningResponse?.workbench == nil
        )
        .help("Start fresh after every started activity has a result")
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var activityComposer: some View {
        VStack(spacing: 8) {
            categoryTabs
            if model.planningState.selectedCategory == .career {
                careerFocus
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                VStack(spacing: 8) {
                    catalogControls
                    catalogList
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            selectionTray
        }
        .padding(.top, 2)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var categoryTabs: some View {
        HStack(spacing: 4) {
            categoryButton("Coding", value: .leetcode)
            categoryButton("System design", value: .systemDesign)
            categoryButton("Behavioral", value: .behavioral)
            categoryButton("Career", value: .career)
        }
        .padding(.horizontal, 10)
    }

    private var catalogControls: some View {
        HStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(palette.secondaryInk)
                TextField(
                    "Search \(model.planningState.selectedSpecialty.title)",
                    text: Binding(
                        get: { model.activePlanningQuery.search },
                        set: { value in
                            model.updatePlanningQuery { $0.search = value }
                        }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .onSubmit(model.applyPlanningQuery)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(plannerControlBackground)

            plannerIconButton(
                model.activePlanningQuery.starredOnly ? "star.fill" : "star",
                label: "Favorites only",
                selected: model.activePlanningQuery.starredOnly
            ) {
                model.updatePlanningQuery { $0.starredOnly.toggle() }
                model.applyPlanningQuery()
            }

            Button {
                sortPresented = false
                filterPresented.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    plannerMenuIcon(
                        "line.3.horizontal.decrease",
                        selected: filterPresented || model.activePlanningQuery.activeFilterCount > 0
                    )
                    if model.activePlanningQuery.activeFilterCount > 0 {
                        Text("\(model.activePlanningQuery.activeFilterCount)")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                            .frame(minWidth: 13, minHeight: 13)
                            .background(Circle().fill(palette.linkOff))
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(PlannerPressButtonStyle())
            .voiceHoverFeedback(cornerRadius: 10, tint: palette.linkOff)
            .help("Filter activities")
            .accessibilityLabel("Filter activities")
            .accessibilityValue("\(model.activePlanningQuery.activeFilterCount) active")
            .popover(isPresented: $filterPresented, arrowEdge: .top) {
                planningFilterPopover
            }

            Button {
                filterPresented = false
                sortPresented.toggle()
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    plannerMenuIcon("arrow.up.arrow.down", selected: sortPresented)
                    Text(model.activePlanningQuery.direction == .descending ? "↓" : "↑")
                        .font(.system(size: 7, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.white)
                        .frame(width: 13, height: 13)
                        .background(Circle().fill(palette.linkOff))
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(PlannerPressButtonStyle())
            .voiceHoverFeedback(cornerRadius: 10, tint: palette.linkOff)
            .help("Sort activities")
            .accessibilityLabel(
                "Sort activities by \(model.activePlanningQuery.sort.title), "
                    + model.activePlanningQuery.sort.directionTitle(
                        model.activePlanningQuery.direction
                    )
            )
            .popover(isPresented: $sortPresented, arrowEdge: .top) {
                planningSortPopover
            }
        }
        .padding(.horizontal, 10)
    }

    private var planningFilterPopover: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Filter activities")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.ink)

            planningFilterSection("Review") {
                planningAttentionTile(.due, tint: palette.linkOff)
                planningAttentionTile(.needsReview, tint: palette.linkOff)
            }

            planningFilterSection("Result") {
                planningAttentionTile(.solved, tint: palette.tealDark)
                planningAttentionTile(.helped, tint: palette.tealDark)
                planningAttentionTile(.failed, tint: palette.warning)
                planningAttentionTile(.todo, tint: palette.linkOff)
            }

            planningFilterSection("Difficulty") {
                HStack(spacing: 5) {
                    ForEach(VoicePlanningDifficulty.allCases, id: \.rawValue) { difficulty in
                        planningFilterTile(
                            difficulty.rawValue.capitalized,
                            count: model.planningDifficultyCount(difficulty),
                            selected: model.activePlanningQuery.difficulty.contains(difficulty),
                            tint: palette.warning
                        ) {
                            model.updatePlanningQuery { query in
                                if query.difficulty.contains(difficulty) {
                                    query.difficulty.remove(difficulty)
                                } else {
                                    query.difficulty.insert(difficulty)
                                }
                            }
                            model.applyPlanningQuery()
                        }
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                plannerPopoverFooterButton(
                    "Clear",
                    enabled: model.activePlanningQuery.activeFilterCount > 0
                ) {
                    model.updatePlanningQuery { query in
                        query.attention.removeAll()
                        query.difficulty.removeAll()
                    }
                    model.applyPlanningQuery()
                }

                plannerPopoverFooterButton("Done", prominent: true) {
                    filterPresented = false
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private var planningSortPopover: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Sort activities")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.ink)

            ForEach(VoicePlanningSort.allCases, id: \.rawValue) { sort in
                Button {
                    model.updatePlanningQuery { $0.sort = sort }
                    model.applyPlanningQuery()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sort.title)
                            .font(.system(size: 11, weight: .bold))
                        Text(sort.directionTitle(model.activePlanningQuery.direction))
                            .font(.system(size: 9, weight: .medium))
                            .opacity(0.76)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: 45)
                    .foregroundStyle(
                        model.activePlanningQuery.sort == sort
                            ? Color.white : palette.ink
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                model.activePlanningQuery.sort == sort
                                    ? palette.linkOff
                                    : palette.glassHighlight.opacity(palette.isDark ? 0.13 : 0.42)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(palette.coolBorder.opacity(0.7), lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(.plain)
                .voiceHoverFeedback(cornerRadius: 9, tint: palette.linkOff)
                .accessibilityAddTraits(
                    model.activePlanningQuery.sort == sort ? .isSelected : []
                )
            }

            Divider()
            Text("Direction")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.secondaryInk)
            Picker(
                "Direction",
                selection: Binding(
                    get: { model.activePlanningQuery.direction },
                    set: { direction in
                        model.updatePlanningQuery { $0.direction = direction }
                        model.applyPlanningQuery()
                    }
                )
            ) {
                Text(
                    model.activePlanningQuery.sort.directionTitle(.descending)
                ).tag(VoicePlanningDirection.descending)
                Text(
                    model.activePlanningQuery.sort.directionTitle(.ascending)
                ).tag(VoicePlanningDirection.ascending)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider()
            HStack(spacing: 8) {
                plannerPopoverFooterButton("Reset") {
                    model.updatePlanningQuery { query in
                        query.sort = .frequency
                        query.direction = .descending
                    }
                    model.applyPlanningQuery()
                }

                plannerPopoverFooterButton("Done", prominent: true) {
                    sortPresented = false
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func plannerPopoverFooterButton(
        _ title: String,
        prominent: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(prominent ? Color.white : palette.linkOff)
                .frame(maxWidth: .infinity)
                .frame(height: 31)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            prominent
                                ? palette.linkOff
                                : palette.glassHighlight.opacity(palette.isDark ? 0.14 : 0.46)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    prominent
                                        ? palette.linkOff.opacity(0.92)
                                        : palette.coolBorder.opacity(0.78),
                                    lineWidth: 0.8
                                )
                        )
                )
        }
        .buttonStyle(PlannerPressButtonStyle())
        .voiceHoverFeedback(enabled: enabled, cornerRadius: 8, tint: palette.linkOff)
        .opacity(enabled ? 1 : 0.48)
        .disabled(!enabled)
    }

    private func planningFilterSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.secondaryInk)
            content()
        }
    }

    private func planningAttentionTile(
        _ attention: VoicePlanningAttention,
        tint: Color
    ) -> some View {
        planningFilterTile(
            attention.title,
            count: model.planningAttentionCount(attention),
            selected: model.activePlanningQuery.attention.contains(attention),
            tint: tint
        ) {
            model.updatePlanningQuery { query in
                if query.attention.contains(attention) {
                    query.attention.remove(attention)
                } else {
                    query.attention.insert(attention)
                }
            }
            model.applyPlanningQuery()
        }
    }

    private func planningFilterTile(
        _ title: String,
        count: Int,
        selected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: selected ? .bold : .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(selected ? tint : palette.ink)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: 31)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        selected
                            ? tint.opacity(palette.isDark ? 0.24 : 0.10)
                            : palette.glassHighlight.opacity(palette.isDark ? 0.11 : 0.34)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                selected ? tint.opacity(0.9) : palette.coolBorder.opacity(0.58),
                                lineWidth: selected ? 1.2 : 0.7
                            )
                    )
            )
        }
        .buttonStyle(PlannerPressButtonStyle())
        .voiceHoverFeedback(cornerRadius: 8, tint: tint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var plannerControlBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(palette.glassHighlight.opacity(palette.isDark ? 0.16 : 0.46))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(palette.coolBorder.opacity(0.72), lineWidth: 0.8)
            )
    }

    private func plannerMenuIcon(
        _ symbol: String,
        selected: Bool,
        badge: String? = nil
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            if let badge {
                Image(systemName: badge)
                    .font(.system(size: 5, weight: .bold))
                    .offset(x: 4, y: 4)
            }
        }
        .foregroundStyle(selected ? palette.tealDark : palette.secondaryInk)
        .frame(width: 36, height: 34)
        .contentShape(Rectangle())
        .background(plannerControlBackground)
    }

    private var catalogList: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(model.planningResponse?.catalog.items ?? []) { item in
                    catalogRow(item)
                        .id(item.id)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 9)
        }
        .scrollPosition(
            id: Binding(
                get: {
                    model.planningCatalogScrollAnchor(
                        for: model.planningState.selectedSpecialty
                    )
                },
                set: { itemID in
                    model.updatePlanningCatalogScrollAnchor(
                        itemID,
                        for: model.planningState.selectedSpecialty
                    )
                }
            ),
            anchor: .top
        )
        // The catalog owns the flexible middle of the Activities surface. Letting
        // it absorb the available height keeps Custom activity attached to the
        // fixed selection tray instead of leaving a dead band beneath it.
        .frame(minHeight: 64, maxHeight: .infinity)
    }

    private var careerFocus: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.connectedIdle)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(palette.connectedIdle.opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Job applications")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.ink)
                    Text("Career focus · time only · no result or publication")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(palette.secondaryInk)
                }
                Spacer()
                Text("\(VoicePlanningCareerPolicy.jobApplicationMinutes) min")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(plannerControlBackground)
                    .accessibilityLabel(
                        "\(VoicePlanningCareerPolicy.jobApplicationMinutes) minutes"
                    )
                Button("Add job block", action: model.addJobApplicationsSelection)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.connectedIdle.opacity(palette.isDark ? 0.12 : 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(palette.connectedIdle.opacity(0.32), lineWidth: 0.8)
                    )
            )
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 220)
    }

    @ViewBuilder
    private var customComposer: some View {
        if model.planningCustomPresented {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    plannerCustomTextField(
                        "Required activity title",
                        text: $model.planningCustomTitle
                    )
                    .focused($customTitleFocused)

                    HStack(spacing: 5) {
                        TextField(
                            "40",
                            value: $model.planningCustomMinutes,
                            format: .number
                        )
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(width: 34)
                        Text("min")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.secondaryInk)
                    }
                    .padding(.horizontal, 9)
                    .frame(width: 84, height: 32)
                    .background(plannerControlBackground)
                    .accessibilityLabel("Planned minutes")
                }
                plannerCustomTextField("Optional public URL", text: $model.planningCustomURL)
                plannerCustomTextField(
                    "Optional prompt or context",
                    text: $model.planningCustomPrompt
                )
                HStack(spacing: 8) {
                    plannerPopoverFooterButton("Cancel") {
                        withAnimation(plannerAnimation) {
                            model.planningCustomPresented = false
                        }
                        FloatingPanelController.shared.endPlannerTextEntry()
                    }
                    Spacer()
                    plannerPopoverFooterButton(
                        "Add to selection",
                        prominent: true,
                        enabled: !model.planningCustomTitle
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    ) {
                        withAnimation(plannerAnimation) {
                            model.addCustomPlanningSelection()
                        }
                        FloatingPanelController.shared.endPlannerTextEntry()
                    }
                    .frame(width: 116)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(palette.timerSurface.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(palette.coolBorder.opacity(0.76), lineWidth: 0.8)
                    )
            )
            .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .bottom)))
            .onDisappear {
                FloatingPanelController.shared.endPlannerTextEntry()
            }
        } else if model.planningState.selectedCategory != .career {
            Button {
                withAnimation(plannerAnimation) {
                    model.planningCustomPresented = true
                }
                Task { @MainActor in
                    await Task.yield()
                    FloatingPanelController.shared.beginPlannerTextEntry()
                    customTitleFocused = true
                }
            } label: {
                Label("Custom activity", systemImage: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 27)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlannerPressButtonStyle())
            .voiceHoverFeedback(cornerRadius: 9, tint: palette.teal)
            .foregroundStyle(palette.tealDark)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(palette.coolBorder, style: StrokeStyle(lineWidth: 0.8, dash: [4]))
            )
            .contentShape(Rectangle())
        }
    }

    private func plannerCustomTextField(
        _ placeholder: String,
        text: Binding<String>
    ) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(plannerControlBackground)
    }

    private var selectionTray: some View {
        let railHeight = selectionTrayExpanded
            ? PlannerSelectionTrayPolicy.expandedRailHeight(
                selectionCount: model.planningState.selections.count
            )
            : 30
        return VStack(spacing: 6) {
            selectionRail
                .frame(maxWidth: .infinity)
                .frame(height: railHeight)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.glassHighlight.opacity(palette.isDark ? 0.10 : 0.30))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(
                                    palette.coolBorder.opacity(0.62),
                                    style: StrokeStyle(lineWidth: 0.7, dash: [4])
                                )
                        )
                )

            customComposer

            HStack(spacing: 7) {
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    planningDestinationButton("Standalone", value: "standalone")
                    planningDestinationButton("One session", value: "session")
                }
                .padding(2)
                .frame(width: 170, height: 27)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.glassHighlight.opacity(palette.isDark ? 0.14 : 0.42))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(palette.coolBorder.opacity(0.72), lineWidth: 0.8)
                        )
                )
                Button(action: model.submitPlanningSelection) {
                    Text(
                        model.planningSelectionCount == 0
                            ? "Add activities"
                            : "Add \(model.planningSelectionCount) activities"
                    )
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 116, height: 30)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(palette.linkOff)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(palette.linkOff.opacity(0.92), lineWidth: 0.8)
                            )
                    )
                }
                    .frame(width: 116)
                    .layoutPriority(1)
                    .buttonStyle(PlannerPressButtonStyle())
                    .voiceHoverFeedback(
                        enabled: !model.planningState.selections.isEmpty
                            && !model.planningMutationInFlight
                            && model.planningResponse?.workbench != nil,
                        cornerRadius: 8,
                        tint: palette.linkOff
                    )
                    .opacity(
                        model.planningState.selections.isEmpty
                            || model.planningMutationInFlight
                            || model.planningResponse?.workbench == nil
                            ? 0.46 : 1
                    )
                    .disabled(
                        model.planningState.selections.isEmpty
                            || model.planningMutationInFlight
                            || model.planningResponse?.workbench == nil
                    )
            }
            .frame(height: 30)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(palette.timerSurface.opacity(palette.isDark ? 0.72 : 0.48))
        .animation(plannerAnimation, value: selectionTrayExpanded)
        .onChange(of: model.planningState.selections.count) { _, count in
            if count <= PlannerSelectionTrayPolicy.collapsedVisibleCount {
                selectionTrayExpanded = false
            }
        }
    }

    @ViewBuilder
    private var selectionRail: some View {
        let selections = model.planningState.selections
        if selections.isEmpty {
            Text("Selected activities will appear here")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.secondaryInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if selectionTrayExpanded {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 116, maximum: 172),
                            spacing: 5
                        ),
                    ],
                    spacing: 5
                ) {
                    ForEach(selections) { selection in
                        selectionChip(selection, fillsWidth: true)
                    }
                }
                .padding(6)
            }
            .scrollDisabled(
                !PlannerSelectionTrayPolicy.expandedContentScrolls(
                    selectionCount: selections.count
                )
            )
            .overlay(alignment: .topTrailing) {
                selectionDisclosureButton(
                    label: "Collapse selections",
                    symbol: "chevron.down"
                )
                .padding(5)
            }
            .accessibilityLabel("Selected activities, expanded")
        } else {
            HStack(spacing: 5) {
                ForEach(
                    Array(
                        selections.prefix(
                            PlannerSelectionTrayPolicy.collapsedVisibleCount
                        )
                    )
                ) { selection in
                    selectionChip(selection, fillsWidth: true)
                }
                let hiddenCount = PlannerSelectionTrayPolicy.hiddenCount(
                    selectionCount: selections.count
                )
                if hiddenCount > 0 {
                    Button {
                        selectionTrayExpanded = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("+\(hiddenCount) more")
                            Image(systemName: "chevron.up")
                        }
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(palette.tealDark)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(
                            Capsule()
                                .fill(palette.teal.opacity(0.14))
                                .overlay(
                                    Capsule().stroke(
                                        palette.teal.opacity(0.52),
                                        lineWidth: 0.8
                                    )
                                )
                        )
                    }
                    .buttonStyle(PlannerPressButtonStyle())
                    .voiceHoverFeedback(cornerRadius: 13, tint: palette.teal)
                    .accessibilityLabel("Show \(hiddenCount) more selected activities")
                }
            }
            .padding(.horizontal, 5)
            .accessibilityLabel("Selected activities")
        }
    }

    private func selectionChip(
        _ selection: VoicePlanningSelectionDraft,
        fillsWidth: Bool
    ) -> some View {
        Button {
            model.removePlanningSelection(selection.id)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "circle.grid.2x3.fill")
                    .font(.system(size: 7, weight: .semibold))
                Text(selection.title)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: 26)
            .contentShape(Capsule())
            .background(
                Capsule()
                    .fill(
                        palette.teal.opacity(
                            palette.isDark ? 0.22 : 0.12
                        )
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                palette.teal.opacity(0.42),
                                lineWidth: 0.7
                            )
                    )
            )
        }
        .buttonStyle(PlannerPressButtonStyle())
        .voiceHoverFeedback(cornerRadius: 13, tint: palette.teal)
        .accessibilityLabel("Deselect \(selection.title)")
    }

    private func selectionDisclosureButton(
        label: String,
        symbol: String
    ) -> some View {
        Button {
            selectionTrayExpanded.toggle()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.tealDark)
                .frame(width: 24, height: 24)
                .background(Circle().fill(palette.timerSurface.opacity(0.92)))
        }
        .buttonStyle(PlannerPressButtonStyle())
        .voiceHoverFeedback(cornerRadius: 12, tint: palette.teal)
        .accessibilityLabel(label)
    }

    private func planningDestinationButton(_ title: String, value: String) -> some View {
        let selected = model.planningDestination == value
        return Button {
            withAnimation(plannerAnimation) {
                model.planningDestination = value
            }
        } label: {
            Text(title)
                .font(.system(size: 9, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? Color.white : palette.secondaryInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? palette.linkOff : Color.clear)
                )
        }
        .buttonStyle(PlannerPressButtonStyle())
        .voiceHoverFeedback(cornerRadius: 6, tint: palette.linkOff)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fullSessionComposer: some View {
        VStack(spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build a full interview session")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.ink)
                    Text("Highest-frequency eligible work · 6 coding by default")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(palette.secondaryInk)
                }
                Spacer()
            }
            HStack(spacing: 7) {
                fullSessionCard(
                    "Coding",
                    mark: "C",
                    minutes: VoicePlanningFullSessionPolicy.codingMinutes,
                    tint: categoryTint(.leetcode),
                    value: $model.planningFullCoding
                )
                fullSessionCard(
                    "System design",
                    mark: "S",
                    minutes: VoicePlanningFullSessionPolicy.interviewMinutes,
                    tint: categoryTint(.systemDesign),
                    value: $model.planningFullSystemDesign
                )
                fullSessionCard(
                    "Behavioral",
                    mark: "B",
                    minutes: VoicePlanningFullSessionPolicy.interviewMinutes,
                    tint: categoryTint(.behavioral),
                    value: $model.planningFullBehavioral
                )
            }
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("SESSION COUNTDOWN")
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.8)
                        .foregroundStyle(palette.connectedIdle)
                    Text(planningFullSessionBreakdown)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(planningFullSessionDurationLabel)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 62)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.ink.opacity(palette.isDark ? 0.92 : 0.96))
            )

            VStack(alignment: .leading, spacing: 0) {
                Text("HOW INTERVIEW ARC BUILDS IT")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(palette.secondaryInk)
                    .padding(.bottom, 4)

                fullSessionGuideRow(
                    symbol: "clock.arrow.circlepath",
                    title: "Reviews first",
                    detail: "Up to two eligible due reviews lead the session."
                )
                Divider().overlay(palette.divider.opacity(0.5))
                fullSessionGuideRow(
                    symbol: "chart.bar.fill",
                    title: "Frequency-based fill",
                    detail: "Open slots use new high-frequency questions."
                )
                Divider().overlay(palette.divider.opacity(0.5))
                fullSessionGuideRow(
                    symbol: "lock.fill",
                    title: "Adjust now, then lock",
                    detail: "The recipe locks after timing or activity work begins."
                )
                Divider().overlay(palette.divider.opacity(0.5))
                fullSessionGuideRow(
                    symbol: "rectangle.stack.fill",
                    title: "One coherent session",
                    detail: "Every selected activity shares one session countdown."
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.glassHighlight.opacity(palette.isDark ? 0.10 : 0.34))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(palette.coolBorder.opacity(0.64), lineWidth: 0.8)
                    )
            )

            Button(action: model.createPlanningFullSession) {
                HStack {
                    if model.planningMutationInFlight {
                        ProgressView().controlSize(.small)
                    }
                    Text("Create full session")
                        .font(.system(size: 11, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .contentShape(Rectangle())
                .foregroundStyle(Color.white)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(palette.linkOff)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(palette.linkOff.opacity(0.92), lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(PlannerPressButtonStyle())
            .voiceHoverFeedback(
                enabled: !model.planningMutationInFlight
                    && model.planningFullCoding
                        + model.planningFullSystemDesign
                        + model.planningFullBehavioral > 0,
                cornerRadius: 9,
                tint: palette.linkOff
            )
            .opacity(
                model.planningMutationInFlight
                    || model.planningFullCoding
                        + model.planningFullSystemDesign
                        + model.planningFullBehavioral == 0
                    ? 0.46 : 1
            )
            .disabled(
                model.planningMutationInFlight
                    || model.planningFullCoding
                        + model.planningFullSystemDesign
                        + model.planningFullBehavioral == 0
            )
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var planningFullSessionBreakdown: String {
        let coding = model.planningFullCoding * VoicePlanningFullSessionPolicy.codingMinutes
        let systemDesign = model.planningFullSystemDesign
            * VoicePlanningFullSessionPolicy.interviewMinutes
        let behavioral = model.planningFullBehavioral
            * VoicePlanningFullSessionPolicy.interviewMinutes
        return "\(coding)m coding + \(systemDesign)m system design + \(behavioral)m behavioral"
    }

    private var planningFullSessionDurationLabel: String {
        let minutes = model.planningFullSessionMinutes
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) min" }
        if remainder == 0 { return "\(hours) hr" }
        return "\(hours)h \(remainder)m"
    }

    private func fullSessionGuideRow(
        symbol: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.linkOff)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(palette.linkOff.opacity(palette.isDark ? 0.20 : 0.08))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.ink)
                Text(detail)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(palette.secondaryInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
    }

    private func fullSessionCard(
        _ title: String,
        mark: String,
        minutes: Int,
        tint: Color,
        value: Binding<Int>
    ) -> some View {
        VStack(spacing: 7) {
            Text(mark)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(palette.isDark ? 0.20 : 0.09))
                )
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
            Text("\(minutes)m each")
                .font(.system(size: 8))
                .foregroundStyle(palette.secondaryInk)
            HStack(spacing: 8) {
                fullSessionCountButton(
                    "minus",
                    label: "Remove one \(title)",
                    enabled: value.wrappedValue > 0
                ) {
                    value.wrappedValue -= 1
                }
                Text("\(value.wrappedValue)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .frame(minWidth: 24)
                fullSessionCountButton(
                    "plus",
                    label: "Add one \(title)",
                    enabled: value.wrappedValue < 20
                ) {
                    value.wrappedValue += 1
                }
            }
            .accessibilityLabel("\(title) count")
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 128)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(palette.isDark ? 0.13 : 0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tint.opacity(0.34), lineWidth: 0.8)
                )
        )
        .voiceHoverFeedback(cornerRadius: 12, tint: tint)
    }

    private func fullSessionCountButton(
        _ symbol: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 25, height: 25)
                .background(plannerControlBackground)
        }
        .buttonStyle(PlannerPressButtonStyle())
        .voiceHoverFeedback(enabled: enabled, cornerRadius: 8, tint: palette.linkOff)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func catalogRow(_ item: VoicePlanningCatalogItem) -> some View {
        let draftID = "practice:\(model.planningState.selectedSpecialty.rawValue):\(item.id)"
        let selected = model.planningState.selections.contains { $0.id == draftID }
        return Button {
            model.togglePlanningSelection(item)
        } label: {
            HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(
                                selected
                                    ? palette.linkOff
                                    : palette.coolBorder.opacity(0.9),
                                lineWidth: selected ? 1.2 : 0.8
                            )
                        if selected {
                            Circle().fill(palette.linkOff)
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: 17, height: 17)
                    .accessibilityHidden(true)

                    Text(model.planningState.selectedSpecialty == .leetcode ? "C" : "S")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(categoryTint(model.planningState.selectedCategory))
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    categoryTint(model.planningState.selectedCategory)
                                        .opacity(palette.isDark ? 0.20 : 0.09)
                                )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(item.eligible ? palette.ink : palette.secondaryInk)
                            .lineLimit(1)
                        Text(
                            [
                                item.difficulty?.capitalized,
                                item.acceptanceRate.map { "\(Int($0.rounded()))% accepted" },
                                "\(item.targetMinutes)m",
                                item.disabledReason,
                            ]
                            .compactMap { $0 }
                            .joined(separator: " · ")
                        )
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(palette.secondaryInk)
                        .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "flag")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondaryInk)
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        selected
                            ? palette.linkOff.opacity(palette.isDark ? 0.23 : 0.09)
                            : palette.glassHighlight.opacity(palette.isDark ? 0.12 : 0.38)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                selected
                                    ? palette.linkOff.opacity(0.72)
                                    : palette.coolBorder.opacity(0.65),
                                lineWidth: selected ? 1.0 : 0.8
                            )
                    )
            )
        }
        .buttonStyle(PlannerPressButtonStyle())
        .disabled(!item.eligible)
        .voiceHoverFeedback(
            enabled: item.eligible,
            cornerRadius: 10,
            tint: palette.linkOff
        )
        .opacity(item.eligible ? 1 : 0.66)
        .accessibilityElement(children: .contain)
        .accessibilityValue(selected ? "Selected" : (item.disabledReason ?? "Not selected"))
    }

    private func categoryButton(
        _ title: String,
        value: VoicePlanningCategory
    ) -> some View {
        let tint = categoryTint(value)
        let selected = model.planningState.selectedCategory == value
        return Button {
            withAnimation(plannerAnimation) {
                model.setPlanningCategory(value)
            }
        } label: {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .contentShape(Rectangle())
                .foregroundStyle(selected ? tint : palette.secondaryInk)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(
                            selected
                                ? tint.opacity(palette.isDark ? 0.22 : 0.09)
                                : Color.clear
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(
                                    tint.opacity(selected ? 0.92 : 0.42),
                                    lineWidth: selected ? 1.2 : 0.7
                                )
                        )
                )
        }
        .buttonStyle(PlannerPressButtonStyle())
        .voiceHoverFeedback(cornerRadius: 9, tint: tint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func categoryTint(_ category: VoicePlanningCategory) -> Color {
        switch category {
        case .leetcode: palette.warning
        case .systemDesign: palette.linkOff
        case .behavioral: palette.tealDark
        case .career: .purple
        }
    }

    private func planningSectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(palette.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
    }

    private func sessionCard(
        _ session: VoicePlanningCurrentSession,
        activities: [VoicePlanningCurrentActivity],
        now: Date
    ) -> some View {
        let status = model.planningSessionStatus(id: session.id)
        let canRemove = status == .upcoming
            && activities.allSatisfy {
                model.planningActivityStatus(
                    id: $0.id,
                    declaredStatus: $0.status
                ) == .upcoming
            }
        let collapsed = collapsedSessionIDs.contains(session.id)

        return VStack(spacing: 7) {
            HStack(spacing: 9) {
                Button {
                    withAnimation(plannerAnimation) {
                        if collapsed {
                            collapsedSessionIDs.remove(session.id)
                        } else {
                            collapsedSessionIDs.insert(session.id)
                        }
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "timer")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.tealDark)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(palette.teal.opacity(palette.isDark ? 0.20 : 0.09))
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.label)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(palette.ink)
                                .lineLimit(1)
                            Text("\(activities.count) activities · \(session.allocatedSeconds / 60) min")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(palette.secondaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.secondaryInk)
                            .rotationEffect(.degrees(collapsed ? -90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlannerPressButtonStyle())
                .voiceHoverFeedback(cornerRadius: 8, tint: palette.teal)
                .accessibilityLabel(
                    "\(collapsed ? "Expand" : "Collapse") \(session.label)"
                )
                statusBadge(status)
                plannerIconButton(
                    "trash",
                    label: "Remove \(session.label)",
                    enabled: canRemove
                ) {
                    model.removePlanningItem(kind: "session", id: session.id)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.teal.opacity(palette.isDark ? 0.16 : 0.07))
            )

            VStack(spacing: 0) {
                if !activities.isEmpty, !collapsed {
                    HStack(alignment: .top, spacing: 7) {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(palette.teal.opacity(0.34))
                            .frame(width: 2)
                            .padding(.vertical, 7)
                        VStack(spacing: 4) {
                            ForEach(activities) { activity in
                                currentActivityRow(activity, now: now, nested: true)
                            }
                        }
                    }
                    .padding(.leading, 12)
                    .transition(.move(edge: .top))
                }
            }
            .clipped()
        }
        .animation(plannerAnimation, value: collapsed)
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.glassHighlight.opacity(palette.isDark ? 0.13 : 0.40))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            status == .running
                                ? palette.connectedIdle.opacity(0.82)
                                : palette.coolBorder.opacity(0.66),
                            lineWidth: status == .running ? 1.2 : 0.8
                        )
                )
        )
    }

    private func currentActivityRow(
        _ activity: VoicePlanningCurrentActivity,
        now: Date,
        nested: Bool = false
    ) -> some View {
        let status = model.planningActivityStatus(
            id: activity.id,
            declaredStatus: activity.status
        )
        let liveTime = model.planningActivityTime(id: activity.id, at: now)
        return HStack(spacing: 9) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.tealDark)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Text("\(activity.allocatedSeconds / 60) min")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(palette.secondaryInk)
            }
            Spacer()
            if let liveTime {
                Text(liveTime)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(palette.tealDark)
            } else {
                statusBadge(status)
            }
            planningTimerButton(
                id: activity.id,
                title: activity.title,
                status: status
            )
            plannerIconButton(
                "trash",
                label: "Remove \(activity.title)",
                enabled: status == .upcoming
            ) {
                model.removePlanningItem(kind: "activity", id: activity.id)
            }
        }
        .padding(.horizontal, nested ? 9 : 10)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    nested
                        ? palette.timerSurface.opacity(palette.isDark ? 0.64 : 0.50)
                        : palette.glassHighlight.opacity(palette.isDark ? 0.13 : 0.40)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            nested
                                ? palette.coolBorder.opacity(0.42)
                                : Color.clear,
                            lineWidth: 0.7
                        )
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func currentFocusRow(
        _ focus: VoicePlanningCurrentFocus,
        now: Date
    ) -> some View {
        let status = model.planningActivityStatus(id: focus.id)
        let liveTime = model.planningActivityTime(id: focus.id, at: now)
        return HStack(spacing: 9) {
            Image(systemName: "briefcase")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.purple)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.purple.opacity(palette.isDark ? 0.20 : 0.09))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(focus.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Text("Career focus · \(focus.plannedSeconds / 60) min")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(palette.secondaryInk)
            }
            Spacer()
            if let liveTime {
                Text(liveTime)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(Color.purple)
            } else {
                statusBadge(status)
            }
            planningTimerButton(
                id: focus.id,
                title: focus.title,
                status: status
            )
            plannerIconButton(
                "trash",
                label: "Remove \(focus.title)",
                enabled: status == .upcoming
            ) {
                model.removePlanningItem(kind: "focus", id: focus.id)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.purple.opacity(palette.isDark ? 0.11 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.purple.opacity(0.26), lineWidth: 0.8)
                )
        )
    }

    private func planningTimerButton(
        id: String,
        title: String,
        status: VoicePlanningCurrentStatus
    ) -> some View {
        plannerIconButton(
            status == .running ? "pause.fill" : "play.fill",
            label: status == .running ? "Pause \(title)" : "Start \(title)",
            enabled: model.canTogglePlanningActivityTimer(
                id: id,
                status: status
            ),
            selected: status == .running
        ) {
            model.togglePlanningActivityTimer(id: id, status: status)
        }
    }

    private func statusBadge(_ status: VoicePlanningCurrentStatus) -> some View {
        Text(status.title)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(
                status == .running ? palette.connectedIdle : palette.secondaryInk
            )
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        status == .running
                            ? palette.connectedIdle.opacity(0.12)
                            : palette.timerSurface.opacity(0.5)
                    )
            )
    }

    private func upperTab(
        _ title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let tint = title == "Plan today" ? palette.linkOff : palette.tealDark
        return Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .contentShape(Rectangle())
                .foregroundStyle(selected ? tint : palette.secondaryInk)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selected ? tint : Color.clear)
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                }
        }
        .buttonStyle(PlannerPressButtonStyle())
        .voiceHoverFeedback(cornerRadius: 8, tint: tint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func plannerIconButton(
        _ symbol: String,
        label: String,
        enabled: Bool = true,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 27, height: 27)
                .foregroundStyle(selected ? palette.tealDark : palette.secondaryInk)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(
                            selected
                                ? palette.teal.opacity(palette.isDark ? 0.24 : 0.12)
                                : palette.glassHighlight.opacity(palette.isDark ? 0.14 : 0.42)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(palette.coolBorder.opacity(0.68), lineWidth: 0.7)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .voiceHoverFeedback(enabled: enabled, cornerRadius: 9, tint: palette.teal)
        .help(label)
        .accessibilityLabel(label)
    }

    private var plannerAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.10)
            : .easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds)
    }
}

private struct FloatingTimerInstrumentPanel: View {
    @ObservedObject var model: VoiceBridgeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let instrument: VoiceTimerInstrument
    let contentHeight: CGFloat

    private var palette: VoiceWidgetPalette { model.widgetPalette }

    private var availableActivities: [VoiceTimerActivity] {
        instrument.activities.filter { $0.id != instrument.activity?.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                upperSurfaceTab("Focus", symbol: "timer", selected: true) {}
                upperSurfaceTab(
                    "Plan today",
                    symbol: "calendar.badge.plus",
                    selected: false,
                    action: model.showPlanner
                )
            }
            .padding(5)
            .background(palette.timerSurface.opacity(palette.isDark ? 0.74 : 0.42))

            Divider().overlay(palette.divider.opacity(0.65))

            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                VStack(spacing: 0) {
                    if let session = instrument.session,
                       !(model.dynamicRecordingInterfaceActive && model.isRecording) {
                        timerRow(
                            eyebrow: "SESSION",
                            title: session.label,
                            time: sessionTime(session, at: timeline.date),
                            isRunning: session.timer.isRunning,
                            toggleLabel: session.timer.startedAt == nil
                                ? "Start session"
                                : (session.timer.isRunning ? "Pause session" : "Resume session"),
                            canFinish: session.timer.startedAt != nil,
                            toggle: {
                                model.performTimerAction(
                                    subjectID: session.id,
                                    kind: "session",
                                    action: session.timer.isRunning ? "pause" : "start"
                                )
                            },
                            finish: {
                                model.requestFinishSession(session)
                            }
                        )
                    }
                    if instrument.session != nil,
                       !(model.dynamicRecordingInterfaceActive && model.isRecording) {
                        Divider().overlay(palette.divider.opacity(0.65))
                    }
                    if let activity = instrument.activity {
                        timerRow(
                            eyebrow: activity.isFocusBlock ? "CAREER FOCUS" : "ACTIVITY",
                            title: activity.title,
                            time: activityTime(activity, at: timeline.date),
                            isRunning: activity.timer?.isRunning == true,
                            toggleLabel: activity.timer?.startedAt == nil
                                ? "Start activity"
                                : (activity.timer?.isRunning == true ? "Pause activity" : "Resume activity"),
                            canFinish: activity.timer?.startedAt != nil,
                            toggle: {
                                model.performTimerAction(
                                    subjectID: activity.id,
                                    kind: "activity",
                                    action: activity.timer?.isRunning == true ? "pause" : "start"
                                )
                            },
                            finish: { model.openFinishDrawer(for: activity) }
                        )
                    } else {
                        emptyActivityRow
                    }
                }
            }

            if let message = model.timerMutationMessage {
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.warning)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(palette.warning.opacity(0.07))
            }

            Group {
                if model.sessionFinishResolutionRequested {
                    VStack(spacing: 0) {
                        Divider().overlay(palette.divider.opacity(0.65))
                        sessionFinishAttention
                    }
                    .transition(drawerTransition)
                } else if let activity = model.finishingActivity {
                    VStack(spacing: 0) {
                        Divider().overlay(palette.divider.opacity(0.65))
                        finishDrawer(activity)
                    }
                    .transition(drawerTransition)
                } else if model.activityPickerExpanded {
                    VStack(spacing: 0) {
                        Divider().overlay(palette.divider.opacity(0.65))
                        activityPicker
                    }
                    .transition(drawerTransition)
                } else if !availableActivities.isEmpty {
                    VStack(spacing: 0) {
                        Divider().overlay(palette.divider.opacity(0.65))
                        Button(action: model.toggleActivityPicker) {
                            HStack(spacing: 7) {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(
                                    instrument.activity == nil
                                        ? "Start an activity"
                                        : "Choose another activity"
                                )
                                .font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(palette.tealDark)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .voiceHoverFeedback(cornerRadius: 9, tint: palette.teal)
                    }
                    .transition(drawerTransition)
                }
            }
            .animation(drawerAnimation, value: model.finishingActivityID)
            .animation(drawerAnimation, value: model.activityPickerExpanded)
            .animation(drawerAnimation, value: model.sessionFinishResolutionRequested)
        }
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            palette.glassHighlight.opacity(palette.isDark ? 0.76 : 0.54),
                            palette.glass.opacity(palette.isDark ? 0.94 : 0.70),
                            palette.timerSurface.opacity(palette.isDark ? 0.72 : 0.30),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(palette.coolBorder.opacity(0.90), lineWidth: 0.9)
                )
                .shadow(color: palette.coolShadow, radius: 8, y: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .frame(
            height: contentHeight,
            alignment: .bottom
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interview Arc timers")
    }

    private func upperSurfaceTab(
        _ title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .foregroundStyle(selected ? palette.tealDark : palette.secondaryInk)
                .contentShape(Rectangle())
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(selected ? palette.tealDark : Color.clear)
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                }
        }
        .buttonStyle(PlannerPressButtonStyle())
        .voiceHoverFeedback(cornerRadius: 9, tint: palette.teal)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var drawerAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.10)
            : .easeInOut(duration: FloatingWidgetMotionPolicy.durationSeconds)
    }

    private var drawerTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .opacity.combined(
            with: .scale(scale: 0.985, anchor: .bottom)
        )
    }

    private func timerRow(
        eyebrow: String,
        title: String,
        time: String,
        isRunning: Bool,
        toggleLabel: String,
        canFinish: Bool,
        toggle: @escaping () -> Void,
        finish: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(palette.tealDark)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
            }
            .frame(width: 190, alignment: .leading)

            Text(time)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(palette.tealDark)
                .frame(width: 104, alignment: .trailing)

            HStack(spacing: 7) {
                timerControl(
                    symbol: isRunning ? "pause.fill" : "play.fill",
                    label: toggleLabel,
                    enabled: !model.timerMutationInFlight,
                    action: toggle
                )
                timerControl(
                    symbol: "stop.fill",
                    label: "Finish \(eyebrow.lowercased())",
                    enabled: canFinish && !model.timerMutationInFlight,
                    action: finish
                )
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 72)
    }

    private var emptyActivityRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ACTIVITY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(palette.tealDark)
                Text("No activity running")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.ink)
            }
            .frame(width: 190, alignment: .leading)
            Text("—")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.secondaryInk)
                .frame(width: 104, alignment: .trailing)
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 14)
        .frame(height: 72)
    }

    private func timerControl(
        symbol: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(TimerInstrumentButtonStyle(tint: palette.teal, palette: palette))
        .foregroundStyle(enabled ? palette.ink : palette.secondaryInk.opacity(0.45))
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }

    private var sessionFinishAttention: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    "\(model.sessionFinishBlockers.count) "
                        + (model.sessionFinishBlockers.count == 1 ? "activity needs" : "activities need")
                        + " a result"
                )
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(palette.ink)
                Text("Review the result choices in the menu-bar popover.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.secondaryInk)
            }
            Spacer(minLength: 8)
            Button("Review") {
                model.requestSessionFinishReview()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(palette.tealDark)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(palette.teal.opacity(palette.isDark ? 0.22 : 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(palette.teal.opacity(0.42), lineWidth: 0.8)
                    )
            )
            .help("Open the Interview Arc Voice menu-bar popover to review results")
            Button(action: model.cancelSessionFinishResolution) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .voiceHoverFeedback(cornerRadius: 9)
            .help("Cancel finishing session")
        }
        .padding(.horizontal, 12)
        .frame(height: 70)
        .background(palette.warning.opacity(0.07))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(model.sessionFinishBlockers.count) activities need results before the session can finish"
        )
    }

    private func finishDrawer(_ activity: VoiceTimerActivity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FINISH ACTIVITY")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(palette.tealDark)
                    Text(activity.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer()
                Button(action: model.cancelFinishDrawer) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .voiceHoverFeedback(cornerRadius: 9)
                .help("Cancel finish")
            }

            HStack(spacing: 7) {
                outcomeButton(.solved, label: "Solved", color: Color(red: 0.48, green: 0.63, blue: 0.10))
                outcomeButton(
                    .solvedAfterReviewingApproach,
                    label: "With help",
                    color: Color(red: 0.40, green: 0.46, blue: 0.80)
                )
                outcomeButton(.failed, label: "Failed", color: Color(red: 0.82, green: 0.35, blue: 0.24))
                if activity.questionId != nil {
                    Button {
                        model.finishStarred.toggle()
                    } label: {
                        Image(systemName: model.finishStarred ? "star.fill" : "star")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 30, height: 28)
                    }
                    .buttonStyle(
                        TimerInstrumentButtonStyle(
                            tint: Color(red: 0.77, green: 0.61, blue: 0.12),
                            palette: palette,
                            selected: model.finishStarred
                        )
                    )
                    .foregroundStyle(Color(red: 0.46, green: 0.36, blue: 0.06))
                    .help(model.finishStarred ? "Remove star" : "Star for later")
                    .accessibilityLabel(model.finishStarred ? "Starred" : "Not starred")
                }
            }

            Button(action: model.confirmFinishActivity) {
                HStack {
                    if model.timerMutationInFlight {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text("Finish activity")
                }
                .font(.system(size: 11, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        model.finishOutcome == nil
                            ? palette.secondaryInk.opacity(0.28)
                            : palette.tealDark
                    )
            )
            .disabled(model.finishOutcome == nil || model.timerMutationInFlight)
            .voiceHoverFeedback(
                enabled: model.finishOutcome != nil && !model.timerMutationInFlight,
                cornerRadius: 9,
                tint: palette.teal
            )
        }
        .padding(12)
        .background(palette.timerSurface.opacity(palette.isDark ? 0.72 : 0.46))
    }

    private func outcomeButton(
        _ outcome: VoicePracticeOutcome,
        label: String,
        color: Color
    ) -> some View {
        Button {
            model.finishOutcome = outcome
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
        }
        .buttonStyle(
            TimerInstrumentButtonStyle(
                tint: color,
                palette: palette,
                selected: model.finishOutcome == outcome
            )
        )
        .foregroundStyle(color)
        .accessibilityLabel(label)
    }

    private var activityPicker: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CHOOSE ACTIVITY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(palette.tealDark)
                Spacer()
                Button(action: model.toggleActivityPicker) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .voiceHoverFeedback(cornerRadius: 9)
                .help("Close activity picker")
            }
            .padding(.horizontal, 12)
            .frame(height: 32)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(availableActivities) { activity in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(activity.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(palette.ink)
                                    .lineLimit(1)
                                Text(activity.timer?.startedAt == nil ? "Not started" : "Paused")
                                    .font(.system(size: 9))
                                    .foregroundStyle(palette.secondaryInk)
                            }
                            Spacer()
                            if activity.type == "leetcode", activity.url != nil {
                                pickerButton(
                                    symbol: "arrow.up.right.square",
                                    label: "Start and open",
                                    action: { model.startActivity(activity, openProblem: true) }
                                )
                            }
                            pickerButton(
                                symbol: "play.fill",
                                label: activity.timer?.startedAt == nil ? "Start" : "Resume",
                                action: { model.startActivity(activity, openProblem: false) }
                            )
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 43)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(palette.glassHighlight.opacity(palette.isDark ? 0.18 : 0.40))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(palette.coolBorder.opacity(0.65), lineWidth: 0.7)
                                )
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
            }
        }
        .background(palette.timerSurface.opacity(palette.isDark ? 0.62 : 0.34))
    }

    private func pickerButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 27, height: 27)
        }
        .buttonStyle(TimerInstrumentButtonStyle(tint: palette.teal, palette: palette))
        .foregroundStyle(palette.tealDark)
        .disabled(model.timerMutationInFlight)
        .help(label)
        .accessibilityLabel(label)
    }

    private func sessionTime(_ session: VoiceTimerSession, at now: Date) -> String {
        let elapsed = model.elapsedSeconds(for: session.timer, now: now)
        let remaining = session.allocatedSeconds - elapsed
        return remaining >= 0
            ? "\(timerClock(remaining)) left"
            : "+\(timerClock(abs(remaining)))"
    }

    private func activityTime(_ activity: VoiceTimerActivity, at now: Date) -> String {
        guard let timer = activity.timer else { return "00:00:00" }
        return timerClock(model.elapsedSeconds(for: timer, now: now))
    }

    private func timerClock(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        return String(
            format: "%02d:%02d:%02d",
            safe / 3_600,
            (safe % 3_600) / 60,
            safe % 60
        )
    }
}

private struct TimerInstrumentButtonStyle: ButtonStyle {
    let tint: Color
    let palette: VoiceWidgetPalette
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        selected
                            ? tint.opacity(configuration.isPressed ? 0.24 : 0.16)
                            : palette.glassHighlight.opacity(
                                configuration.isPressed
                                    ? (palette.isDark ? 0.10 : 0.26)
                                    : (palette.isDark ? 0.16 : 0.46)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(
                                selected ? tint.opacity(0.72) : palette.coolBorder.opacity(0.72),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(configuration.isPressed ? 0.06 : 0.12),
                        radius: configuration.isPressed ? 1 : 2,
                        y: configuration.isPressed ? 0 : 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PlannerPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct FailureRecoveryPopover: View {
    @ObservedObject var model: VoiceBridgeModel
    @State private var confirmingRecoveryPromotion = false
    private var palette: VoiceWidgetPalette { model.widgetPalette }

    var body: some View {
        if let failure = model.failureNotice {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    ZStack {
                        Circle().fill(palette.warning.opacity(0.10))
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.warning)
                    }
                    .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.title)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                        Text(failure.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(action: model.dismissFailure) {
                        Image(systemName: "xmark")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .voiceHoverFeedback(cornerRadius: 7)
                    .accessibilityLabel("Dismiss failure")
                }

                VStack(spacing: 6) {
                    if model.failureRecoveryTranscriptCanBeUsed {
                        Button {
                            confirmingRecoveryPromotion = true
                        } label: {
                            Label(
                                "Use this transcript",
                                systemImage: "checkmark.circle.fill"
                            )
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.tealDark)
                        .voiceHoverFeedback(
                            cornerRadius: 8,
                            tint: palette.teal
                        )
                    }
                    ForEach(model.availableFailureActions, id: \.self) { action in
                        if action == .openSettings {
                            if action == model.availableFailureActions.first
                                && !model.failureRecoveryTranscriptCanBeUsed {
                                settingsActionLink(action)
                                    .buttonStyle(.borderedProminent)
                            } else {
                                settingsActionLink(action)
                                    .buttonStyle(.bordered)
                            }
                        } else if action == model.availableFailureActions.first
                            && !model.failureRecoveryTranscriptCanBeUsed {
                            failureActionButton(action)
                                .buttonStyle(.borderedProminent)
                        } else {
                            failureActionButton(action)
                                .buttonStyle(.bordered)
                        }
                    }
                }

                DisclosureGroup("Details") {
                    Text(failure.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
                .font(.caption2.weight(.semibold))
            }
            .padding(11)
            .frame(width: 232)
            .confirmationDialog(
                "Use this possibly incomplete transcript?",
                isPresented: $confirmingRecoveryPromotion,
                titleVisibility: .visible
            ) {
                Button("Use this transcript") {
                    model.performFailurePopoverAction(
                        .useRecoveryTranscript
                    )
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Voice will use the exact text shown and the retained original recording. If linked, Voice will insert the normal Voice v2 metadata and register the capture as pending so the specialist can Attach it, Exclude it, or ask you to decide."
                )
            }
        }
    }

    private func failureActionButton(_ action: VoiceFailureAction) -> some View {
        Button {
            model.performFailurePopoverAction(action)
        } label: {
            Label(actionLabel(action), systemImage: actionSymbol(action))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .tint(palette.tealDark)
        .voiceHoverFeedback(cornerRadius: 8, tint: palette.teal)
    }

    private func settingsActionLink(_ action: VoiceFailureAction) -> some View {
        ForegroundSettingsLink {
            Label(actionLabel(action), systemImage: actionSymbol(action))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .tint(palette.tealDark)
        .voiceHoverFeedback(cornerRadius: 8, tint: palette.teal)
    }

    private func actionSymbol(_ action: VoiceFailureAction) -> String {
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

    private func actionLabel(_ action: VoiceFailureAction) -> String {
        switch action {
        case .recordAgain: "Record again"
        case .retryTranscription: "Retry"
        case .playRecording: "Play"
        case .saveRecording: "Save"
        case .useRecoveryTranscript: "Use this transcript"
        case .insertAgain: "Insert again"
        case .enableAccessibility: "Enable access"
        case .openSettings: "Settings"
        case .retryConnection: "Retry connection"
        }
    }
}

private struct LayeredWidgetButtonStyle: ButtonStyle {
    let tint: Color
    let palette: VoiceWidgetPalette
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.glassHighlight.opacity(
                                    configuration.isPressed
                                        ? (palette.isDark ? 0.10 : 0.16)
                                        : (palette.isDark ? 0.18 : 0.34)
                                ),
                                tint.opacity(configuration.isPressed ? 0.18 : 0.10),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle().stroke(
                            palette.glassHighlight.opacity(palette.isDark ? 0.24 : 0.38),
                            lineWidth: 0.7
                        )
                    )
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
    let state: VoiceLinkPresentationState
    let color: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            Image(systemName: "link")
                .font(.system(size: size, weight: .semibold))
            if state == .off {
                Capsule(style: .continuous)
                    .fill(Color.black)
                    .frame(width: 3.2, height: size + 8)
                    .rotationEffect(.degrees(42))
                    .blendMode(.destinationOut)
            }
        }
        .compositingGroup()
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
    let color: Color
    let historical: Bool
    private let idleShape: [Float] = [
        -48, -39, -45, -34, -42, -37, -31,
        -41, -35, -44, -38, -47, -40, -49,
    ]

    var body: some View {
        GeometryReader { geometry in
            let barWidth = FloatingWidgetWindowPolicy.recordingWaveformBarWidth(
                availableWidth: geometry.size.width
            )
            let barSpacing = FloatingWidgetWindowPolicy.recordingWaveformBarSpacing(
                availableWidth: geometry.size.width
            )
            HStack(spacing: barSpacing) {
                ForEach(Array(displayedLevels.enumerated()), id: \.offset) { index, level in
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(
                            width: barWidth,
                            height: barHeight(level, index: index)
                        )
                }
            }
            .frame(
                width: geometry.size.width,
                height: geometry.size.height,
                alignment: .center
            )
        }
        .frame(maxWidth: .infinity, minHeight: 28)
        .layoutPriority(1)
        .animation(.linear(duration: 0.09), value: recorder.powerHistory)
        .accessibilityLabel("Live microphone level")
    }

    private var displayedLevels: [Float] {
        if !historical { return idleShape }
        let count = FloatingWidgetWindowPolicy.recordingWaveformSampleCount
        return Array(
            (Array(repeating: Float(-60), count: count) + recorder.powerHistory)
                .suffix(count)
        )
    }

    private func barHeight(_ level: Float, index: Int) -> CGFloat {
        let normalized = max(0.08, min(1, CGFloat((level + 55) / 45)))
        let pulse = 0.82 + 0.18 * sin(recorder.elapsedSeconds * 11 + Double(index) * 0.72)
        return max(3, 27 * normalized * pulse)
    }
}
