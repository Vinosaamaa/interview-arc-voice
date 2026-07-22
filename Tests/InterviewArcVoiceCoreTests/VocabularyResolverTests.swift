import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test func graphMetadataSelectsGraphPack() throws {
    let resolver = VocabularyResolver(catalog: try .bundled())
    let activity = ActivityContext(
        activityID: "graph-1",
        specialty: .coding,
        title: "Network Delay Time",
        topics: ["Graph", "Shortest Path"]
    )

    let result = resolver.resolve(activity)

    #expect(result.packIDs.contains("coding-graphs"))
    #expect(result.packIDs.contains("coding-core"))
    #expect(result.terms.contains("Dijkstra"))
    #expect(result.usedBaseFallback == false)
}

@Test func unknownActivityUsesSpecialtyBasePack() throws {
    let resolver = VocabularyResolver(catalog: try .bundled())
    let activity = ActivityContext(
        activityID: "custom-1",
        specialty: .systemDesign,
        title: "A completely custom architecture prompt"
    )

    let result = resolver.resolve(activity)

    #expect(result.packIDs == ["system-design-core"])
    #expect(result.usedBaseFallback)
    #expect(result.terms.contains("scalability"))
}

@Test func explicitTermsAndPacksTakePriority() throws {
    let resolver = VocabularyResolver(catalog: try .bundled(), promptTokenBudget: 100)
    let activity = ActivityContext(
        activityID: "feed-1",
        specialty: .systemDesign,
        title: "Design a TikTok-style For You feed",
        vocabularyPackIDs: ["system-design-recommendation"],
        speechTerms: ["HNSW", "vector database"]
    )

    let result = resolver.resolve(activity)

    #expect(result.packIDs.first == "system-design-recommendation")
    #expect(result.terms.prefix(2) == ["HNSW", "vector database"])
    #expect(result.prompt.contains("TikTok-style For You feed"))
}

@Test func promptStaysWithinConservativeBudget() throws {
    let resolver = VocabularyResolver(catalog: try .bundled(), promptTokenBudget: 40)
    let activity = ActivityContext(
        activityID: "many-terms",
        specialty: .systemDesign,
        title: "Design a feed",
        speechTerms: (0..<100).map { "specialized-term-\($0)" }
    )

    let result = resolver.resolve(activity)

    #expect(result.terms.count < 100)
    #expect(result.terms.first == "specialized-term-0")
}

@Test func transcriptAssemblerKeepsNaturalSpacingAndPunctuation() {
    let chunk = AudioChunk(
        url: URL(fileURLWithPath: "/tmp/answer.m4a"),
        offsetSeconds: 0,
        durationSeconds: 2,
        isTemporary: false
    )
    let response = GroqTranscription(
        text: "We use Dijkstra's algorithm, then relax edges.",
        language: "en",
        duration: 2,
        words: [
            TranscriptWord(word: "We", start: 0, end: 0.2),
            TranscriptWord(word: "use", start: 0.25, end: 0.4),
            TranscriptWord(word: "Dijkstra's", start: 0.45, end: 0.8),
            TranscriptWord(word: "algorithm", start: 0.85, end: 1.1),
            TranscriptWord(word: ",", start: 1.1, end: 1.11),
            TranscriptWord(word: "then", start: 1.2, end: 1.4),
            TranscriptWord(word: "relax", start: 1.45, end: 1.7),
            TranscriptWord(word: "edges", start: 1.72, end: 1.95),
            TranscriptWord(word: ".", start: 1.95, end: 1.98),
        ],
        segments: nil
    )

    let result = TranscriptAssembler.assemble([(chunk, response)])

    #expect(result.text == "We use Dijkstra's algorithm, then relax edges.")
}

@Test func transcriptAssemblerRemovesChunkOverlap() {
    let first = AudioChunk(url: URL(fileURLWithPath: "/tmp/one.m4a"), offsetSeconds: 0, durationSeconds: 10, isTemporary: true)
    let second = AudioChunk(url: URL(fileURLWithPath: "/tmp/two.m4a"), offsetSeconds: 8.5, durationSeconds: 10, isTemporary: true)
    let firstResponse = GroqTranscription(text: "First we gather requirements and estimate traffic", language: "en", duration: 10, words: nil, segments: nil)
    let secondResponse = GroqTranscription(text: "estimate traffic before choosing the storage model", language: "en", duration: 10, words: nil, segments: nil)

    let result = TranscriptAssembler.assemble([(first, firstResponse), (second, secondResponse)])

    #expect(result.text == "First we gather requirements and estimate traffic before choosing the storage model")
}
