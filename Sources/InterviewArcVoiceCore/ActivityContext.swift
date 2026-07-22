import Foundation

public enum PracticeSpecialty: String, Codable, CaseIterable, Sendable {
    case coding
    case systemDesign = "system-design"
    case behavioral
}

public struct ActivityContext: Codable, Equatable, Sendable {
    public let activityID: String
    public let specialty: PracticeSpecialty
    public let title: String
    public let topics: [String]
    public let tags: [String]
    public let companies: [String]
    public let projects: [String]
    public let vocabularyPackIDs: [String]
    public let speechTerms: [String]

    public init(
        activityID: String,
        specialty: PracticeSpecialty,
        title: String,
        topics: [String] = [],
        tags: [String] = [],
        companies: [String] = [],
        projects: [String] = [],
        vocabularyPackIDs: [String] = [],
        speechTerms: [String] = []
    ) {
        self.activityID = activityID
        self.specialty = specialty
        self.title = title
        self.topics = topics
        self.tags = tags
        self.companies = companies
        self.projects = projects
        self.vocabularyPackIDs = vocabularyPackIDs
        self.speechTerms = speechTerms
    }
}

