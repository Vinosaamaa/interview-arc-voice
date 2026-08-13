---
schemaVersion: 1
id: change-note-learning-voice-timer-control
revision: 1
type: change-note
status: released
title: Arc Voice Controls the Authoritative Learning Timer
repository: interview-arc-voice
capabilityIds: ["arc-voice","learning-workspace"]
createdAt: 2026-08-13
reconstructed: false
confidence: verified
unknowns: ["Signed merged-main packaged-app verification remains a release gate."]
modules: ["voice-context","floating-widget"]
interfaces: ["voice-learning-timer-control"]
seams: ["learning-session-to-native-timer"]
adapters: ["interview-arc-worker","swiftui-floating-widget"]
relatedRecords: ["change-note-learning-voice-transcript-only@1"]
decisions: []
incidents: []
features: ["learn-workspace"]
capabilities: ["learning-timer-projection","learning-timer-pause-resume"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Arc Voice issue #197","url":"https://github.com/Vinosaamaa/interview-arc-voice/issues/197","kind":"issue"},{"label":"Arc Voice pull request #198","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/198","kind":"pull-request"},{"label":"Interview Arc pull request #318","url":"https://github.com/Vinosaamaa/interview-arc/pull/318","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["Tests/InterviewArcVoiceCoreTests/LearningVoiceContractTests.swift","Tests/InterviewArcVoiceCoreTests/VoiceTimerInstrumentTests.swift","run:31746209628"]}
visibility: public-safe
publicationEligibility: eligible
issue: 197
pr: 198
release: null
run: 31746209628
---
# Arc Voice Controls the Authoritative Learning Timer

Arc Voice already consumed a running Learning Session as a transcript-only capture target, but its timer presentation and controls were coupled only to the Interview workbench instrument. A Learning timer could therefore advance on the website while the native companion displayed no clock.

## Change

Voice now decodes the separate Learning timer projection and advances its elapsed count-up display locally from the Worker’s server timestamp. Standard shows the Lesson title, clock, state, and one Pause or Resume control in the existing floating instrument family. Mini uses the existing single-timer capsule and never invents an Interview session countdown.

Pause and Resume send the stable Learning Session identity, expected revision, action, and one operation ID to the paired Worker Interface. An uncertain exact retry reuses that request. A stale revision, owner mismatch, or ambiguous current timer fails closed and triggers an authoritative context refresh.

## Ownership boundary

Voice does not expose Learning Finish, results, an activity picker, or the Interview Plan Today surface. Finish remains Learning Specialist-owned because it commits recap and checkpoint evidence in addition to stopping time. A paused Learning Session remains visible and resumable but is not eligible for linked Learning transcript capture; recording follows General Dictation until the Session resumes.

## Presentation consequences

The native application keeps Learning and Interview timer semantics distinct while reusing the approved frosted material, monospaced clock, control family, bottom-right anchoring, and Standard/Mini geometry. D1 remains authoritative; the client performs no per-second write and maintains no second durable clock.
