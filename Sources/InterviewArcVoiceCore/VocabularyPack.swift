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
}

public struct VocabularySource: Codable, Equatable, Sendable {
    public let title: String
    public let url: String
    public let consultedAt: String
}

public enum VocabularyCatalogError: Error, Equatable {
    case missingBundledCatalog
}
