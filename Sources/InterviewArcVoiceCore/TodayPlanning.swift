import Foundation

public enum VoicePlanningSpecialty: String, Codable, CaseIterable, Hashable, Sendable {
    case leetcode
    case systemDesign = "system_design"
    case behavioral

    public var title: String {
        switch self {
        case .leetcode: "Coding"
        case .systemDesign: "System design"
        case .behavioral: "Behavioral"
        }
    }
}

public enum VoicePlanningDifficulty: String, Codable, CaseIterable, Hashable, Sendable {
    case easy
    case medium
    case hard
}

public enum VoicePlanningSort: String, Codable, CaseIterable, Hashable, Sendable {
    case frequency
    case recent
    case acceptance

    public var title: String {
        switch self {
        case .frequency: "Frequency"
        case .recent: "Recently practiced"
        case .acceptance: "Acceptance"
        }
    }

    public func directionTitle(_ direction: VoicePlanningDirection) -> String {
        switch (self, direction) {
        case (.recent, .descending): "Newest first"
        case (.recent, .ascending): "Oldest first"
        case (_, .descending): "High first"
        case (_, .ascending): "Low first"
        }
    }
}

public enum VoicePlanningDirection: String, Codable, Hashable, Sendable {
    case ascending = "asc"
    case descending = "desc"
}

public enum VoicePlanningAttention: String, Codable, CaseIterable, Hashable, Sendable {
    case due
    case needsReview = "needs_review"
    case solved
    case helped
    case failed
    case todo

    public var title: String {
        switch self {
        case .due: "Due now"
        case .needsReview: "Needs review"
        case .solved: "Solved"
        case .helped: "Solved with help"
        case .failed: "Failed"
        case .todo: "To do"
        }
    }
}

public struct VoicePlanningQuery: Equatable, Sendable {
    public var search: String
    public var starredOnly: Bool
    public var attention: Set<VoicePlanningAttention>
    public var difficulty: Set<VoicePlanningDifficulty>
    public var sort: VoicePlanningSort
    public var direction: VoicePlanningDirection

    public init(
        search: String = "",
        starredOnly: Bool = false,
        attention: Set<VoicePlanningAttention> = [],
        difficulty: Set<VoicePlanningDifficulty> = [],
        sort: VoicePlanningSort = .frequency,
        direction: VoicePlanningDirection = .descending
    ) {
        self.search = search
        self.starredOnly = starredOnly
        self.attention = attention
        self.difficulty = difficulty
        self.sort = sort
        self.direction = direction
    }

    public var activeFilterCount: Int {
        attention.count + difficulty.count
    }
}

public enum VoicePlanningCareerPolicy {
    public static let jobApplicationMinutes = 60
}

public enum VoicePlanningSurface: String, CaseIterable, Sendable {
    case current = "Today"
    case activities = "Activities"
    case fullSession = "Full session"
}

public enum VoicePlanningCategory: String, CaseIterable, Sendable {
    case leetcode
    case systemDesign = "system_design"
    case behavioral
    case career

    public var specialty: VoicePlanningSpecialty? {
        VoicePlanningSpecialty(rawValue: rawValue)
    }
}

public enum VoiceUpperSurfaceContent: Equatable, Sendable {
    case focus
    case plan
}

public struct VoiceUpperSurfaceDisclosure: Equatable, Sendable {
    public let panelPresented: Bool
    public let content: VoiceUpperSurfaceContent

    public init(panelPresented: Bool, content: VoiceUpperSurfaceContent) {
        self.panelPresented = panelPresented
        self.content = content
    }
}

public enum VoiceUpperSurfacePolicy {
    public static func restoredAfterRecording(
        previous: VoiceUpperSurfaceDisclosure
    ) -> VoiceUpperSurfaceDisclosure {
        previous
    }
}

public enum VoicePlannerEntryPolicy {
    public static func canPresentPlanner(
        linkEnabled: Bool,
        hasLearningTimer: Bool,
        isRecording: Bool,
        isStartingRecording: Bool
    ) -> Bool {
        // Learning is a timer source, not a planner exclusion. Keep the input
        // explicit so future timer integrations cannot silently restore the
        // released learning-only guard.
        _ = hasLearningTimer
        return linkEnabled && !isRecording && !isStartingRecording
    }

    public static func showsStandardEntry(
        linkEnabled: Bool,
        hasTimerInstrument: Bool,
        isRecording: Bool,
        isBusy: Bool
    ) -> Bool {
        linkEnabled
            && !hasTimerInstrument
            && !isRecording
            && !isBusy
    }
}

public struct VoicePlanningMutationIdentity: Equatable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func new() -> VoicePlanningMutationIdentity {
        VoicePlanningMutationIdentity(rawValue: "voice-plan-\(UUID().uuidString.lowercased())")
    }
}

