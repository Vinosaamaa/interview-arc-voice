---
schemaVersion: 1
id: postmortem-native-voice-delivery-recovery
revision: 1
type: postmortem
status: closed
title: Bound Voice delivery recovery
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-voice-group-delivery-retry-conflict"]
createdAt: 2026-08-05
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoiceCore/LiveUpdatePolicy.swift","Sources/InterviewArcVoiceCore/VoiceAPIModels.swift","docs/protocol-v2.md"]
seams: ["SwiftUI/macOS shell ↔ Voice core","native Voice ↔ hosted Interview Arc"]
adapters: ["Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/InterviewArcAPIClient.swift","Sources/InterviewArcVoiceCore/LiveUpdatePolicy.swift","Sources/InterviewArcVoiceCore/PendingVoiceCaptureStore.swift","Sources/InterviewArcVoiceCore/VoiceAPIModels.swift","Sources/InterviewArcVoiceCore/VoicePipeline.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-voice-group-delivery-retry-conflict"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #171","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/171","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:171","head-commit:bf82f531384c9bb1cab6b4063a03110a92504e2b","merge-commit:5aa36748573e237028344b46dc8bda2ae3e8d62a"]}
visibility: public-safe
publicationEligibility: eligible
issue: 64
pr: 171
release: null
run: null
---
# Bound Voice delivery recovery

Evidence-indexed reconstruction of pull request #171. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
