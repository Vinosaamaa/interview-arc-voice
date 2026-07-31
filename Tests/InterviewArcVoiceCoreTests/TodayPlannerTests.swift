import Foundation
import Testing
@testable import InterviewArcVoiceCore

@Test
func plannerKeepsSpecialtyQueryStateIndependent() {
    var state = VoicePlanningPresentationState()
    state.updateQuery(
        VoicePlanningQuery(
            search: "graph",
            starredOnly: true,
            attention: [.due, .todo],
            difficulty: [.medium, .hard],
            sort: .acceptance,
            direction: .descending
        ),
        for: .leetcode
    )

    #expect(state.query(for: .leetcode).search == "graph")
    #expect(state.query(for: .leetcode).starredOnly)
    #expect(state.query(for: .leetcode).attention == [.due, .todo])
    #expect(state.query(for: .systemDesign) == VoicePlanningQuery())
    #expect(state.query(for: .behavioral) == VoicePlanningQuery())
}

@Test
func plannerFilterCountAndSortCopyStayExplicit() {
    let query = VoicePlanningQuery(
        attention: [.due, .todo],
        difficulty: [.hard],
        sort: .recent,
        direction: .descending
    )

    #expect(query.activeFilterCount == 3)
    #expect(query.sort.title == "Recently practiced")
    #expect(query.sort.directionTitle(query.direction) == "Newest first")
    #expect(VoicePlanningSort.acceptance.directionTitle(.ascending) == "Low first")
}

@Test
func jobApplicationsUseTheFixedCareerFocusDuration() {
    #expect(VoicePlanningCareerPolicy.jobApplicationMinutes == 60)
}

@Test
func fullSessionEstimateMatchesTheWebsiteRecipeDurations() {
    #expect(VoicePlanningFullSessionPolicy.defaultCodingCount == 6)
    #expect(VoicePlanningFullSessionPolicy.defaultSystemDesignCount == 1)
    #expect(VoicePlanningFullSessionPolicy.defaultBehavioralCount == 1)
    #expect(
        VoicePlanningFullSessionPolicy.totalMinutes(
            coding: VoicePlanningFullSessionPolicy.defaultCodingCount,
            systemDesign: VoicePlanningFullSessionPolicy.defaultSystemDesignCount,
            behavioral: VoicePlanningFullSessionPolicy.defaultBehavioralCount
        ) == 360
    )
}

@Test
func plannerKeepsCategoryAndScrollAnchorAcrossTemporaryDisclosureChanges() {
    var state = VoicePlanningPresentationState()
    state.selectedCategory = .systemDesign
    state.selectedSpecialty = .systemDesign
    state.updateCatalogScrollAnchor(
        "design-facebook-marketplace",
        for: .systemDesign
    )
    state.surface = .current
    state.surface = .activities

    #expect(state.selectedCategory == .systemDesign)
    #expect(state.selectedSpecialty == .systemDesign)
    #expect(
        state.catalogScrollAnchor(for: .systemDesign)
            == "design-facebook-marketplace"
    )
    #expect(state.catalogScrollAnchor(for: .leetcode) == nil)
}

@Test
func plannerSelectionSurvivesCatalogAndDisclosureChanges() {
    let draft = VoicePlanningSelectionDraft.practice(
        specialty: .leetcode,
        questionID: "course-schedule",
        title: "Course Schedule",
        minutes: 40,
        url: nil,
        prompt: nil,
        topics: ["Graph"]
    )
    var state = VoicePlanningPresentationState()
    state.toggleSelection(draft)
    state.selectedSpecialty = .systemDesign
    state.surface = .current

    #expect(state.selections == [draft])
    #expect(state.totalSelectedMinutes == 40)
}

@Test
func plannerRecordingRestoresTheExactUpperSurface() {
    let focus = VoiceUpperSurfaceDisclosure(
        panelPresented: true,
        content: .focus
    )
    let plan = VoiceUpperSurfaceDisclosure(
        panelPresented: true,
        content: .plan
    )
    let collapsed = VoiceUpperSurfaceDisclosure(
        panelPresented: false,
        content: .focus
    )

    #expect(VoiceUpperSurfacePolicy.restoredAfterRecording(previous: focus) == focus)
    #expect(VoiceUpperSurfacePolicy.restoredAfterRecording(previous: plan) == plan)
    #expect(VoiceUpperSurfacePolicy.restoredAfterRecording(previous: collapsed) == collapsed)
}

