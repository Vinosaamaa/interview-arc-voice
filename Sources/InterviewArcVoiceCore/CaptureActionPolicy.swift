public enum CaptureInsertionCompletion: Equatable, Sendable {
    case delivered
    case needsAttention
}

public enum CaptureActionPolicy {
    public static func copyPayload(
        transcript: String,
        captureID: String?,
        activityID: String?,
        turnID: String?
    ) -> String {
        guard let captureID, !captureID.isEmpty,
              let activityID, !activityID.isEmpty,
              let turnID, !turnID.isEmpty else {
            return transcript
        }
        return VoiceCaptureEnvelope(
            captureID: captureID,
            activityID: activityID,
            turnID: turnID,
            transcript: transcript
        ).editorText
    }

    public static func insertionCompletion(
        inserted: Bool
    ) -> CaptureInsertionCompletion {
        inserted ? .delivered : .needsAttention
    }
}
