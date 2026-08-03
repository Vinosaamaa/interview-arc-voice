import AppKit
import ApplicationServices
import Darwin
import Foundation
import InterviewArcVoiceCore

/// Resolves only privacy-safe target identity signals. It never reads terminal
/// contents, command arguments, environment variables, or transcript text.
enum CaptureTargetInspector {
    private static let descendantCache = CodexDescendantCache()

    static func descriptor(
        for application: NSRunningApplication
    ) -> CaptureTargetDescriptor {
        let bundleIdentifier = application.bundleIdentifier
        let hasCodexDescendant = CaptureTargetApplicationPolicy
            .requiresCodexDescendantInspection(bundleIdentifier: bundleIdentifier)
            ? descendantCache.value(for: application.processIdentifier) {
                processTreeContainsCodex(rootPID: application.processIdentifier)
            }
            : false
        return CaptureTargetDescriptor(
            bundleIdentifier: bundleIdentifier,
            windowTitle: focusedWindowTitle(
                applicationPID: application.processIdentifier
            ) ?? visibleWindowTitle(
                applicationPID: application.processIdentifier
            ),
            hasCodexDescendant: hasCodexDescendant
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
        var nameBuffer = [CChar](repeating: 0, count: 1_024)
        while let parentPID = pending.popLast(), visited.count < 512 {
            guard visited.insert(parentPID).inserted else { continue }
            for childPID in childPIDs(of: parentPID) {
                if executableName(pid: childPID, buffer: &nameBuffer) == "codex" {
                    return true
                }
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

    private static func executableName(
        pid: pid_t,
        buffer: inout [CChar]
    ) -> String? {
        buffer.withUnsafeMutableBufferPointer { pointer in
            pointer.initialize(repeating: 0)
        }
        let length = proc_name(
            pid,
            &buffer,
            UInt32(buffer.count)
        )
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map {
            UInt8(bitPattern: $0)
        }
        return String(decoding: bytes, as: UTF8.self).lowercased()
    }
}

private final class CodexDescendantCache: @unchecked Sendable {
    private struct Entry {
        let createdAt: ContinuousClock.Instant
        let value: Bool
    }

    private let lock = NSLock()
    private var entries: [pid_t: Entry] = [:]
    private let lifetime: Duration = .milliseconds(500)

    func value(for pid: pid_t, compute: () -> Bool) -> Bool {
        let now = ContinuousClock.now
        lock.lock()
        if let entry = entries[pid], now - entry.createdAt < lifetime {
            lock.unlock()
            return entry.value
        }
        lock.unlock()

        let value = compute()
        lock.lock()
        entries = entries.filter { now - $0.value.createdAt < lifetime }
        entries[pid] = Entry(createdAt: now, value: value)
        lock.unlock()
        return value
    }
}
