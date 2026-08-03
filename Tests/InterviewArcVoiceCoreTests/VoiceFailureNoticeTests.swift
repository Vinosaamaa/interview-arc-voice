import XCTest
@testable import InterviewArcVoiceCore

final class VoiceFailureNoticeTests: XCTestCase {
    func testChangedKeychainCredentialClearsPersistedRejection() {
        XCTAssertTrue(
            CredentialRejectionReconciliationPolicy.shouldClearRejection(
                rejectionIsPersisted: true,
                rejectedCredentialFingerprint: "old-fingerprint",
                currentCredentialFingerprint: "new-fingerprint",
                currentCredentialIsPresent: true
            )
        )
    }

    func testSameRejectedCredentialRemainsRejected() {
        XCTAssertFalse(
            CredentialRejectionReconciliationPolicy.shouldClearRejection(
                rejectionIsPersisted: true,
                rejectedCredentialFingerprint: "same-fingerprint",
                currentCredentialFingerprint: "same-fingerprint",
                currentCredentialIsPresent: true
            )
        )
    }

    func testLegacyRejectionWithoutFingerprintAllowsOneFreshProviderCheck() {
        XCTAssertTrue(
            CredentialRejectionReconciliationPolicy.shouldClearRejection(
                rejectionIsPersisted: true,
                rejectedCredentialFingerprint: nil,
                currentCredentialFingerprint: "current-fingerprint",
                currentCredentialIsPresent: true
            )
        )
    }

    func testMissingCredentialNeverClearsARejectedState() {
        XCTAssertFalse(
            CredentialRejectionReconciliationPolicy.shouldClearRejection(
                rejectionIsPersisted: true,
                rejectedCredentialFingerprint: nil,
                currentCredentialFingerprint: nil,
                currentCredentialIsPresent: false
            )
        )
    }

    func testFailureNoticeRoundTripsForPersistence() throws {
        let occurredAt = Date(timeIntervalSince1970: 1_784_906_000)
        let notice = VoiceFailureNotice(
            id: UUID(uuidString: "12345678-1234-1234-1234-1234567890ab")!,
            kind: .transcription,
            title: "Transcription failed",
            message: "Recording preserved · choose Retry or Play",
            detail: "The provider timed out before returning a complete transcript.",
            actions: [.retryTranscription, .playRecording, .saveRecording],
            occurredAt: occurredAt
        )

        let encoded = try JSONEncoder().encode(notice)
        XCTAssertEqual(try JSONDecoder().decode(VoiceFailureNotice.self, from: encoded), notice)
    }

    func testResolvedCredentialConfigurationFailureIsCleared() {
        let notice = VoiceFailureNotice(
            kind: .configuration,
            title: "Settings need attention",
            message: "Open settings to finish Voice setup",
            detail: "Add your Groq API key in Interview Arc Voice settings.",
            actions: [.openSettings]
        )

        XCTAssertNil(
            CredentialFailureRecoveryPolicy().retainedFailure(
                notice,
                configurationIsReady: true
            )
        )
    }

    func testCredentialRecoveryKeepsUnrelatedFailures() {
        let notice = VoiceFailureNotice(
            kind: .transcription,
            title: "Transcription failed",
            message: "Recording preserved",
            detail: "The provider did not return a transcript.",
            actions: [.retryTranscription]
        )

        XCTAssertEqual(
            CredentialFailureRecoveryPolicy().retainedFailure(
                notice,
                configurationIsReady: true
            ),
            notice
        )
    }

    func testUnresolvedCredentialConfigurationFailureRemainsVisible() {
        let notice = VoiceFailureNotice(
            kind: .configuration,
            title: "Settings need attention",
            message: "Open settings to finish Voice setup",
            detail: "Add your Groq API key in Interview Arc Voice settings.",
            actions: [.openSettings]
        )

        XCTAssertEqual(
            CredentialFailureRecoveryPolicy().retainedFailure(
                notice,
                configurationIsReady: false
            ),
            notice
        )
    }
}
