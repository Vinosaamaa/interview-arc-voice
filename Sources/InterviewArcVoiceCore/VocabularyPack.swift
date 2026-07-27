import Foundation

public struct VocabularyPack: Codable, Equatable, Sendable {
    public let id: String
    public let specialty: PracticeSpecialty
    public let isBase: Bool
    public let priority: Int
    public let triggers: [String]
    public let terms: [String]
}

public struct VocabularyCatalog: Codable, Equatable, Sendable {
    public let version: Int
    public let sources: [VocabularySource]?
    public let packs: [VocabularyPack]

    public static func bundled() throws -> VocabularyCatalog {
        let packagedBundleName = "InterviewArcVoice_InterviewArcVoiceCore.bundle"
        let packagedCandidates = [
            Bundle.main.resourceURL?.appending(path: packagedBundleName),
            Bundle.main.bundleURL.appending(path: packagedBundleName),
            Bundle.main.executableURL?.deletingLastPathComponent().appending(path: packagedBundleName),
        ].compactMap { $0 }
        for bundleURL in packagedCandidates {
            let catalogURL = bundleURL.appending(path: "vocabulary-packs.json")
            if FileManager.default.fileExists(atPath: catalogURL.path) {
                return try JSONDecoder().decode(
                    VocabularyCatalog.self,
                    from: Data(contentsOf: catalogURL)
                )
            }
        }

        // SwiftPM's generated Bundle.module accessor traps when a hand-built
        // .app places the resource bundle somewhere it does not expect. Only
        // reach it after checking the conventional packaged-app locations.
        guard let url = Bundle.module.url(
            forResource: "vocabulary-packs",
            withExtension: "json"
        ) else {
            throw VocabularyCatalogError.missingBundledCatalog
        }

        return try JSONDecoder().decode(
            VocabularyCatalog.self,
            from: Data(contentsOf: url)
        )
    }

    public func generalDictationPrompt(maxTerms: Int = 32) -> String {
        var seen = Set<String>()
        return packs
            .filter(\.isBase)
            .sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.id < $1.id
            }
            .flatMap(\.terms)
            .filter { term in
                seen.insert(term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted
            }
            .prefix(max(1, maxTerms))
            .joined(separator: ", ")
    }
}

public struct VocabularySource: Codable, Equatable, Sendable {
    public let title: String
    public let url: String
    public let consultedAt: String
}

public enum VocabularyCatalogError: Error, Equatable {
    case missingBundledCatalog
}
