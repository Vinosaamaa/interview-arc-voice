import Foundation

public enum VoiceForegroundPresentation: Equatable, Sendable {
    case idle
    case recording
    case processing
    case failure
}

public enum VoiceBackgroundPresentationDecision: Equatable, Sendable {
    case publishBackgroundStatus
    case preserveForeground
}

public enum VoiceBackgroundPresentationPolicy {
    public static func decision(
        foreground: VoiceForegroundPresentation,
        stateUnchangedDuringReconciliation: Bool
    ) -> VoiceBackgroundPresentationDecision {
        guard foreground == .idle, stateUnchangedDuringReconciliation else {
            return .preserveForeground
        }
        return .publishBackgroundStatus
    }
}

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

public struct VoicePendingReconciliationPolicy: Sendable {
    public init() {}

    public func delaySeconds(
        captures: [PendingVoiceCapture],
        attempt: Int,
        now: Date = Date()
    ) -> TimeInterval? {
        let unresolved = captures.filter {
            switch $0.localState ?? .insertedRegistrationPending {
            case .insertedRegistrationPending, .waitingForSpecialist, .needsDecision:
                return true
            case .acceptedDelivering:
                return true
            case .excludedGracePeriod, .audioLostNeedsAcknowledgement,
                 .audioLostAcknowledged, .quarantinedConflict, .complete:
                return false
            }
        }
        guard !unresolved.isEmpty else { return nil }

        let safetyDelay = VoiceLiveUpdateFallbackPolicy().delaySeconds(attempt: attempt)
        let scheduledDelay = unresolved.compactMap(\.nextAttemptAt)
            .map { max(0, $0.timeIntervalSince(now)) }
            .min()
        return min(safetyDelay, scheduledDelay ?? safetyDelay)
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
        guard [.insertedRegistrationPending, .waitingForSpecialist, .excludedGracePeriod]
            .contains(capture.localState ?? .insertedRegistrationPending) else { return false }
        return now.timeIntervalSince(capture.createdAt) >= 86_400
    }
}

public enum VoiceCaptureExpiryAction: Equatable, Sendable {
    case none
    case expirePendingOnServer
    case deleteExcludedOnServer
    case removeTerminalLocalEvidence
}

public struct VoiceCaptureLifecyclePolicy: Sendable {
    public init() {}

    public func expiryAction(
        capture: PendingVoiceCapture,
        serverStatus: String,
        now: Date = Date()
    ) -> VoiceCaptureExpiryAction {
        guard VoiceCaptureRetryPolicy().isExpired(capture, now: now) else {
            return .none
        }
        switch serverStatus {
        case "pending":
            return .expirePendingOnServer
        case "unrelated", "deleting":
            return .deleteExcludedOnServer
        case "deleted", "discarded_unclassified", "expired_unclassified":
            return .removeTerminalLocalEvidence
        default:
            return .none
        }
    }

    public func belongsToCurrentWorkbench(
        _ capture: PendingVoiceCapture,
        workbenchID: String?,
        currentActivityIDs: Set<String>
    ) -> Bool {
        guard let workbenchID else { return false }
        if let captureWorkbenchID = capture.workbenchID {
            return captureWorkbenchID == workbenchID
        }
        return currentActivityIDs.contains(capture.activity.activityId)
    }

    public func canRemoveSettledMetadata(
        _ capture: PendingVoiceCapture,
        currentWorkbenchID: String?
    ) -> Bool {
        guard let captureWorkbenchID = capture.workbenchID,
              captureWorkbenchID != currentWorkbenchID else {
            return false
        }
        return capture.localState == .complete
            || capture.localState == .audioLostAcknowledged
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

public enum VoiceLiveSignal: Equatable, Sendable {
    case connected(revision: Int)
    case practiceChanged(VoiceLiveUpdate)
}

public struct VoiceLiveFrameDecoder: Sendable {
    private struct FrameHeader: Decodable {
        let type: String
        let revision: Int
    }

    public init() {}

    public func decode(
        _ data: Data,
        latestRevision: inout Int
    ) throws -> VoiceLiveSignal? {
        let decoder = JSONDecoder()
        let header = try decoder.decode(FrameHeader.self, from: data)
        switch header.type {
        case "connected":
            latestRevision = max(latestRevision, header.revision)
            return .connected(revision: header.revision)
        case "practice_changed":
            guard VoiceLiveRevisionPolicy().shouldApply(
                revision: header.revision,
                latestRevision: latestRevision
            ) else {
                return nil
            }
            let update = try decoder.decode(VoiceLiveUpdate.self, from: data)
            latestRevision = update.revision
            return .practiceChanged(update)
        default:
            return nil
        }
    }
}

public struct VoiceLiveRevisionPolicy: Sendable {
    public init() {}

    public func shouldApply(revision: Int, latestRevision: Int) -> Bool {
        revision > 0 && revision > latestRevision
    }
}
