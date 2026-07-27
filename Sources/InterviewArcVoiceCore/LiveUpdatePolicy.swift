import Foundation

public struct PendingCaptureRegistrationPolicy: Sendable {
    public init() {}

    public func captureIDsToRegister(
        localCaptureIDs: [String],
        serverCaptureIDs: [String]
    ) -> [String] {
        let known = Set(serverCaptureIDs)
        return localCaptureIDs.filter { !known.contains($0) }
    }
}

public struct VoiceLiveUpdateFallbackPolicy: Sendable {
    public init() {}

    public func delaySeconds(attempt: Int) -> TimeInterval {
        min(120, 15 * pow(2, Double(max(0, attempt))))
    }
}

public struct VoiceCaptureRetryPolicy: Sendable {
    public init() {}

    public func nextAttempt(attempt: Int, now: Date = Date()) -> Date {
        let seconds = min(3_600, 15 * pow(2, Double(max(0, attempt))))
        return now.addingTimeInterval(seconds)
    }

    public func isDue(_ capture: PendingVoiceCapture, now: Date = Date()) -> Bool {
        guard capture.localState != .quarantinedConflict else { return false }
        return capture.nextAttemptAt.map { $0 <= now }
            ?? (capture.localState == .insertedRegistrationPending)
    }

    public func isExpired(_ capture: PendingVoiceCapture, now: Date = Date()) -> Bool {
        guard [.insertedRegistrationPending, .waitingForSpecialist, .needsDecision, .excludedGracePeriod]
            .contains(capture.localState ?? .insertedRegistrationPending) else { return false }
        return now.timeIntervalSince(capture.createdAt) >= 86_400
    }
}

public struct VoiceLiveUpdate: Codable, Equatable, Sendable {
    public let type: String
    public let revision: Int
    public let scope: String
    public let occurredAt: Int64

    public init(type: String, revision: Int, scope: String, occurredAt: Int64) {
        self.type = type
        self.revision = revision
        self.scope = scope
        self.occurredAt = occurredAt
    }
}

public struct VoiceLiveRevisionPolicy: Sendable {
    public init() {}

    public func shouldApply(revision: Int, latestRevision: Int) -> Bool {
        revision > 0 && revision > latestRevision
    }
}
