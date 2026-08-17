---
schemaVersion: 1
id: postmortem-intermittent-silent-input-stream
revision: 1
type: postmortem
status: closed
title: Recover silent recordings and gate linked captures by intent
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-intermittent-silent-input-stream"]
createdAt: 2026-07-26
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Sources/InterviewArcVoiceCore/MicrophoneSignalPolicy.swift","Sources/InterviewArcVoiceCore/VoiceAPIModels.swift","Tests/InterviewArcVoiceCoreTests/LiveContextPolicyTests.swift","Tests/InterviewArcVoiceCoreTests/MicrophoneSignalPolicyTests.swift","docs/protocol-v2.md"]
seams: ["SwiftUI/macOS shell ↔ Voice core","native Voice ↔ hosted Interview Arc"]
adapters: ["Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/AudioRecorder.swift","Sources/InterviewArcVoiceCore/CaptureRouting.swift","Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Sources/InterviewArcVoiceCore/InterviewArcAPIClient.swift","Sources/InterviewArcVoiceCore/MicrophoneSignalPolicy.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-intermittent-silent-input-stream"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #61","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/61","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:61","head-commit:1959e5940a86c13a89b3f67bc269306e11a8e5b8","merge-commit:dee34619761df01fba563be8f843379e8ac5d800"]}
visibility: public-safe
publicationEligibility: eligible
issue: 58
pr: 61
release: null
run: null
---
# Recover silent recordings and gate linked captures by intent

Evidence-indexed reconstruction of pull request #61. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
