---
schemaVersion: 1
id: change-note-voice-mini-widget
revision: 1
type: change-note
status: released
title: Add optional Mini floating widget mode
repository: interview-arc-voice
capabilityIds: ["voice-mini-widget"]
createdAt: 2026-07-30
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift"]
seams: ["SwiftUI/macOS shell ↔ Voice core"]
adapters: ["Sources/InterviewArcVoice/AppInfrastructure.swift","Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Sources/InterviewArcVoiceCore/VoiceWidgetSizeMode.swift","Tests/InterviewArcVoiceCoreTests/VoiceWidgetSizeModeTests.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-mini-widget"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #98","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/98","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:98","head-commit:6c607cda3d55def5766eae6e59340a48ede97e42","merge-commit:823870d4c558297230a2669ca7c507a7939ee89d"]}
visibility: public-safe
publicationEligibility: eligible
issue: 96
pr: 98
release: null
run: null
---
# Add optional Mini floating widget mode

Evidence-indexed reconstruction of pull request #98. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
