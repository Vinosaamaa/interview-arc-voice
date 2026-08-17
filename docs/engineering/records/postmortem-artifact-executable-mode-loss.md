---
schemaVersion: 1
id: postmortem-artifact-executable-mode-loss
revision: 1
type: postmortem
status: closed
title: Restore smooth widget collapse and preserve artifact modes
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-artifact-executable-mode-loss"]
createdAt: 2026-08-03
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice"]
interfaces: [".github/workflows/ci.yml","Tests/ArtifactPromotionPolicyTests.sh"]
seams: ["reviewed tree ↔ packaged macOS artifact"]
adapters: ["Sources/InterviewArcVoice/AppInfrastructure.swift","scripts/archive-app.sh","scripts/validate-artifact-workflow.rb"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-artifact-executable-mode-loss"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #168","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/168","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:168","head-commit:8f14c8095e4fc4519034648a84e4f97093e11f70","merge-commit:96f5cf660ea88621caf44146ca05d583c7d987c6"]}
visibility: public-safe
publicationEligibility: eligible
issue: 37
pr: 168
release: null
run: null
---
# Restore smooth widget collapse and preserve artifact modes

Evidence-indexed reconstruction of pull request #168. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