public enum VoicePlanningSelectionDraft: Equatable, Hashable, Identifiable, Sendable {
    case practice(
        specialty: VoicePlanningSpecialty,
        questionID: String?,
        title: String,
        minutes: Int,
        url: String?,
        prompt: String?,
        topics: [String]
    )
    case focus(
        title: String,
        minutes: Int,
        note: String?
    )

    public var id: String {
        switch self {
        case .practice(let specialty, let questionID, let title, _, _, _, _):
            return "practice:\(specialty.rawValue):\(questionID ?? title)"
        case .focus(let title, _, _):
            return "focus:job_applications:\(title)"
        }
    }

    public var title: String {
        switch self {
        case .practice(_, _, let title, _, _, _, _), .focus(let title, _, _):
            title
        }
    }

    public var minutes: Int {
        switch self {
        case .practice(_, _, _, let minutes, _, _, _), .focus(_, let minutes, _):
            minutes
        }
    }
}

public struct VoicePlanningPresentationState: Equatable, Sendable {
    public var selectedSpecialty: VoicePlanningSpecialty = .leetcode
    public var selectedCategory: VoicePlanningCategory = .leetcode
    public var surface: VoicePlanningSurface = .current
    public private(set) var selections: [VoicePlanningSelectionDraft] = []
    private var queries: [VoicePlanningSpecialty: VoicePlanningQuery] = [:]
    private var catalogScrollAnchors: [VoicePlanningSpecialty: String] = [:]

    public init() {}

    public func query(for specialty: VoicePlanningSpecialty) -> VoicePlanningQuery {
        queries[specialty] ?? VoicePlanningQuery()
    }

    public mutating func updateQuery(
        _ query: VoicePlanningQuery,
        for specialty: VoicePlanningSpecialty
    ) {
        queries[specialty] = query
    }

    public func catalogScrollAnchor(
        for specialty: VoicePlanningSpecialty
    ) -> String? {
        catalogScrollAnchors[specialty]
    }

    public mutating func updateCatalogScrollAnchor(
        _ itemID: String?,
        for specialty: VoicePlanningSpecialty
    ) {
        catalogScrollAnchors[specialty] = itemID
    }

    public mutating func toggleSelection(_ selection: VoicePlanningSelectionDraft) {
        if let index = selections.firstIndex(where: { $0.id == selection.id }) {
            selections.remove(at: index)
        } else {
            selections.append(selection)
        }
    }

    public mutating func removeSelection(id: String) {
        selections.removeAll { $0.id == id }
    }

    public mutating func clearSelections() {
        selections.removeAll()
    }

    public var totalSelectedMinutes: Int {
        selections.reduce(0) { $0 + $1.minutes }
    }
}

public struct VoicePlanningWorkbench: Codable, Equatable, Sendable {
    public let id: String
    public let date: String?
}

public struct VoicePlanningSummary: Codable, Equatable, Sendable {
    public let sessionCount: Int
    public let activityCount: Int
    public let focusBlockCount: Int
    public let plannedSeconds: Int
}

public struct VoicePlanningCatalogItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let difficulty: String?
    public let acceptanceRate: Double?
    public let topics: [String]?
    public let tags: [String]?
    public let url: String?
    public let prompt: String?
    public let targetMinutes: Int
    public let eligible: Bool
    public let disabledReason: String?
    public let starred: Bool
    public let lastCompletedAt: Int64?
    public var attention: [VoicePlanningAttention]? = nil
}

public struct VoicePlanningCatalog: Codable, Equatable, Sendable {
    public let specialty: VoicePlanningSpecialty
    public let items: [VoicePlanningCatalogItem]
    public let page: Int
    public let pageSize: Int
    public let total: Int
    public let hasMore: Bool
    public var attentionCounts: [String: Int]? = nil
    public var difficultyCounts: [String: Int]? = nil
}

public struct VoicePlanningCurrentSession: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let allocatedSeconds: Int
    public let activityIds: [String]
}

public struct VoicePlanningCurrentActivity: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let allocatedSeconds: Int
    public let questionId: String?
    public let sessionId: String?
    public let status: String?
}

public struct VoicePlanningCurrentFocus: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let plannedSeconds: Int
}

public struct VoicePlanningCurrent: Codable, Equatable, Sendable {
    public let sessions: [VoicePlanningCurrentSession]
    public let activities: [VoicePlanningCurrentActivity]
    public let focusBlocks: [VoicePlanningCurrentFocus]
}

public struct VoicePlanningResponse: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let date: String
    public let workbench: VoicePlanningWorkbench?
    public let summary: VoicePlanningSummary
    public let current: VoicePlanningCurrent
    public let catalog: VoicePlanningCatalog

    public func applying(_ authoritative: VoicePlanningAuthoritative) -> Self {
        Self(
            protocolVersion: protocolVersion,
            date: date,
            workbench: authoritative.workbench,
            summary: VoicePlanningSummary(
                sessionCount: authoritative.sessions.count,
                activityCount: authoritative.activities.count,
                focusBlockCount: authoritative.focusBlocks.count,
                plannedSeconds: authoritative.sessions.reduce(0) { $0 + $1.allocatedSeconds }
                    + authoritative.activities
                        .filter { $0.sessionId == nil }
                        .reduce(0) { $0 + $1.allocatedSeconds }
                    + authoritative.focusBlocks.reduce(0) { $0 + $1.plannedSeconds }
            ),
            current: VoicePlanningCurrent(
                sessions: authoritative.sessions,
                activities: authoritative.activities,
                focusBlocks: authoritative.focusBlocks
            ),
            catalog: catalog
        )
    }
}

