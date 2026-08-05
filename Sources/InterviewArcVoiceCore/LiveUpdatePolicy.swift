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

public enum VoiceLiveRetryMode: Equatable, Sendable {
    case none
    case scheduled
    case forced(activityID: String)
}

public struct VoiceLiveRetryPolicy: Sendable {
    public init() {}

    public func mode(for scope: String) -> VoiceLiveRetryMode {
        let prefix = "voice_delivery_retry:"
        if scope.hasPrefix(prefix) {
            let activityID = String(scope.dropFirst(prefix.count))
            if !activityID.isEmpty { return .forced(activityID: activityID) }
        }
        switch scope {
        case "voice_intent", "voice_capture": return .scheduled
        default: return .none
        }
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
                 .audioLostAcknowledged, .quarantinedConflict, .needsAttention,
                 .complete:
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
    public static let maximumAutomaticAttempts = 8
    public static let maximumRetryWindow: TimeInterval = 6 * 60 * 60

    public init() {}

    public func nextAttempt(attempt: Int, now: Date = Date()) -> Date {
        let schedule: [TimeInterval] = [15, 30, 60, 120, 300, 900, 3_600]
        let index = min(schedule.count - 1, max(0, attempt - 1))
        let seconds = schedule[index]
        return now.addingTimeInterval(seconds)
    }

    public func isDue(_ capture: PendingVoiceCapture, now: Date = Date()) -> Bool {
        guard capture.localState != .quarantinedConflict,
              capture.localState != .needsAttention else { return false }
        return capture.nextAttemptAt.map { $0 <= now }
            ?? (capture.localState == .insertedRegistrationPending)
    }

    public func isExpired(_ capture: PendingVoiceCapture, now: Date = Date()) -> Bool {
        guard [.insertedRegistrationPending, .waitingForSpecialist, .excludedGracePeriod]
            .contains(capture.localState ?? .insertedRegistrationPending) else { return false }
        return now.timeIntervalSince(capture.createdAt) >= 86_400
    }
}

public enum VoiceDeliveryFailureDecision: Equatable, Sendable {
    case retry(
        attempt: Int,
        retryStartedAt: Date,
        nextAttemptAt: Date,
        code: String,
        statusCode: Int,
        message: String
    )
    case quarantine(code: String, statusCode: Int, message: String)
    case needsAttention(code: String, statusCode: Int, message: String)
}

public struct VoiceDeliveryFailurePolicy: Sendable {
    private static let permanentCodes: Set<String> = [
        "voice_response_group_conflict",
        "voice_capture_identity_conflict",
        "voice_capture_not_remediable",
        "capture_deleted",
        "capture_tombstoned",
        "owner_mismatch",
        "activity_mismatch",
        "turn_mismatch",
        "checksum_mismatch",
        "invalid_authentication",
        "forbidden",
    ]

    public init() {}

    public func decision(
        error: InterviewArcAPIError,
        capture: PendingVoiceCapture,
        now: Date = Date()
    ) -> VoiceDeliveryFailureDecision {
        let code = error.code ?? "http_\(error.statusCode)"
        if !error.retryable || Self.permanentCodes.contains(code) {
            return .quarantine(
                code: code,
                statusCode: error.statusCode,
                message: error.message
            )
        }
        let attempt = (capture.retryAttempt ?? 0) + 1
        let startedAt = capture.retryStartedAt ?? now
        if attempt >= VoiceCaptureRetryPolicy.maximumAutomaticAttempts
            || now.timeIntervalSince(startedAt) >= VoiceCaptureRetryPolicy.maximumRetryWindow {
            return .needsAttention(
                code: code,
                statusCode: error.statusCode,
                message: error.message
            )
        }
        return .retry(
            attempt: attempt,
            retryStartedAt: startedAt,
            nextAttemptAt: VoiceCaptureRetryPolicy().nextAttempt(
                attempt: attempt,
                now: now
            ),
            code: code,
            statusCode: error.statusCode,
            message: error.message
        )
    }
}

public struct VoiceDeliveryErrorPolicy: Sendable {
    public init() {}

    public func retryableAPIError(for error: Error) -> InterviewArcAPIError? {
        guard error is DecodingError else { return nil }
        return InterviewArcAPIError(
            statusCode: 0,
            message: error.localizedDescription,
            code: "response_decoding_failure",
            retryable: true
        )
    }
}

public enum VoiceDeliveryReceiptAction: Equatable, Sendable {
    case deliverTranscript
    case resumeAfterTranscript(responseGroupID: String?, responseGroupDigest: String?)
    case quarantine(responseGroupID: String?, responseGroupDigest: String?)
}

public struct VoiceDeliveryReceiptPolicy: Sendable {
    public init() {}

    public func action(for blocker: VoiceDeliveryBlocker?) -> VoiceDeliveryReceiptAction {
        guard let blocker else { return .deliverTranscript }
        if blocker.status == "quarantined_conflict"
            || blocker.groupStatus == "quarantined_conflict" {
            return .quarantine(
                responseGroupID: blocker.responseTurnId,
                responseGroupDigest: blocker.groupDigest
            )
        }
        if blocker.transcriptDeliveryState == "received"
            || blocker.canonicalUserTurnPresent {
            return .resumeAfterTranscript(
                responseGroupID: blocker.responseTurnId,
                responseGroupDigest: blocker.groupDigest
            )
        }
        return .deliverTranscript
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
        guard let currentWorkbenchID,
              let captureWorkbenchID = capture.workbenchID,
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
