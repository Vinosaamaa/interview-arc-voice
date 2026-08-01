import Foundation

public enum SpeechProtectionMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case off
    case basic
    case enhanced

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .off: "Off"
        case .basic: "Basic"
        case .enhanced: "Enhanced — Experimental"
        }
    }

    public static let defaultsKey = "voice.speechProtectionMode"

    public static func load(from defaults: UserDefaults = .standard) -> SpeechProtectionMode {
        guard let rawValue = defaults.string(forKey: defaultsKey),
              let mode = SpeechProtectionMode(rawValue: rawValue) else {
            return .basic
        }
        return mode
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

public struct SpeechProtectedTranscription: Equatable, Sendable {
    public let transcription: TranscriptionResult
    public let omittedUnsupportedSegmentCount: Int
    public let omittedUnsupportedWordCount: Int
    public let wordAlignmentComplete: Bool
    public let evaluatedSegmentCount: Int
    public let wordTimestampCount: Int

    public init(
        transcription: TranscriptionResult,
        omittedUnsupportedSegmentCount: Int,
        omittedUnsupportedWordCount: Int = 0,
        wordAlignmentComplete: Bool = false,
        evaluatedSegmentCount: Int = 0,
        wordTimestampCount: Int = 0
    ) {
        self.transcription = transcription
        self.omittedUnsupportedSegmentCount = omittedUnsupportedSegmentCount
        self.omittedUnsupportedWordCount = omittedUnsupportedWordCount
        self.wordAlignmentComplete = wordAlignmentComplete
        self.evaluatedSegmentCount = evaluatedSegmentCount
        self.wordTimestampCount = wordTimestampCount
    }
}

public enum SegmentLocalTranscriptValidator {
    private static let segmentPaddingSeconds = 0.15
    private static let maximumLocalSpeechFraction = 0.01
    private static let providerNoSpeechThreshold = 0.60
    private static let providerLogProbabilityThreshold = -1.0
    private static let minimumWordEvidenceSeconds = 0.45
    private static let maximumUnsupportedWordGapSeconds = 0.30
    private static let maximumTerminalSpeechFraction = 0.10
    private static let minimumTerminalTimestampOverrunSeconds = 0.20
    private static let terminalHallucinationPhrases = [
        ["thank", "you"],
    ]

    private struct TextToken {
        let normalized: String
        let range: Range<String.Index>
    }

    private struct TokenInterval: Equatable {
        let lowerBound: Int
        let upperBound: Int
    }

    private struct WordTokenAlignment {
        let intervals: [TokenInterval]
        let isComplete: Bool
    }

    private struct RejectedWordRun {
        let wordIndices: [Int]
        let tokenInterval: TokenInterval
    }

    public static func apply(
        _ transcription: TranscriptionResult,
        speechEvidence: SpeechEvidenceResult,
        mode: SpeechProtectionMode
    ) -> SpeechProtectedTranscription {
        guard mode == .enhanced,
              let segments = transcription.segments,
              !segments.isEmpty,
              segmentsRepresentCompleteTranscript(
                  segments,
                  transcript: transcription.text
              ) else {
            return SpeechProtectedTranscription(
                transcription: transcription,
                omittedUnsupportedSegmentCount: 0,
                evaluatedSegmentCount: transcription.segments?.count ?? 0,
                wordTimestampCount: transcription.words.count
            )
        }

        let canonicalTokens = tokens(in: transcription.text)
        let segmentTokens = segments.map { tokens(in: $0.text) }
        let segmentTokenIntervals = tokenIntervals(for: segmentTokens)
        guard segmentTokens.flatMap({ $0 }).map(\.normalized)
                == canonicalTokens.map(\.normalized) else {
            return SpeechProtectedTranscription(
                transcription: transcription,
                omittedUnsupportedSegmentCount: 0,
                evaluatedSegmentCount: segments.count,
                wordTimestampCount: transcription.words.count
            )
        }

        let rejectedSegmentIndices = Set(
            segments.indices.filter { index in
                isUnsupported(
                    segments[index],
                    speechEvidence: speechEvidence
                )
            }
        )
        let wordAlignment = alignWords(
            transcription.words,
            canonicalTokens: canonicalTokens
        )
        let terminalTokenInterval = terminalPhraseTokenInterval(
            canonicalTokens: canonicalTokens
        )
        var rejectedWordRuns: [RejectedWordRun]
        if wordAlignment.isComplete {
            rejectedWordRuns = transcription.words.indices.compactMap { index in
                guard
                    !overlaps(
                        wordAlignment.intervals[index],
                        terminalTokenInterval
                    )
                    && !overlapsRejectedSegment(
                        transcription.words[index],
                        segments: segments,
                        rejectedSegmentIndices: rejectedSegmentIndices
                    )
                    && isStronglyUnsupported(
                        transcription.words[index],
                        speechEvidence: speechEvidence
                    )
                else {
                    return nil
                }
                return RejectedWordRun(
                    wordIndices: [index],
                    tokenInterval: wordAlignment.intervals[index]
                )
            }
        } else {
            rejectedWordRuns = uniquelyAlignedUnsupportedWordRuns(
                transcription.words,
                canonicalTokens: canonicalTokens,
                segments: segments,
                rejectedSegmentIndices: rejectedSegmentIndices,
                speechEvidence: speechEvidence
            )
        }
        if wordAlignment.isComplete,
           let terminalRun = unsupportedTerminalPhraseRun(
               transcription.words,
               canonicalTokens: canonicalTokens,
               wordAlignment: wordAlignment,
               segments: segments,
               rejectedSegmentIndices: rejectedSegmentIndices,
               speechEvidence: speechEvidence
           ) {
            rejectedWordRuns.append(terminalRun)
        }
        let rejectedWordIndices = Set(rejectedWordRuns.flatMap(\.wordIndices))

        let rejectedTokenIntervals =
            rejectedSegmentIndices.map { segmentTokenIntervals[$0] }
            + rejectedWordRuns.map(\.tokenInterval)
        let mergedRejectedTokenIntervals = merge(rejectedTokenIntervals)
        guard !mergedRejectedTokenIntervals.isEmpty else {
            return SpeechProtectedTranscription(
                transcription: transcription,
                omittedUnsupportedSegmentCount: 0,
                wordAlignmentComplete: wordAlignment.isComplete,
                evaluatedSegmentCount: segments.count,
                wordTimestampCount: transcription.words.count
            )
        }

        let retainedSegments: [TranscriptSegment] =
            segments.indices.compactMap { index -> TranscriptSegment? in
                guard !rejectedSegmentIndices.contains(index) else {
                    return nil
                }
                let segment = segments[index]
                let interval = segmentTokenIntervals[index]
                let localRejected = mergedRejectedTokenIntervals.compactMap {
                    intersection($0, interval).map {
                        TokenInterval(
                            lowerBound: $0.lowerBound - interval.lowerBound,
                            upperBound: $0.upperBound - interval.lowerBound
                        )
                    }
                }
                guard !localRejected.isEmpty else { return segment }
                let sanitized = removing(
                    localRejected,
                    from: segment.text,
                    tokens: segmentTokens[index]
                )
                guard !sanitized.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty else {
                    return nil
                }
                return TranscriptSegment(
                    start: segment.start,
                    end: segment.end,
                    text: sanitized,
                    averageLogProbability: segment.averageLogProbability,
                    compressionRatio: segment.compressionRatio,
                    noSpeechProbability: segment.noSpeechProbability
                )
            }
        let retainedWords: [TranscriptWord] =
            transcription.words.indices.compactMap {
                index -> TranscriptWord? in
                let word = transcription.words[index]
                guard !rejectedWordIndices.contains(index),
                      !overlapsRejectedSegment(
                          word,
                          segments: segments,
                          rejectedSegmentIndices: rejectedSegmentIndices
                      ) else {
                    return nil
                }
                return word
            }
        let retainedText = removing(
            mergedRejectedTokenIntervals,
            from: transcription.text,
            tokens: canonicalTokens
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return SpeechProtectedTranscription(
            transcription: TranscriptionResult(
                text: retainedText,
                words: retainedWords,
                segments: retainedSegments,
                durationSeconds: transcription.durationSeconds,
                chunkCount: transcription.chunkCount,
                timing: transcription.timing
            ),
            omittedUnsupportedSegmentCount: rejectedSegmentIndices.count,
            omittedUnsupportedWordCount: rejectedWordIndices.count,
            wordAlignmentComplete: wordAlignment.isComplete,
            evaluatedSegmentCount: segments.count,
            wordTimestampCount: transcription.words.count
        )
    }

    private static func isUnsupported(
        _ segment: TranscriptSegment,
        speechEvidence: SpeechEvidenceResult
    ) -> Bool {
        guard segment.end > segment.start,
              let noSpeechProbability = segment.noSpeechProbability,
              let averageLogProbability = segment.averageLogProbability,
              noSpeechProbability >= providerNoSpeechThreshold,
              averageLogProbability <= providerLogProbabilityThreshold else {
            return false
        }
        let local = speechEvidence.evidence(
            from: max(0, segment.start - segmentPaddingSeconds),
            to: segment.end + segmentPaddingSeconds
        )
        return !local.hasSustainedSpeech
            && local.speechLikeFraction <= maximumLocalSpeechFraction
    }

    private static func isStronglyUnsupported(
        _ word: TranscriptWord,
        speechEvidence: SpeechEvidenceResult
    ) -> Bool {
        isStronglyUnsupported(
            from: word.start,
            to: word.end,
            speechEvidence: speechEvidence
        )
    }

    private static func isStronglyUnsupported(
        from wordStart: Double,
        to wordEnd: Double,
        speechEvidence: SpeechEvidenceResult
    ) -> Bool {
        guard wordEnd > wordStart else { return false }
        let start = max(0, wordStart - segmentPaddingSeconds)
        let end = wordEnd + segmentPaddingSeconds
        guard end - start >= minimumWordEvidenceSeconds else { return false }
        let local = speechEvidence.evidence(from: start, to: end)
        return local.frameCount > 0
            && !local.hasSustainedSpeech
            && local.speechLikeFraction <= maximumLocalSpeechFraction
    }

    private static func isLocallyUnsupported(
        _ word: TranscriptWord,
        speechEvidence: SpeechEvidenceResult
    ) -> Bool {
        guard word.end > word.start else { return false }
        let local = speechEvidence.evidence(from: word.start, to: word.end)
        return local.frameCount > 0
            && !local.hasSustainedSpeech
            && local.speechLikeFraction <= maximumLocalSpeechFraction
    }

    private static func uniquelyAlignedUnsupportedWordRuns(
        _ words: [TranscriptWord],
        canonicalTokens: [TextToken],
        segments: [TranscriptSegment],
        rejectedSegmentIndices: Set<Int>,
        speechEvidence: SpeechEvidenceResult
    ) -> [RejectedWordRun] {
        var candidateRuns: [[Int]] = []
        var currentRun: [Int] = []

        func finishCurrentRun() {
            guard !currentRun.isEmpty else { return }
            candidateRuns.append(currentRun)
            currentRun = []
        }

        for index in words.indices {
            let word = words[index]
            guard
                !overlapsRejectedSegment(
                    word,
                    segments: segments,
                    rejectedSegmentIndices: rejectedSegmentIndices
                ),
                isLocallyUnsupported(
                    word,
                    speechEvidence: speechEvidence
                )
            else {
                finishCurrentRun()
                continue
            }

            if let previousIndex = currentRun.last,
               word.start - words[previousIndex].end
                    > maximumUnsupportedWordGapSeconds {
                finishCurrentRun()
            }
            currentRun.append(index)
        }
        finishCurrentRun()

        return candidateRuns.compactMap { indices in
            guard let first = indices.first,
                  let last = indices.last,
                  isStronglyUnsupported(
                      from: words[first].start,
                      to: words[last].end,
                      speechEvidence: speechEvidence
                  ) else {
                return nil
            }
            let candidateTokens = indices.flatMap {
                tokens(in: words[$0].word).map(\.normalized)
            }
            guard let interval = uniqueTokenInterval(
                matching: candidateTokens,
                in: canonicalTokens
            ) else {
                return nil
            }
            return RejectedWordRun(
                wordIndices: indices,
                tokenInterval: interval
            )
        }
    }

    private static func unsupportedTerminalPhraseRun(
        _ words: [TranscriptWord],
        canonicalTokens: [TextToken],
        wordAlignment: WordTokenAlignment,
        segments: [TranscriptSegment],
        rejectedSegmentIndices: Set<Int>,
        speechEvidence: SpeechEvidenceResult
    ) -> RejectedWordRun? {
        guard speechEvidence.analyzedDurationSeconds > 0 else { return nil }

        guard let tokenInterval = terminalPhraseTokenInterval(
            canonicalTokens: canonicalTokens
        ) else { return nil }
        let wordIndices = words.indices.filter { index in
            let interval = wordAlignment.intervals[index]
            return interval.lowerBound < tokenInterval.upperBound
                && interval.upperBound > tokenInterval.lowerBound
        }
        guard let firstIndex = wordIndices.first,
              let lastIndex = wordIndices.last,
              wordAlignment.intervals[firstIndex].lowerBound
                == tokenInterval.lowerBound,
              wordAlignment.intervals[lastIndex].upperBound
                == tokenInterval.upperBound,
              !wordIndices.contains(where: {
                  overlapsRejectedSegment(
                      words[$0],
                      segments: segments,
                      rejectedSegmentIndices: rejectedSegmentIndices
                  )
              }) else {
            return nil
        }

        let firstWord = words[firstIndex]
        let lastWord = words[lastIndex]
        let audioEnd = speechEvidence.analyzedDurationSeconds
        guard lastWord.end >= audioEnd - 0.75 else { return nil }
        guard terminalProviderCorroboratesRejection(
            wordIndices: wordIndices,
            words: words,
            segments: segments,
            audioEnd: audioEnd
        ) else {
            return nil
        }
        let evidenceStart = max(0, firstWord.start - segmentPaddingSeconds)
        let local = speechEvidence.evidence(
            from: evidenceStart,
            to: audioEnd
        )
        guard audioEnd - evidenceStart >= minimumWordEvidenceSeconds,
              local.frameCount > 0,
              !local.hasSustainedSpeech,
              local.speechLikeFraction <= maximumTerminalSpeechFraction else {
            return nil
        }
        return RejectedWordRun(
            wordIndices: Array(wordIndices),
            tokenInterval: tokenInterval
        )
    }

    private static func terminalPhraseTokenInterval(
        canonicalTokens: [TextToken]
    ) -> TokenInterval? {
        let normalizedTokens = canonicalTokens.map(\.normalized)
        guard let phrase = terminalHallucinationPhrases.first(where: {
            normalizedTokens.suffix($0.count).elementsEqual($0)
        }) else {
            return nil
        }
        return TokenInterval(
            lowerBound: canonicalTokens.count - phrase.count,
            upperBound: canonicalTokens.count
        )
    }

    private static func overlaps(
        _ interval: TokenInterval,
        _ optionalOther: TokenInterval?
    ) -> Bool {
        guard let other = optionalOther else { return false }
        return interval.lowerBound < other.upperBound
            && interval.upperBound > other.lowerBound
    }

    private static func terminalProviderCorroboratesRejection(
        wordIndices: [Int],
        words: [TranscriptWord],
        segments: [TranscriptSegment],
        audioEnd: Double
    ) -> Bool {
        guard let lastIndex = wordIndices.last else { return false }
        if words[lastIndex].end - audioEnd
            >= minimumTerminalTimestampOverrunSeconds {
            return true
        }

        let overlappingSegments = segments.filter { segment in
            wordIndices.contains { index in
                words[index].end > segment.start
                    && words[index].start < segment.end
            }
        }
        guard !overlappingSegments.isEmpty else { return false }
        return overlappingSegments.allSatisfy { segment in
            guard let noSpeechProbability = segment.noSpeechProbability,
                  let averageLogProbability = segment.averageLogProbability else {
                return false
            }
            return noSpeechProbability >= providerNoSpeechThreshold
                && averageLogProbability <= providerLogProbabilityThreshold
        }
    }

    private static func uniqueTokenInterval(
        matching candidateTokens: [String],
        in canonicalTokens: [TextToken]
    ) -> TokenInterval? {
        guard !candidateTokens.isEmpty,
              candidateTokens.count <= canonicalTokens.count else {
            return nil
        }
        let canonicalValues = canonicalTokens.map(\.normalized)
        var match: TokenInterval?
        for start in 0...(canonicalValues.count - candidateTokens.count) {
            let end = start + candidateTokens.count
            guard Array(canonicalValues[start..<end]) == candidateTokens else {
                continue
            }
            guard match == nil else { return nil }
            match = TokenInterval(lowerBound: start, upperBound: end)
        }
        return match
    }

    private static func overlapsRejectedSegment(
        _ word: TranscriptWord,
        segments: [TranscriptSegment],
        rejectedSegmentIndices: Set<Int>
    ) -> Bool {
        rejectedSegmentIndices.contains { index in
            word.end > segments[index].start
                && word.start < segments[index].end
        }
    }

    private static func alignWords(
        _ words: [TranscriptWord],
        canonicalTokens: [TextToken]
    ) -> WordTokenAlignment {
        var intervals: [TokenInterval] = []
        var normalizedWords: [String] = []
        var offset = 0
        for word in words {
            let wordTokens = tokens(in: word.word)
            let values = wordTokens.map(\.normalized)
            intervals.append(
                TokenInterval(
                    lowerBound: offset,
                    upperBound: offset + values.count
                )
            )
            normalizedWords.append(contentsOf: values)
            offset += values.count
        }
        return WordTokenAlignment(
            intervals: intervals,
            isComplete:
                !words.isEmpty
                && normalizedWords == canonicalTokens.map(\.normalized)
        )
    }

    private static func tokenIntervals(
        for tokenGroups: [[TextToken]]
    ) -> [TokenInterval] {
        var offset = 0
        return tokenGroups.map { group in
            defer { offset += group.count }
            return TokenInterval(
                lowerBound: offset,
                upperBound: offset + group.count
            )
        }
    }

    private static func merge(
        _ intervals: [TokenInterval]
    ) -> [TokenInterval] {
        let sorted = intervals
            .filter { $0.upperBound > $0.lowerBound }
            .sorted {
                $0.lowerBound == $1.lowerBound
                    ? $0.upperBound < $1.upperBound
                    : $0.lowerBound < $1.lowerBound
            }
        guard var current = sorted.first else { return [] }
        var result: [TokenInterval] = []
        for interval in sorted.dropFirst() {
            if interval.lowerBound <= current.upperBound {
                current = TokenInterval(
                    lowerBound: current.lowerBound,
                    upperBound: max(current.upperBound, interval.upperBound)
                )
            } else {
                result.append(current)
                current = interval
            }
        }
        result.append(current)
        return result
    }

    private static func intersection(
        _ left: TokenInterval,
        _ right: TokenInterval
    ) -> TokenInterval? {
        let lower = max(left.lowerBound, right.lowerBound)
        let upper = min(left.upperBound, right.upperBound)
        guard upper > lower else { return nil }
        return TokenInterval(lowerBound: lower, upperBound: upper)
    }

    private static func removing(
        _ intervals: [TokenInterval],
        from text: String,
        tokens: [TextToken]
    ) -> String {
        guard !intervals.isEmpty, !tokens.isEmpty else { return text }
        var result = text
        let characterRanges = intervals.compactMap { interval -> Range<String.Index>? in
            guard interval.lowerBound >= 0,
                  interval.upperBound > interval.lowerBound,
                  interval.lowerBound < tokens.count else {
                return nil
            }
            let upper = min(interval.upperBound, tokens.count)
            let start = tokens[interval.lowerBound].range.lowerBound
            let end = upper < tokens.count
                ? tokens[upper].range.lowerBound
                : text.endIndex
            return start..<end
        }
        let sortedRanges = characterRanges.sorted {
            $0.lowerBound < $1.lowerBound
        }
        guard !sortedRanges.isEmpty else { return text }
        result = ""
        var cursor = text.startIndex
        for range in sortedRanges {
            guard range.lowerBound >= cursor else { continue }
            result.append(contentsOf: text[cursor..<range.lowerBound])
            cursor = range.upperBound
        }
        result.append(contentsOf: text[cursor..<text.endIndex])
        return result
    }

    private static func tokens(in value: String) -> [TextToken] {
        var result: [TextToken] = []
        var index = value.startIndex
        while index < value.endIndex {
            while index < value.endIndex,
                  !value[index].isLetter,
                  !value[index].isNumber {
                index = value.index(after: index)
            }
            guard index < value.endIndex else { break }
            let start = index
            while index < value.endIndex,
                  value[index].isLetter || value[index].isNumber {
                index = value.index(after: index)
            }
            let range = start..<index
            result.append(
                TextToken(
                    normalized: String(value[range]).lowercased(),
                    range: range
                )
            )
        }
        return result
    }

    private static func segmentsRepresentCompleteTranscript(
        _ segments: [TranscriptSegment],
        transcript: String
    ) -> Bool {
        normalizedTokens(
            segments.map(\.text).joined(separator: " ")
        ) == normalizedTokens(transcript)
    }

    private static func normalizedTokens(_ value: String) -> [String] {
        value.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
