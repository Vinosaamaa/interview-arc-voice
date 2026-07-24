import XCTest
@testable import InterviewArcVoiceCore

final class KeychainStoreTests: XCTestCase {
    func testCredentialRoundTripsThroughKeychain() throws {
        let store = KeychainStore(service: "dev.interviewarc.voice.tests.\(UUID().uuidString)")
        defer { try? store.remove(.groqAPIKey) }

        try store.set("gsk_test_value", for: .groqAPIKey)

        XCTAssertEqual(try store.value(for: .groqAPIKey), "gsk_test_value")
    }

    func testCredentialSaveIsVerifiedByReadingTheSubmittedValueBack() {
        let policy = CredentialSaveVerificationPolicy()

        XCTAssertTrue(
            policy.isVerified(
                submittedValue: "  gsk_saved_value  ",
                retrievedValue: "gsk_saved_value"
            )
        )
        XCTAssertFalse(
            policy.isVerified(
                submittedValue: "gsk_saved_value",
                retrievedValue: nil
            )
        )
        XCTAssertFalse(
            policy.isVerified(
                submittedValue: "gsk_saved_value",
                retrievedValue: "different-value"
            )
        )
    }
}
