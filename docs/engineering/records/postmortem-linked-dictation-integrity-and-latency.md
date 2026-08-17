---
schemaVersion: 1
id: postmortem-linked-dictation-integrity-and-latency
revision: 1
type: postmortem
status: closed
title: Harden instant capture and transcript integrity
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-linked-dictation-integrity-and-latency"]
createdAt: 2026-07-24
reconstructed: true
confidence: high
unknowns: ["An explicit linked issue was not exposed.","Attachment bodies and workflow logs were not quoted.","Sensitive source values and nonessential risky evidence links were omitted from this staged record."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Sources/InterviewArcVoiceCore/VoiceAPIModels.swift"]
seams: ["SwiftUI/macOS shell ↔ Voice core","Voice capture ↔ foreground editor","native Voice ↔ hosted Interview Arc"]
adapters: ["Sources/InterviewArcVoice/AppInfrastructure.swift","Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/AudioRecorder.swift","Sources/InterviewArcVoiceCore/GeneralDictationPipeline.swift","Sources/InterviewArcVoiceCore/IntegrityMonitoring.swift","Sources/InterviewArcVoiceCore/VoiceAPIModels.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-linked-dictation-integrity-and-latency"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #10","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/10","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:10","head-commit:875a1c08a6aee14b1c4197a4f17968f17a956ab2","merge-commit:f3b8ee2b0d5d925d58b386fb649db07418d9bde8"]}
visibility: public-safe
publicationEligibility: eligible
issue: null
pr: 10
release: null
run: null
---
# Harden instant capture and transcript integrity

Evidence-indexed reconstruction of pull request #10. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
