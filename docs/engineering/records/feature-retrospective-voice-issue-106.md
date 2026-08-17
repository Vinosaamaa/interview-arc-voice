---
schemaVersion: 1
id: feature-retrospective-voice-issue-106
revision: 1
type: feature-retrospective
status: released
title: Add native Voice Today planner
repository: interview-arc-voice
capabilityIds: ["voice-issue-106"]
createdAt: 2026-07-31
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift"]
seams: ["SwiftUI/macOS shell ↔ Voice core","native Voice ↔ hosted Interview Arc"]
adapters: ["Sources/InterviewArcVoice/AppInfrastructure.swift","Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Sources/InterviewArcVoiceCore/InterviewArcAPIClient.swift","Sources/InterviewArcVoiceCore/TodayPlanning.swift","Tests/InterviewArcVoiceCoreTests/TodayPlannerTests.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-issue-106"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #108","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/108","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:108","head-commit:14762b5abf6909081eb6fa997543e1720794e6e7","merge-commit:e5109e55a2dae7908c5ad1017d3c53fbce647680"]}
visibility: public-safe
publicationEligibility: eligible
issue: 106
pr: 108
release: null
run: null
---
# Add native Voice Today planner

Evidence-indexed reconstruction of pull request #108. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