@Test
func plannerMutationIDsAreStableOnlyForAnExplicitRetry() {
    let first = VoicePlanningMutationIdentity.new()
    let retry = first
    let next = VoicePlanningMutationIdentity.new()

    #expect(first == retry)
    #expect(first != next)
    #expect(first.rawValue.hasPrefix("voice-plan-"))
}

@Test
func plannerDecodesTheAuthoritativeWorkerShape() throws {
    let payload = """
    {
      "protocolVersion": 1,
      "date": "2026-07-30",
      "workbench": {"id": "workbench-1", "date": "2026-07-30"},
      "summary": {
        "sessionCount": 1,
        "activityCount": 2,
        "focusBlockCount": 1,
        "plannedSeconds": 8400
      },
      "current": {
        "sessions": [{
          "id": "session-1",
          "label": "Session 1",
          "allocatedSeconds": 6000,
          "activityIds": ["activity-1", "focus-1"]
        }],
        "activities": [{
          "id": "activity-1",
          "title": "Course Schedule",
          "allocatedSeconds": 2400,
          "questionId": "course-schedule",
          "sessionId": "session-1",
          "status": "planned"
        }],
        "focusBlocks": [{
          "id": "focus-1",
          "title": "Job applications",
          "plannedSeconds": 3600
        }]
      },
      "catalog": {
        "specialty": "leetcode",
        "items": [{
          "id": "course-schedule",
          "title": "Course Schedule",
          "difficulty": "medium",
          "acceptanceRate": 49.8,
          "topics": ["Graph"],
          "tags": [],
          "url": null,
          "prompt": null,
          "targetMinutes": 40,
          "eligible": false,
          "disabledReason": "Already on Today",
          "starred": true,
          "lastCompletedAt": null
        }],
        "page": 1,
        "pageSize": 30,
        "total": 1,
        "hasMore": false
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(VoicePlanningResponse.self, from: payload)
    #expect(decoded.workbench?.id == "workbench-1")
    #expect(decoded.current.focusBlocks.first?.title == "Job applications")
    #expect(decoded.catalog.items.first?.disabledReason == "Already on Today")
}

@Test
func plannerMutationCarriesTheAuthoritativeTodaySnapshot() throws {
    let payload = """
    {
      "protocolVersion": 1,
      "duplicate": false,
      "authoritative": {
        "workbench": {"id": "workbench-1", "date": "2026-07-31"},
        "sessions": [{
          "id": "session-2",
          "label": "Session 2",
          "allocatedSeconds": 3600,
          "activityIds": ["activity-2"]
        }],
        "activities": [{
          "id": "activity-2",
          "title": "Number of Islands",
          "allocatedSeconds": 2400,
          "questionId": "number-of-islands",
          "sessionId": "session-2",
          "status": "planned"
        }],
        "focusBlocks": []
      }
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(VoicePlanningMutationResponse.self, from: payload)
    #expect(decoded.authoritative?.sessions.first?.id == "session-2")
    #expect(decoded.authoritative?.activities.first?.title == "Number of Islands")
}

@Test
func plannerGeometryKeepsTheRecorderAsTheBottomAnchor() {
    #expect(FloatingWidgetWindowPolicy.plannerWidth > FloatingWidgetWindowPolicy.expandedWidth)
    #expect(FloatingWidgetWindowPolicy.plannerHostHeight > FloatingWidgetWindowPolicy.expandedDrawerHostHeight)
    #expect(FloatingWidgetWindowPolicy.recorderIsBottomSurface)
    #expect(FloatingWidgetWindowPolicy.timerGap == 10)
}

@Test
func standardPlannerEntryDoesNotDisappearWhenPreviousMemoActionsExist() {
    #expect(
        VoicePlannerEntryPolicy.showsStandardEntry(
            linkEnabled: true,
            hasTimerInstrument: false,
            isRecording: false,
            isBusy: false
        )
    )
    #expect(
        !VoicePlannerEntryPolicy.showsStandardEntry(
            linkEnabled: true,
            hasTimerInstrument: true,
            isRecording: false,
            isBusy: false
        )
    )
}
