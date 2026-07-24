import XCTest
@testable import InterviewArcVoiceCore

final class KeychainStoreTests: XCTestCase {
    func testCredentialRoundTripsThroughKeychain() throws {
        let store = KeychainStore(service: "dev.interviewarc.voice.tests.\(UUID().uuidString)")
        defer { try? store.remove(.groqAPIKey) }

        try store.set("gsk_test_value", for: .groqAPIKey)
        XCTAssertEqual(try store.value(for: .groqAPIKey), "gsk_test_value")

        try store.set("gsk_updated_value", for: .groqAPIKey)
        XCTAssertEqual(try store.value(for: .groqAPIKey), "gsk_updated_value")
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
        XCTAssertFalse(
            policy.isVerified(
                submittedValue: " \n ",
                retrievedValue: ""
            ),
            "An empty Keychain item must not be accepted as a saved credential."
        )
        XCTAssertTrue(
            policy.isVerified(
                submittedValue: "",
                retrievedValue: "",
                permitsEmpty: true
            ),
            "The optional Interview Arc token may remain empty for general dictation."
        )
    }

    func testCredentialRecoveryPrefersAUsableLegacyCandidateOverAnEmptyPrimaryItem() {
        XCTAssertEqual(
            CredentialCandidateSelectionPolicy().preferredValue(
                primary: "",
                legacyCandidates: ["", "  ", "gsk_recovered_value"]
            ),
            "gsk_recovered_value"
        )
    }
}
