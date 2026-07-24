import Foundation

public struct VoiceContextRetentionPolicy: Sendable {
    public init() {}

    public func context(
        previous: VoiceContextResponse?,
        refreshed: VoiceContextResponse?
    ) -> VoiceContextResponse? {
        refreshed ?? previous
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
