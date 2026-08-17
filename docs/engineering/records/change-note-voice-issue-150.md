---
schemaVersion: 1
id: change-note-voice-issue-150
revision: 1
type: change-note
status: released
title: Add floating-widget recovery transcript action
repository: interview-arc-voice
capabilityIds: ["voice-issue-150"]
createdAt: 2026-08-02
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Tests/InterviewArcVoiceCoreTests/TranscriptRecoveryPolicyTests.swift"]
seams: ["SwiftUI/macOS shell ↔ Voice core"]
adapters: ["Sources/InterviewArcVoice/AppInfrastructure.swift","Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Sources/InterviewArcVoiceCore/TranscriptRecovery.swift","Sources/InterviewArcVoiceCore/VoiceFailureNotice.swift","Tests/InterviewArcVoiceCoreTests/TranscriptRecoveryPolicyTests.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-issue-150"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #153","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/153","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:153","head-commit:75d3ed91412c665ad00f48ba4d35007b5e6ea59c","merge-commit:b6eb6c4df3c4733e9693eb06e3a75ec215b9a8ef"]}
visibility: public-safe
publicationEligibility: eligible
issue: 150
pr: 153
release: null
run: null
---
# Add floating-widget recovery transcript action

Evidence-indexed reconstruction of pull request #153. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
