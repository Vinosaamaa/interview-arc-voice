---
schemaVersion: 1
id: postmortem-partial-transcript-delivery
revision: 1
type: postmortem
status: closed
title: P0: reject lexically incomplete voice transcripts
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-partial-transcript-delivery"]
createdAt: 2026-08-01
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted.","Sensitive source values and nonessential risky evidence links were omitted from this staged record."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["no explicit public interface file changed"]
seams: ["SwiftUI/macOS shell ↔ Voice core"]
adapters: ["Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/IntegrityMonitoring.swift","Sources/InterviewArcVoiceCore/VoiceDiagnostics.swift","Sources/InterviewArcVoiceCore/VoicePipeline.swift","Tests/InterviewArcVoiceCoreTests/IntegrityMonitorTests.swift","Tests/InterviewArcVoiceCoreTests/VoiceDiagnosticsTests.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-partial-transcript-delivery"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #136","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/136","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:136","head-commit:eb703a5768c4b2bf5a61e6823c06c178aa640b55","merge-commit:58b30a1908a7433cbc4952d1f20ab63bf42e8b62"]}
visibility: public-safe
publicationEligibility: eligible
issue: 123
pr: 136
release: null
run: null
---
# P0: reject lexically incomplete voice transcripts

Evidence-indexed reconstruction of pull request #136. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