public struct VoicePlanningAuthoritative: Decodable, Sendable {
    public let workbench: VoicePlanningWorkbench?
    public let sessions: [VoicePlanningCurrentSession]
    public let activities: [VoicePlanningCurrentActivity]
    public let focusBlocks: [VoicePlanningCurrentFocus]
}

public struct VoicePlanningMutationRequest: Encodable, Equatable, Sendable {
    public let type: String
    public let mutationId: String
    public let workbenchId: String
    public var destination: String?
    public var selections: [VoicePlanningSelectionPayload]?
    public var coding: Int?
    public var systemDesign: Int?
    public var behavioral: Int?
    public var specialty: VoicePlanningSpecialty?
    public var questionId: String?
    public var starred: Bool?
    public var kind: String?
    public var id: String?
    public var newWorkbenchId: String?

    public init(
        type: String,
        mutationId: String = VoicePlanningMutationIdentity.new().rawValue,
        workbenchId: String,
        destination: String? = nil,
        selections: [VoicePlanningSelectionPayload]? = nil,
        coding: Int? = nil,
        systemDesign: Int? = nil,
        behavioral: Int? = nil,
        specialty: VoicePlanningSpecialty? = nil,
        questionId: String? = nil,
        starred: Bool? = nil,
        kind: String? = nil,
        id: String? = nil,
        newWorkbenchId: String? = nil
    ) {
        self.type = type
        self.mutationId = mutationId
        self.workbenchId = workbenchId
        self.destination = destination
        self.selections = selections
        self.coding = coding
        self.systemDesign = systemDesign
        self.behavioral = behavioral
        self.specialty = specialty
        self.questionId = questionId
        self.starred = starred
        self.kind = kind
        self.id = id
        self.newWorkbenchId = newWorkbenchId
    }
}

public enum VoicePlanningFullSessionPolicy {
    public static let codingMinutes = 40
    public static let interviewMinutes = 60
    public static let defaultCodingCount = 6
    public static let defaultSystemDesignCount = 1
    public static let defaultBehavioralCount = 1

    public static func totalMinutes(
        coding: Int,
        systemDesign: Int,
        behavioral: Int
    ) -> Int {
        max(0, coding) * codingMinutes
            + max(0, systemDesign) * interviewMinutes
            + max(0, behavioral) * interviewMinutes
    }
}

public enum VoicePlanningCurrentStatus: Equatable, Sendable {
    case running
    case paused
    case completed
    case upcoming

    public var title: String {
        switch self {
        case .running: "Running"
        case .paused: "Paused"
        case .completed: "Completed"
        case .upcoming: "Upcoming"
        }
    }
}

public enum VoicePlanningTimerControlPolicy {
    public static func isEnabled(
        subjectID: String,
        status: VoicePlanningCurrentStatus,
        runningSubjectID: String?,
        learningTimerIsRunning: Bool = false,
        mutationInFlight: Bool
    ) -> Bool {
        guard status != .completed, !mutationInFlight else { return false }
        if learningTimerIsRunning, status != .running { return false }
        return runningSubjectID == nil || runningSubjectID == subjectID
    }
}

public struct VoicePlanningSelectionPayload: Encodable, Equatable, Sendable {
    public let kind: String
    public var specialty: VoicePlanningSpecialty?
    public var questionId: String?
    public let title: String
    public let minutes: Int
    public var url: String?
    public var prompt: String?
    public var topics: [String]?
    public var focusCategory: String?
    public var note: String?

    public init(draft: VoicePlanningSelectionDraft) {
        switch draft {
        case .practice(
            let specialty,
            let questionID,
            let title,
            let minutes,
            let url,
            let prompt,
            let topics
        ):
            kind = "practice"
            self.specialty = specialty
            questionId = questionID
            self.title = title
            self.minutes = minutes
            self.url = url
            self.prompt = prompt
            self.topics = topics
            focusCategory = nil
            note = nil
        case .focus(let title, let minutes, let note):
            kind = "focus"
            specialty = nil
            questionId = nil
            self.title = title
            self.minutes = minutes
            url = nil
            prompt = nil
            topics = nil
            focusCategory = "job_applications"
            self.note = note
        }
    }
}

public struct VoicePlanningMutationResponse: Decodable, Sendable {
    public let protocolVersion: Int
    public let duplicate: Bool?
    public let authoritative: VoicePlanningAuthoritative?
}
