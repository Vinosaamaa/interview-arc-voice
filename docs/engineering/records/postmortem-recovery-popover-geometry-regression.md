---
schemaVersion: 1
id: postmortem-recovery-popover-geometry-regression
revision: 1
type: postmortem
status: closed
title: Fix recovery animation, Bluetooth ducking, and voice controls
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-recovery-popover-geometry-regression"]
createdAt: 2026-07-26
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted.","Sensitive source values and nonessential risky evidence links were omitted from this staged record."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoice/SystemOutputVolumeController.swift","Sources/InterviewArcVoiceCore/BackgroundAudioPolicy.swift","Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Tests/InterviewArcVoiceCoreTests/BackgroundAudioPolicyTests.swift"]
seams: ["SwiftUI/macOS shell ↔ Voice core"]
adapters: ["Sources/InterviewArcVoice/AppInfrastructure.swift","Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoice/SystemOutputVolumeController.swift","Sources/InterviewArcVoiceCore/BackgroundAudioPolicy.swift","Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Tests/InterviewArcVoiceCoreTests/BackgroundAudioPolicyTests.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-recovery-popover-geometry-regression"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #53","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/53","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:53","head-commit:9750764c5cb67988ec2d8eda50e39c3f00d2deae","merge-commit:c119f4c0f70068ac2dbbb72c0a6514976cee5ac1"]}
visibility: public-safe
publicationEligibility: eligible
issue: 37
pr: 53
release: null
run: null
---
# Fix recovery animation, Bluetooth ducking, and voice controls

Evidence-indexed reconstruction of pull request #53. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
