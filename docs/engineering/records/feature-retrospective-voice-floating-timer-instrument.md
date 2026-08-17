---
schemaVersion: 1
id: feature-retrospective-voice-floating-timer-instrument
revision: 1
type: feature-retrospective
status: released
title: Add expandable timer instrument to Voice
repository: interview-arc-voice
capabilityIds: ["voice-floating-timer-instrument"]
createdAt: 2026-07-24
reconstructed: true
confidence: high
unknowns: ["An explicit linked issue was not exposed.","Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Sources/InterviewArcVoiceCore/VoiceAPIModels.swift","Tests/InterviewArcVoiceCoreTests/LiveContextPolicyTests.swift","docs/protocol-v1.md"]
seams: ["SwiftUI/macOS shell ↔ Voice core","native Voice ↔ hosted Interview Arc"]
adapters: ["Sources/InterviewArcVoice/AppInfrastructure.swift","Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Sources/InterviewArcVoiceCore/InterviewArcAPIClient.swift","Sources/InterviewArcVoiceCore/VoiceAPIModels.swift","Tests/InterviewArcVoiceCoreTests/LiveContextPolicyTests.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-floating-timer-instrument"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #27","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/27","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:27","head-commit:fcb3111ce56861b8ef85121ab9ebfcfb6623030e","merge-commit:4ed0bd6e9ec37da9620612a87089876ad6a36a40"]}
visibility: public-safe
publicationEligibility: eligible
issue: null
pr: 27
release: null
run: null
---
# Add expandable timer instrument to Voice

Evidence-indexed reconstruction of pull request #27. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
