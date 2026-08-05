import AppKit
import ApplicationServices
import Foundation
import InterviewArcVoiceCore

/// Resolves only privacy-safe target identity signals. It never reads terminal
/// contents, command arguments, environment variables, or transcript text.
enum CaptureTargetInspector {
    static func descriptor(
        for application: NSRunningApplication
    ) -> CaptureTargetDescriptor {
        let bundleIdentifier = application.bundleIdentifier
        let focusedTitle = focusedWindowTitle(
            applicationPID: application.processIdentifier
        )
        let fallbackTitle = focusedTitle == nil
            ? visibleWindowTitle(applicationPID: application.processIdentifier)
            : nil
        return CaptureTargetDescriptor(
            bundleIdentifier: bundleIdentifier,
            windowTitle: focusedTitle ?? fallbackTitle,
            windowEvidence: focusedTitle != nil
                ? .focusedAccessibility
                : (fallbackTitle != nil ? .visibleWindowFallback : .missing)
        )
    }

    /// Accessibility is the preferred source because it identifies the actual
    /// focused window. Some terminal builds do not expose that attribute to a
    /// background menu-bar application, even when Voice is trusted. In that
    /// case, use the title of the terminal's visible layer-zero window. This
    /// fallback reads only window metadata; it never captures terminal pixels
    /// or terminal contents.
    private static func visibleWindowTitle(
        applicationPID: pid_t
    ) -> String? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }
        return windows.first { window in
            (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                == applicationPID
                && (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }
        .flatMap { $0[kCGWindowName as String] as? String }
        .flatMap { title in
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func focusedWindowTitle(
        applicationPID: pid_t
    ) -> String? {
        let application = AXUIElementCreateApplication(applicationPID)
        AXUIElementSetMessagingTimeout(application, 0.2)
        var focusedWindowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        ) == .success,
        let focusedWindowValue else {
            return nil
        }
        let focusedWindow = focusedWindowValue as! AXUIElement
        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedWindow,
            kAXTitleAttribute as CFString,
            &titleValue
        ) == .success else {
            return nil
        }
        if let title = titleValue as? String { return title }
        return (titleValue as? NSAttributedString)?.string
    }

}
