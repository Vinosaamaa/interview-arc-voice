import AppKit
import ApplicationServices
import Darwin
import Foundation
import InterviewArcVoiceCore

/// Resolves only privacy-safe target identity signals. It never reads terminal
/// contents, command arguments, environment variables, or transcript text.
enum CaptureTargetInspector {
    static func descriptor(
        for application: NSRunningApplication
    ) -> CaptureTargetDescriptor {
        CaptureTargetDescriptor(
            bundleIdentifier: application.bundleIdentifier,
            windowTitle: focusedWindowTitle(
                applicationPID: application.processIdentifier
            ) ?? visibleWindowTitle(
                applicationPID: application.processIdentifier
            ),
            hasCodexDescendant: processTreeContainsCodex(
                rootPID: application.processIdentifier
            )
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

    private static func processTreeContainsCodex(rootPID: pid_t) -> Bool {
        var pending = [rootPID]
        var visited = Set<pid_t>()
        while let parentPID = pending.popLast(), visited.count < 512 {
            guard visited.insert(parentPID).inserted else { continue }
            for childPID in childPIDs(of: parentPID) {
                if executableName(pid: childPID) == "codex" { return true }
                pending.append(childPID)
            }
        }
        return false
    }

    private static func childPIDs(of parentPID: pid_t) -> [pid_t] {
        var children = [pid_t](repeating: 0, count: 256)
        let childCount = children.withUnsafeMutableBytes { buffer in
            proc_listchildpids(
                parentPID,
                buffer.baseAddress,
                Int32(buffer.count)
            )
        }
        guard childCount > 0 else { return [] }
        return Array(
            children.prefix(
                min(
                    children.count,
                    Int(childCount)
                )
            )
        ).filter { $0 > 0 }
    }

    private static func executableName(pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: 4_096)
        let length = proc_pidpath(
            pid,
            &pathBuffer,
            UInt32(pathBuffer.count)
        )
        guard length > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: pathBuffer))
            .lastPathComponent
            .lowercased()
    }
}
