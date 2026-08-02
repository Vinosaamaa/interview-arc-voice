@preconcurrency import AVFoundation
import Darwin
import Foundation
import InterviewArcVoiceCore

private enum VerificationError: Error {
    case invalidArguments
    case unreadableAudio
    case oversizedPrompt
    case unavailableModel
}

@main
private enum InterviewArcVoiceVerifier {
    static func main() async {
        do {
            let options = try parseArguments(Array(CommandLine.arguments.dropFirst()))
            let report = try await run(options: options)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            let code = safeErrorCode(error)
            FileHandle.standardError.write(Data("local-verification-failed: \(code)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private struct Options {
        let audioURL: URL
        let promptURL: URL?
    }

    private static func parseArguments(_ arguments: [String]) throws -> Options {
        guard arguments.count == 2 || arguments.count == 4,
              arguments.first == "--audio" else {
            throw VerificationError.invalidArguments
        }
        let audioURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        let promptURL: URL?
        if arguments.count == 4 {
            guard arguments[2] == "--prompt-file" else {
                throw VerificationError.invalidArguments
            }
            promptURL = URL(fileURLWithPath: arguments[3]).standardizedFileURL
        } else {
            promptURL = nil
        }
        return Options(audioURL: audioURL, promptURL: promptURL)
    }

    private static func run(
        options: Options
    ) async throws -> LocalWhisperVerificationReport {
        let values = try options.audioURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isReadableKey,
            .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isReadable == true,
              (values.fileSize ?? 0) > 0 else {
            throw VerificationError.unreadableAudio
        }

        let prompt: String
        if let promptURL = options.promptURL {
            let promptData = try Data(contentsOf: promptURL)
            guard promptData.count <= 65_536 else {
                throw VerificationError.oversizedPrompt
            }
            prompt = String(decoding: promptData, as: UTF8.self)
        } else {
            prompt = ""
        }

        let recordingStore = try RecordingStore()
        let manager = try LocalWhisperModelManager(
            rootDirectory: recordingStore.localModelsDirectory
        )
        let snapshot = await manager.snapshot()
        guard snapshot.state == .available else {
            throw VerificationError.unavailableModel
        }

        let asset = AVURLAsset(url: options.audioURL)
        let duration = try await asset.load(.duration).seconds
        let result = try await manager.transcribe(
            fileURL: options.audioURL,
            prompt: prompt
        )
        return LocalWhisperVerificationReport(
            result: result,
            audioDurationSeconds: duration.isFinite ? duration : 0
        )
    }

    private static func safeErrorCode(_ error: Error) -> String {
        switch error {
        case VerificationError.invalidArguments: "invalid-arguments"
        case VerificationError.unreadableAudio: "unreadable-audio"
        case VerificationError.oversizedPrompt: "oversized-prompt"
        case VerificationError.unavailableModel: "model-unavailable"
        case is LocalWhisperModelError: "local-model-error"
        default: "transcription-failed"
        }
    }
}
