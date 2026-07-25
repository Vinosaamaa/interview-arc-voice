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
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: FloatingWidgetWindowPolicy.collapsedWidth,
                height: FloatingWidgetWindowPolicy.hostHeight
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
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        let hostingView = TransparentHostingView(
            rootView: FloatingRecorderView(model: model)
        )
        panel.contentView = hostingView
        panel.setFrameAutosaveName("InterviewArcVoiceFloatingPanel")
        if !panel.setFrameUsingName("InterviewArcVoiceFloatingPanel") {
            panel.center()
        }
        panel.setContentSize(
            NSSize(
                width: FloatingWidgetWindowPolicy.collapsedWidth,
                height: FloatingWidgetWindowPolicy.hostHeight
            )
        )
        panel.invalidateShadow()
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func toggle(model: VoiceBridgeModel) {
        guard let panel else { show(model: model); return }
        panel.isVisible ? panel.orderOut(nil) : panel.orderFrontRegardless()
    }

    func setSize(width: CGFloat, height: CGFloat, reduceMotion: Bool) {
        guard let panel else { return }
        guard abs(panel.frame.width - width) > 0.5
                || abs(panel.frame.height - height) > 0.5 else { return }
        let frame = FloatingWidgetGeometryPolicy.anchoredFrame(
            currentFrame: panel.frame,
            targetSize: CGSize(width: width, height: height)
        )
        panel.contentView?.layer?.removeAllAnimations()
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

private final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

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
            .frame(width: geometry.size.width, alignment: .leading)
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

    private var palette: VoiceWidgetPalette { model.widgetPalette }

    var body: some View {
        VStack(alignment: .trailing, spacing: FloatingWidgetWindowPolicy.timerGap) {
            if !model.dynamicRecordingInterfaceActive,
               model.timerPanelExpanded,
               model.hasTimerInstrument,
               let instrument = model.timerInstrument {
                FloatingTimerInstrumentPanel(
                    model: model,
                    instrument: instrument
                )
                .frame(width: FloatingWidgetWindowPolicy.expandedWidth)
                // The AppKit panel already animates the bottom-anchored frame.
                // A second SwiftUI move transition made the capsule hop
                // vertically while the host was resizing.
                .transition(.opacity)
            }
            recorderCapsule
        }
        .padding(.vertical, 8)
        .frame(
            width: model.floatingWidth,
            height: model.floatingHeight,
            alignment: .bottomTrailing
        )
        .onChange(of: model.floatingSize) { _, _ in resizeWindow() }
    }

    private var recorderCapsule: some View {
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
                isRecording: model.dynamicRecordingInterfaceActive && model.isRecording
            )
            HStack(spacing: 6) {
                linkButton
                if model.isRecording {
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
                    if !model.hasTimerInstrument, model.hasLastAudio {
                        memoButton(
                            symbol: model.isPlayingLastAudio ? "pause.fill" : "play.fill",
                            label: model.isPlayingLastAudio ? "Pause last recording" : "Play last recording",
                            action: model.toggleLastAudioPlayback
                        )
                    }
                    if !model.hasTimerInstrument, !model.lastTranscript.isEmpty {
                        memoButton(
                            symbol: "doc.on.doc",
                            label: "Copy last transcript",
                            action: model.copyLastTranscript
                        )
                    }
                    if !model.hasTimerInstrument, model.hasLastAudio {
                        memoButton(
                            symbol: "square.and.arrow.down",
                            label: "Save last audio and transcript",
                            action: model.exportLastMemo
                        )
                    }
                }
                recordButton
            }
            .padding(.horizontal, 4)
        }
        .frame(
            width: model.floatingWidth,
            height: FloatingWidgetWindowPolicy.capsuleHeight
        )
        .clipShape(Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
        .frame(width: model.floatingWidth, alignment: .trailing)
    }

    private func resizeWindow() {
        FloatingPanelController.shared.setSize(
            width: model.floatingWidth,
            height: model.floatingHeight,
            reduceMotion: reduceMotion
        )
    }

    private var linkButton: some View {
        Button(action: model.toggleLinkMode) {
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
            if model.hasTimerInstrument, !model.isBusy {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Button(action: model.toggleTimerPanel) {
                        HStack(spacing: 5) {
                            OverflowMarqueeText(
                                text: model.compactTimerTitle,
                                font: .system(size: 11, weight: .semibold),
                                color: palette.ink
                            )
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .layoutPriority(1)
                            if let activityTime = model.compactActivityTime(at: timeline.date) {
                                compactClock(
                                    activityTime,
                                    symbol: "stopwatch",
                                    tint: palette.tealDark
                                )
                            }
                            if let sessionTime = model.compactSessionTime(at: timeline.date) {
                                Rectangle()
                                    .fill(palette.divider.opacity(0.75))
                                    .frame(width: 1, height: 17)
                                Text(sessionTime)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(palette.tealDark)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: 52, alignment: .center)
                            }
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
            } else {
                Text(model.floatingTitle)
                    .font(.system(size: 12, weight: .semibold, design: .default))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func compactClock(
        _ value: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .semibold))
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 4)
        .frame(width: 64, height: 24)
        .background(palette.timerSurface.opacity(palette.isDark ? 0.78 : 0.62))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
            ForEach(Array((model.failureNotice?.actions ?? []).prefix(2)), id: \.self) { action in
                if action == .openSettings {
                    SettingsLink {
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
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(LayeredWidgetButtonStyle(tint: palette.teal, palette: palette))
        .foregroundStyle(palette.ink)
        .voiceHoverFeedback(
            enabled: !model.isBusy,
            cornerRadius: 11,
            tint: palette.teal
        )
        .disabled(model.isBusy)
        .help(label)
        .accessibilityLabel(label)
    }

    private func failureSymbol(_ action: VoiceFailureAction) -> String {
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

    private func failureLabel(_ action: VoiceFailureAction) -> String {
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

    private var recordButton: some View {
        Button(action: model.toggleRecording) {
            ZStack {
                Circle()
                    .fill(recordHaloColor.opacity(model.isBusy ? 0.12 : 0.46))
                    .frame(width: 38, height: 38)
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
                } else {
                    Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(recordIconColor)
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
            enabled: model.isRecording || model.canRecord,
            cornerRadius: 18,
            tint: model.isRecording ? .red : palette.teal
        )
        .disabled(!model.isRecording && !model.canRecord)
        .accessibilityLabel(
            model.isBusy
                ? model.processingStatus
                : (model.isRecording ? "Stop recording" : "Start recording")
        )
    }

    private var recordHaloColor: Color {
        model.isRecording ? Color(red: 0.96, green: 0.29, blue: 0.25) : palette.tealGlow
    }

    private var recordFaceColor: Color {
        model.isRecording ? Color(red: 1.00, green: 0.78, blue: 0.76) : palette.timerSurface
    }

    private var recordIconColor: Color {
        model.isRecording ? Color(red: 0.72, green: 0.12, blue: 0.10) : palette.tealDark
    }

}

private struct FloatingTimerInstrumentPanel: View {
    @ObservedObject var model: VoiceBridgeModel
    let instrument: VoiceTimerInstrument

    private var palette: VoiceWidgetPalette { model.widgetPalette }

    private var availableActivities: [VoiceTimerActivity] {
        instrument.activities.filter { $0.id != instrument.activity?.id }
    }

    var body: some View {
        VStack(spacing: 0) {
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
                                model.performTimerAction(
                                    subjectID: session.id,
                                    kind: "session",
                                    action: "finish"
                                )
                            }
                        )
                    }
                    if instrument.session != nil,
                       !(model.dynamicRecordingInterfaceActive && model.isRecording) {
                        Divider().overlay(palette.divider.opacity(0.65))
                    }
                    if let activity = instrument.activity {
                        timerRow(
                            eyebrow: "ACTIVITY",
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

            if let activity = model.finishingActivity {
                Divider().overlay(palette.divider.opacity(0.65))
                finishDrawer(activity)
            } else if model.activityPickerExpanded {
                Divider().overlay(palette.divider.opacity(0.65))
                activityPicker
            } else if !availableActivities.isEmpty {
                Divider().overlay(palette.divider.opacity(0.65))
                Button(action: model.toggleActivityPicker) {
                    HStack(spacing: 7) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11, weight: .semibold))
                        Text(instrument.activity == nil ? "Start an activity" : "Choose another activity")
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
            height: model.floatingHeight
                - FloatingWidgetWindowPolicy.capsuleHeight
                - FloatingWidgetWindowPolicy.timerGap
                - 16,
            alignment: .bottom
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interview Arc timers")
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

private struct FailureRecoveryPopover: View {
    @ObservedObject var model: VoiceBridgeModel
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
                    ForEach(failure.actions, id: \.self) { action in
                        if action == .openSettings {
                            if action == failure.actions.first {
                                settingsActionLink(action)
                                    .buttonStyle(.borderedProminent)
                            } else {
                                settingsActionLink(action)
                                    .buttonStyle(.bordered)
                            }
                        } else if action == failure.actions.first {
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
        }
    }

    private func failureActionButton(_ action: VoiceFailureAction) -> some View {
        Button {
            model.performFailureAction(action)
        } label: {
            Label(actionLabel(action), systemImage: actionSymbol(action))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .tint(Color(red: 0.08, green: 0.44, blue: 0.39))
        .voiceHoverFeedback(cornerRadius: 8, tint: .teal)
    }

    private func settingsActionLink(_ action: VoiceFailureAction) -> some View {
        SettingsLink {
            Label(actionLabel(action), systemImage: actionSymbol(action))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .tint(Color(red: 0.08, green: 0.44, blue: 0.39))
        .voiceHoverFeedback(cornerRadius: 8, tint: .teal)
    }

    private func actionSymbol(_ action: VoiceFailureAction) -> String {
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

    private func actionLabel(_ action: VoiceFailureAction) -> String {
        switch action {
        case .recordAgain: "Record again"
        case .retryTranscription: "Retry"
        case .playRecording: "Play"
        case .saveRecording: "Save"
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
        HStack(spacing: 2) {
            ForEach(Array(displayedLevels.enumerated()), id: \.offset) { index, level in
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: 2.5, height: barHeight(level, index: index))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.linear(duration: 0.09), value: recorder.powerHistory)
        .accessibilityLabel("Live microphone level")
    }

    private var displayedLevels: [Float] {
        if !historical { return idleShape }
        let count = 24
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
