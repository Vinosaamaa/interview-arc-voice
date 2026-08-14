---
schemaVersion: 1
id: change-note-learning-voice-timer-control
revision: 2
type: change-note
status: accepted
title: Arc Voice Coordinates the Learning Timer with Plan Today
repository: interview-arc-voice
capabilityIds: ["arc-voice","learning-workspace"]
createdAt: 2026-08-14
reconstructed: false
confidence: verified
unknowns: ["Canonical macOS CI and signed merged-main packaged-app verification remain release gates."]
modules: ["voice-context","floating-widget"]
interfaces: ["voice-learning-timer-control","voice-today-planner"]
seams: ["learning-session-to-native-timer","learning-timer-to-interview-planner"]
adapters: ["interview-arc-worker","swiftui-floating-widget"]
relatedRecords: ["change-note-learning-voice-transcript-only@1"]
decisions: []
incidents: []
features: ["learn-workspace"]
capabilities: ["learning-timer-projection","learning-timer-pause-resume","learning-planner-coexistence","cross-domain-timer-exclusion"]
amends: ["change-note-learning-voice-timer-control@1"]
supersedes: []
learningRefs: []
sources: [{"label":"Arc Voice issue #197","url":"https://github.com/Vinosaamaa/interview-arc-voice/issues/197","kind":"issue"},{"label":"Arc Voice pull request #198","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/198","kind":"pull-request"},{"label":"Arc Voice pull request #199","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/199","kind":"pull-request"},{"label":"Interview Arc pull request #318","url":"https://github.com/Vinosaamaa/interview-arc/pull/318","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["Tests/InterviewArcVoiceCoreTests/LearningVoiceContractTests.swift","Tests/InterviewArcVoiceCoreTests/TodayPlannerTests.swift","Tests/InterviewArcVoiceCoreTests/TodayPlanningTimerControlTests.swift","parser:passed","public-safety:passed"]}
visibility: public-safe
publicationEligibility: eligible
issue: 197
pr: 199
release: null
run: null
---
# Arc Voice Coordinates the Learning Timer with Plan Today

Arc Voice already consumed a running Learning Session as a transcript-only capture target, but its timer presentation and controls were coupled only to the Interview workbench instrument. A Learning timer could therefore advance on the website while the native companion displayed no clock.

## Change

Voice now decodes the separate Learning timer projection and advances its elapsed count-up display locally from the Worker’s server timestamp. Standard shows the Lesson title, clock, state, and one Pause or Resume control in the existing floating instrument family. Mini uses the existing single-timer capsule and never invents an Interview session countdown.

Pause and Resume send the stable Learning Session identity, expected revision, action, and one operation ID to the paired Worker Interface. An uncertain exact retry reuses that request. A stale revision, owner mismatch, or ambiguous current timer fails closed and triggers an authoritative context refresh.

The first native release treated the separate Learning timer as a Plan Today exclusion. Planner opening rejected any Learning timer, context refresh dismissed an open planner, and the Learning Focus panel omitted the established outer switcher. The timer itself worked, but the owner could not plan while it was visible.

## Planner coexistence

Learning Focus now uses the same outer Focus and Plan Today presentation contract as Interview timers. Plan Today keeps a compact Learning band visible with Lesson identity, elapsed time, state, and the exact Pause or Resume control. Browsing, selection, and planning mutations remain independent from the Learning timer and survive context refresh, Mini entry, and recording hide and restore.

The native planner locks Interview Start and Resume while Learning is running. The owner explicitly pauses Learning, and only the resulting authoritative paused revision re-enables Interview timers. Voice deliberately does not chain a Learning Pause and Interview Start into one locally assumed transaction; a partial transport failure therefore cannot silently select the wrong timer domain. An already-running Interview activity retains Pause as a recovery path if legacy conflicting state must be unwound.

## Ownership boundary

Voice does not expose Learning Finish, results, or an activity picker. Finish remains Learning Specialist-owned because it commits recap and checkpoint evidence in addition to stopping time. A paused Learning Session remains visible and resumable but is not eligible for linked Learning transcript capture; recording follows General Dictation until the Session resumes.

## Presentation consequences

The native application keeps Learning and Interview timer semantics distinct while reusing the approved frosted material, monospaced clock, control family, bottom-right anchoring, and Standard/Mini geometry. D1 remains authoritative; the client performs no per-second write and maintains no second durable clock. Plan Today becomes a shared planning surface without becoming a shared timer authority.
