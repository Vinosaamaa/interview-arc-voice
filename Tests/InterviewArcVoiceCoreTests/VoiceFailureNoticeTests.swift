import XCTest
@testable import InterviewArcVoiceCore

final class VoiceFailureNoticeTests: XCTestCase {
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
}

