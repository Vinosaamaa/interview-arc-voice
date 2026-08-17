---
schemaVersion: 1
id: postmortem-header-only-recording-regression
revision: 1
type: postmortem
status: closed
title: Fix packaged voice capture and widget recovery controls
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-header-only-recording-regression"]
createdAt: 2026-07-24
reconstructed: true
confidence: high
unknowns: ["An explicit linked issue was not exposed.","Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["no explicit public interface file changed"]
seams: ["SwiftUI/macOS shell ↔ Voice core","microphone/audio ↔ transcription provider","Voice capture ↔ foreground editor"]
adapters: ["Sources/InterviewArcVoice/AppInfrastructure.swift","Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/AudioRecorder.swift","Sources/InterviewArcVoiceCore/IntegrityMonitoring.swift","Tests/InterviewArcVoiceCoreTests/IntegrityMonitorTests.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-header-only-recording-regression"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #11","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/11","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:11","head-commit:a29ca9d750bfd9f43a8b51ec377ff69c7a0ad7f5","merge-commit:2ee8aa17d19f91625f2498e63a3986be83cc4063"]}
visibility: public-safe
publicationEligibility: eligible
issue: null
pr: 11
release: null
run: null
---
# Fix packaged voice capture and widget recovery controls

Evidence-indexed reconstruction of pull request #11. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
