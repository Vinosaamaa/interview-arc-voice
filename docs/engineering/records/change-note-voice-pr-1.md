---
schemaVersion: 1
id: change-note-voice-pr-1
revision: 1
type: change-note
status: released
title: Refresh focus automatically and add macOS app icon
repository: interview-arc-voice
capabilityIds: ["voice-pr-1"]
createdAt: 2026-07-22
reconstructed: true
confidence: high
unknowns: ["An explicit linked issue was not exposed.","Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice"]
interfaces: ["no explicit public interface file changed"]
seams: ["repository-internal change; no cross-boundary seam evidenced"]
adapters: ["Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","scripts/generate-app-icon.sh","scripts/package-app.sh","scripts/package_icns.py"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-pr-1"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #1","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/1","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:1","head-commit:467c0fcbc0a3f62b6476fd18c3d11df73834dc14","merge-commit:0789d8985fe38abaedae3ba3b5b3475f8e51e167"]}
visibility: public-safe
publicationEligibility: eligible
issue: null
pr: 1
release: null
run: null
---
# Refresh focus automatically and add macOS app icon

Evidence-indexed reconstruction of pull request #1. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
