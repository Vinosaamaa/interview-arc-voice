import Foundation

public enum ContextRefreshOrderingPolicy {
    public static func shouldApply(
        requestID: Int,
        latestRequestID: Int
    ) -> Bool {
        requestID == latestRequestID
    }
}

public struct VoiceContextRetentionPolicy: Sendable {
    public init() {}

    public func context(
        previous: VoiceContextResponse?,
        refreshed: VoiceContextResponse?
    ) -> VoiceContextResponse? {
        refreshed ?? previous
    }
}

public struct CaptureContextFreshnessPolicy: Sendable {
    public let maximumAge: TimeInterval

    public init(maximumAge: TimeInterval = 10) {
        self.maximumAge = maximumAge
    }

    public func isFresh(
        lastVerifiedAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let lastVerifiedAt else { return false }
        return now.timeIntervalSince(lastVerifiedAt) <= maximumAge
    }
}

public struct LateCaptureBindingPolicy: Sendable {
    public init() {}

    public func activity(
        initiallyLinkedActivityID: String?,
        recordingStartedAtMilliseconds: Int64,
        refreshedActivity: FocusedVoiceActivity?
    ) -> FocusedVoiceActivity? {
        guard initiallyLinkedActivityID == nil,
              let refreshedActivity,
              let runningSince = refreshedActivity.runningSince,
              runningSince <= recordingStartedAtMilliseconds else {
            return nil
        }
        return refreshedActivity
    }

    public func capture(
        initiallyLinked: Bool,
        recordingStartedAtMilliseconds: Int64,
        refreshedContext: VoiceContextResponse
    ) -> LinkedVoiceCaptureContext? {
        guard !initiallyLinked,
              let selection = VoiceCaptureContextPolicy().selection(
                  for: refreshedContext
              ) else {
            return nil
        }
        let runningSince = switch selection {
        case .interview(let activity): activity.runningSince
        case .learning(let session): session.runningSince
        }
        guard let runningSince,
              runningSince <= recordingStartedAtMilliseconds else {
            return nil
        }
        return selection
    }
}

public struct VoiceMemoExportPlan: Equatable, Sendable {
    public let suggestedAudioFilename: String

    public init(activityTitle: String?, createdAt: Date) {
        let title = Self.safeFilenameStem(activityTitle ?? "")
        if !title.isEmpty {
            suggestedAudioFilename = title + ".m4a"
            return
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        suggestedAudioFilename = "Interview Arc Voice \(formatter.string(from: createdAt)).m4a"
    }

    public func transcriptURL(forAudioURL audioURL: URL) -> URL {
        audioURL.deletingPathExtension().appendingPathExtension("txt")
    }

    private static func safeFilenameStem(_ input: String) -> String {
        input
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct PlaybackCompletionPolicy: Sendable {
    public init() {}

    public func didFinish(
        previousTime: TimeInterval,
        currentTime: TimeInterval,
        duration: TimeInterval
    ) -> Bool {
        guard duration > 0 else { return false }
        if previousTime >= max(0, duration - 0.15) { return true }
        return currentTime <= 0.01 && previousTime >= duration * 0.8
    }
}
