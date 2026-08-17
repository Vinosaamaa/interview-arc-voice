---
schemaVersion: 1
id: postmortem-live-sync-polling-and-capture-retry-storm
revision: 1
type: postmortem
status: closed
title: Bound Voice live synchronization and capture recovery
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-live-sync-polling-and-capture-retry-storm"]
createdAt: 2026-07-27
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted.","Sensitive source values and nonessential risky evidence links were omitted from this staged record."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Sources/InterviewArcVoiceCore/LiveUpdatePolicy.swift","Sources/InterviewArcVoiceCore/VoiceAPIModels.swift","docs/protocol-v2.md"]
seams: ["SwiftUI/macOS shell ↔ Voice core","native Voice ↔ hosted Interview Arc"]
adapters: ["Sources/InterviewArcVoice/AppInfrastructure.swift","Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Sources/InterviewArcVoiceCore/InterviewArcAPIClient.swift","Sources/InterviewArcVoiceCore/LiveUpdatePolicy.swift","Sources/InterviewArcVoiceCore/PendingVoiceCaptureStore.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-live-sync-polling-and-capture-retry-storm"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #70","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/70","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:70","head-commit:afa30ca684c385d15703afe7c0e9d248cb31c672","merge-commit:ebebb8814dc2f6ef4cb77d37f8b7acabde0f3303"]}
visibility: public-safe
publicationEligibility: eligible
issue: 64
pr: 70
release: null
run: null
---
# Bound Voice live synchronization and capture recovery

Evidence-indexed reconstruction of pull request #70. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
