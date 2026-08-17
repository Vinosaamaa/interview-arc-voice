---
schemaVersion: 1
id: postmortem-recovered-transcript-checksum-mismatch
revision: 1
type: postmortem
status: closed
title: Canonicalize Voice transcript identity before delivery
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-recovered-transcript-checksum-mismatch"]
createdAt: 2026-08-07
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted.","Sensitive source values and nonessential risky evidence links were omitted from this staged record."]
modules: ["Sources:InterviewArcVoiceCore"]
interfaces: ["Tests/InterviewArcVoiceCoreTests/TranscriptRecoveryPolicyTests.swift","docs/protocol-v2.md"]
seams: ["native Voice ↔ hosted Interview Arc"]
adapters: ["Sources/InterviewArcVoiceCore/InterviewArcAPIClient.swift","Sources/InterviewArcVoiceCore/VoicePipeline.swift","Tests/InterviewArcVoiceCoreTests/TranscriptRecoveryPolicyTests.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-recovered-transcript-checksum-mismatch"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #183","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/183","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:183","head-commit:11b4ec758f2c8b5706ae83d31959de9ebbc7c66f","merge-commit:a1104dd323d5f43629ab78f7a6298d117fe04407"]}
visibility: public-safe
publicationEligibility: eligible
issue: 182
pr: 183
release: null
run: null
---
# Canonicalize Voice transcript identity before delivery

Evidence-indexed reconstruction of pull request #183. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
