---
schemaVersion: 1
id: postmortem-long-dictation-transcript-integrity
revision: 1
type: postmortem
status: closed
title: Fix long dictation transcript integrity and recovery
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-long-dictation-transcript-integrity"]
createdAt: 2026-07-24
reconstructed: true
confidence: high
unknowns: ["An explicit linked issue was not exposed.","Attachment bodies and workflow logs were not quoted.","Sensitive source values and nonessential risky evidence links were omitted from this staged record."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["no explicit public interface file changed"]
seams: ["SwiftUI/macOS shell ↔ Voice core","microphone/audio ↔ transcription provider","Voice capture ↔ foreground editor"]
adapters: ["Sources/InterviewArcVoice/AppInfrastructure.swift","Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/AudioRecorder.swift","Sources/InterviewArcVoiceCore/GeneralDictationPipeline.swift","Sources/InterviewArcVoiceCore/GroqTranscriber.swift","Tests/InterviewArcVoiceCoreTests/VocabularyResolverTests.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-long-dictation-transcript-integrity"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #9","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/9","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:9","head-commit:37d2fbc78c3d78f03f53acd6a6fdeb28f69ba8bd","merge-commit:0310ff1e675d2b01b47aa3309f8f4fa76ca82417"]}
visibility: public-safe
publicationEligibility: eligible
issue: null
pr: 9
release: null
run: null
---
# Fix long dictation transcript integrity and recovery

Evidence-indexed reconstruction of pull request #9. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
