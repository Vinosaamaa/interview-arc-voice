---
schemaVersion: 1
id: change-note-voice-career-focus-timers
revision: 1
type: change-note
status: released
title: Support Career Focus timers in Voice
repository: interview-arc-voice
capabilityIds: ["voice-career-focus-timers"]
createdAt: 2026-07-27
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoiceCore/VoiceAPIModels.swift","docs/protocol-v1.md"]
seams: ["SwiftUI/macOS shell ↔ Voice core","Voice capture ↔ foreground editor","native Voice ↔ hosted Interview Arc"]
adapters: ["Sources/InterviewArcVoice/AppInfrastructure.swift","Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/GeneralDictationPipeline.swift","Sources/InterviewArcVoiceCore/InterviewArcAPIClient.swift","Sources/InterviewArcVoiceCore/VocabularyPack.swift","Sources/InterviewArcVoiceCore/VoiceAPIModels.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-career-focus-timers"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #76","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/76","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:76","head-commit:50ed9bacd89ccfe2e09878e5c53e021120fb31bc","merge-commit:e92823d56d7c298b1829e582299b9a8bd2764f88"]}
visibility: public-safe
publicationEligibility: eligible
issue: 75
pr: 76
release: null
run: null
---
# Support Career Focus timers in Voice

Evidence-indexed reconstruction of pull request #76. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
