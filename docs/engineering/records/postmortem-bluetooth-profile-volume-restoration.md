---
schemaVersion: 1
id: postmortem-bluetooth-profile-volume-restoration
revision: 1
type: postmortem
status: closed
title: Restore Bluetooth audio after the original profile returns
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-bluetooth-profile-volume-restoration"]
createdAt: 2026-07-26
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoice/SystemOutputVolumeController.swift","Sources/InterviewArcVoiceCore/BackgroundAudioPolicy.swift","Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Tests/InterviewArcVoiceCoreTests/BackgroundAudioPolicyTests.swift"]
seams: ["SwiftUI/macOS shell ↔ Voice core"]
adapters: ["Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoice/SystemOutputVolumeController.swift","Sources/InterviewArcVoiceCore/BackgroundAudioPolicy.swift","Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Tests/InterviewArcVoiceCoreTests/BackgroundAudioPolicyTests.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-bluetooth-profile-volume-restoration"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #56","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/56","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:56","head-commit:b577423051912ff786fdb151b0fdcca33e72e90a","merge-commit:e3223202cc3fd4bc84606fee2f5a905029214e97"]}
visibility: public-safe
publicationEligibility: eligible
issue: 38
pr: 56
release: null
run: null
---
# Restore Bluetooth audio after the original profile returns

Evidence-indexed reconstruction of pull request #56. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
