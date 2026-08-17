---
schemaVersion: 1
id: postmortem-missed-voice-decision-invalidation
revision: 1
type: postmortem
status: closed
title: Recover missed Voice decision invalidations
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-missed-voice-decision-invalidation"]
createdAt: 2026-07-27
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoiceCore/LiveUpdatePolicy.swift","docs/protocol-v2.md"]
seams: ["SwiftUI/macOS shell ↔ Voice core","native Voice ↔ hosted Interview Arc"]
adapters: ["Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/InterviewArcAPIClient.swift","Sources/InterviewArcVoiceCore/LiveUpdatePolicy.swift","Tests/InterviewArcVoiceCoreTests/LiveReliabilityTests.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-missed-voice-decision-invalidation"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #73","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/73","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:73","head-commit:0be53e821eb9c9f333ed64ddf0ed37f5426c5cde","merge-commit:b13b1062d0a65c0becbd4389db60399304c6ab77"]}
visibility: public-safe
publicationEligibility: eligible
issue: 72
pr: 73
release: null
run: null
---
# Recover missed Voice decision invalidations

Evidence-indexed reconstruction of pull request #73. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
