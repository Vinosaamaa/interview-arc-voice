import Foundation

public struct VocabularyResolution: Equatable, Sendable {
    public let packIDs: [String]
    public let terms: [String]
    public let prompt: String
    public let usedBaseFallback: Bool
}

public struct VocabularyResolver: Sendable {
    private let catalog: VocabularyCatalog
    private let promptTokenBudget: Int

    public init(catalog: VocabularyCatalog, promptTokenBudget: Int = 180) {
        self.catalog = catalog
        self.promptTokenBudget = min(max(promptTokenBudget, 32), 220)
    }

    public func resolve(_ activity: ActivityContext) -> VocabularyResolution {
        let specialtyPacks = catalog.packs.filter { $0.specialty == activity.specialty }
        let explicitPackIDs = Set(activity.vocabularyPackIDs)
        let searchablePhrases = metadataPhrases(for: activity)

        let explicitPacks = specialtyPacks.filter { explicitPackIDs.contains($0.id) }
        let matchedPacks = specialtyPacks.filter { pack in
            !pack.isBase && pack.triggers.contains { trigger in
                searchablePhrases.contains { phrase in
                    containsPhrase(phrase, trigger: trigger)
                }
            }
        }
        let basePacks = specialtyPacks.filter(\.isBase)
        let hasSpecificPack = !explicitPacks.isEmpty || !matchedPacks.isEmpty

        let rankedMatchedPacks = matchedPacks.sorted {
            if $0.isBase != $1.isBase { return !$0.isBase }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.id < $1.id
        }
        let selectedPacks = uniquePacks(
            explicitPacks.sorted { $0.id < $1.id }
                + rankedMatchedPacks
                + basePacks.sorted { $0.id < $1.id }
        )

        let orderedTerms = uniqueTerms(
            activity.speechTerms
                + activity.companies
                + activity.projects
                + selectedPacks.flatMap(\.terms)
        )
        let contextTitle = String(activity.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        let prefix = contextTitle.isEmpty ? "Technical interview vocabulary" : "Context: \(contextTitle). Vocabulary"
        let termBudget = max(0, promptTokenBudget - estimatedTokenCount(prefix) - 2)
        let promptTerms = fitToPromptBudget(orderedTerms, budget: termBudget)
        let prompt = promptTerms.isEmpty ? prefix : "\(prefix): \(promptTerms.joined(separator: ", "))."

        return VocabularyResolution(
            packIDs: selectedPacks.map(\.id),
            terms: promptTerms,
            prompt: prompt,
            usedBaseFallback: !hasSpecificPack
        )
    }

    private func metadataPhrases(for activity: ActivityContext) -> [String] {
        [activity.title]
            + activity.topics
            + activity.tags
            + activity.companies
            + activity.projects
    }

    private func containsPhrase(_ candidate: String, trigger: String) -> Bool {
        let candidateTokens = normalizedTokens(candidate)
        let triggerTokens = normalizedTokens(trigger)
        guard !candidateTokens.isEmpty, !triggerTokens.isEmpty,
              triggerTokens.count <= candidateTokens.count else { return false }

        if triggerTokens.count == 1 {
            return candidateTokens.contains(triggerTokens[0])
        }

        for start in 0...(candidateTokens.count - triggerTokens.count) {
            if Array(candidateTokens[start..<(start + triggerTokens.count)]) == triggerTokens {
                return true
            }
        }
        return false
    }

    private func normalizedTokens(_ value: String) -> [String] {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private func uniquePacks(_ packs: [VocabularyPack]) -> [VocabularyPack] {
        var seen = Set<String>()
        return packs.filter { seen.insert($0.id).inserted }
    }

    private func uniqueTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms.compactMap { raw in
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return nil }
            let key = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { return nil }
            return term
        }
    }

    private func fitToPromptBudget(_ terms: [String], budget: Int) -> [String] {
        guard budget > 0 else { return [] }
        var accepted: [String] = []
        var estimate = 0

        for term in terms {
            let added = estimatedTokenCount(term) + (accepted.isEmpty ? 0 : 1)
            guard estimate + added <= budget else { continue }
            accepted.append(term)
            estimate += added
        }
        return accepted
    }

    private func estimatedTokenCount(_ value: String) -> Int {
        let wordCount = max(1, value.split(whereSeparator: \.isWhitespace).count)
        let characterEstimate = max(1, Int(ceil(Double(value.utf8.count) / 3.2)))
        return max(wordCount, characterEstimate)
    }
}
