---
schemaVersion: 1
id: postmortem-successful-transcript-audio-evidence-loss
revision: 1
type: postmortem
status: closed
title: Retain exact audio for Recent Transcripts
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-successful-transcript-audio-evidence-loss"]
createdAt: 2026-07-31
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["no explicit public interface file changed"]
seams: ["SwiftUI/macOS shell ↔ Voice core","microphone/audio ↔ transcription provider","Voice capture ↔ foreground editor"]
adapters: ["Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/GeneralDictationPipeline.swift","Sources/InterviewArcVoiceCore/RecordingStore.swift","Sources/InterviewArcVoiceCore/TranscriptRecovery.swift","Sources/InterviewArcVoiceCore/VoicePipeline.swift","Tests/InterviewArcVoiceCoreTests/RecentTranscriptAudioRetentionTests.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-successful-transcript-audio-evidence-loss"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #111","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/111","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:111","head-commit:e9721bbdafbfcd279b49011f918e89677c0c1a85","merge-commit:3fc1a27f9534936a487c29619f1bb0abe4b23edf"]}
visibility: public-safe
publicationEligibility: eligible
issue: 107
pr: 111
release: null
run: null
---
# Retain exact audio for Recent Transcripts

Evidence-indexed reconstruction of pull request #111. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
