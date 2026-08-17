---
schemaVersion: 1
id: postmortem-false-transcription-from-non-speech
revision: 1
type: postmortem
status: closed
title: Complete the Voice recording and settings release
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-false-transcription-from-non-speech"]
createdAt: 2026-07-25
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoice/SystemOutputVolumeController.swift","Sources/InterviewArcVoiceCore/BackgroundAudioPolicy.swift","Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift","Tests/InterviewArcVoiceCoreTests/BackgroundAudioPolicyTests.swift","Tests/InterviewArcVoiceCoreTests/FloatingWidgetWindowPolicyTests.swift"]
seams: ["SwiftUI/macOS shell ↔ Voice core","microphone/audio ↔ transcription provider"]
adapters: ["Sources/InterviewArcVoice/AppInfrastructure.swift","Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoice/SystemOutputVolumeController.swift","Sources/InterviewArcVoiceCore/AudioRecorder.swift","Sources/InterviewArcVoiceCore/BackgroundAudioPolicy.swift","Sources/InterviewArcVoiceCore/FloatingWidgetWindowPolicy.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-false-transcription-from-non-speech"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #40","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/40","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:40","head-commit:92064f36f887df4f0b38a52ae43c383f3105fae9","merge-commit:5728ec0a5b0de4a9963605c4a0ab2a285dc7e30c"]}
visibility: public-safe
publicationEligibility: eligible
issue: 31
pr: 40
release: null
run: null
---
# Complete the Voice recording and settings release

Evidence-indexed reconstruction of pull request #40. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
