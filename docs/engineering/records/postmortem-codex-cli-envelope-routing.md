---
schemaVersion: 1
id: postmortem-codex-cli-envelope-routing
revision: 1
type: postmortem
status: closed
title: Restore Voice v2 envelopes in verified Codex CLI terminals
repository: interview-arc-voice
capabilityIds: ["voice-postmortem-codex-cli-envelope-routing"]
createdAt: 2026-08-03
reconstructed: true
confidence: high
unknowns: ["Attachment bodies and workflow logs were not quoted."]
modules: ["Sources:InterviewArcVoice","Sources:InterviewArcVoiceCore"]
interfaces: ["Tests/InterviewArcVoiceCoreTests/LiveContextPolicyTests.swift","docs/protocol-v2.md"]
seams: ["SwiftUI/macOS shell ↔ Voice core","Voice capture ↔ foreground editor"]
adapters: ["Sources/InterviewArcVoice/CaptureTargetInspector.swift","Sources/InterviewArcVoice/InterviewArcVoiceApp.swift","Sources/InterviewArcVoiceCore/CaptureRouting.swift","Sources/InterviewArcVoiceCore/VoiceDiagnostics.swift","Tests/InterviewArcVoiceCoreTests/LiveContextPolicyTests.swift","Tests/InterviewArcVoiceCoreTests/VoiceDiagnosticsTests.swift"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: ["voice-postmortem-codex-cli-envelope-routing"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Pull request #156","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/156","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["pull-request:156","head-commit:95414fb8f39f5ce5d256584a8aa9a2fdbd7a9fcb","merge-commit:b172a5b21f577edb293329e134280de976eb845e"]}
visibility: public-safe
publicationEligibility: eligible
issue: 60
pr: 156
release: null
run: null
---
# Restore Voice v2 envelopes in verified Codex CLI terminals

Evidence-indexed reconstruction of pull request #156. This record preserves the reviewed public-safe module, interface, seam, and adapter inventory from that change. It does not reconstruct unavailable motivation, success, attachment bodies, workflow logs, or deployment receipts.

## Historical limits

Dependent receipts link this exact revision. Unrecorded impact remains unknown.
