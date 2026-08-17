---
schemaVersion: 1
id: postmortem-invalid-groq-credential-retry-loop
revision: 1
type: postmortem
status: closed
title: Harden Voice transcript recovery
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-invalid-groq-credential-retry-loop"]
createdAt: 2026-07-29
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoiceCore/VoiceAPIModels.swift","Tests/InterviewArcVoiceCoreTests/TranscriptRecoveryPolicyTests.swift"]
seams: ["SwiftUI/macOS shell ↔ Voice core","microphone/audio ↔ transcription provider","native credential UI ↔ macOS Keychain","native Voice ↔ hosted Interview Arc"]
adapters: ["Sources/InterviewArcVoice/AppInfrastructure.swift","Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/GroqTranscriber.swift","Sources/InterviewArcVoiceCore/RecordingStore.swift","Sources/InterviewArcVoiceCore/TranscriptRecovery.swift","Sources/InterviewArcVoiceCore/VoiceAPIModels.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-invalid-groq-credential-retry-loop"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #89","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/89","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:89","head-commit:908731b6afb289372afeacd7b9fca4c293ad0158","merge-commit:43f89cc317175cd804ddf37b7b240963e98399f0"]}
visibility: public-safe
publicationEligibility: eligible
issue: 87
pr: 89
release: null
run: null
---
# Harden Voice transcript recovery

Evidence-indexed reconstruction of pull request #89. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
