---
schemaVersion: 1
id: change-note-learning-voice-transcript-only
revision: 1
type: change-note
status: accepted
title: Learning Voice Uses Transcript-Only Evidence
repository: interview-arc-voice
capabilityIds: ["voice-capture","learning-transcript"]
createdAt: 2026-08-12
reconstructed: false
confidence: verified
unknowns: []
modules: ["voice-capture-pipeline","learning-transcript-recovery"]
interfaces: ["voice-context","voice-learning-transcripts"]
seams: ["focused-context-to-capture-policy","transcript-to-cursor","learning-transcript-to-acknowledgement"]
adapters: ["system-recorder","groq","accessibility-insertion","interview-arc-worker"]
relatedRecords: ["capability-dossier-voice-capture-reliability@1"]
decisions: []
incidents: []
features: ["learn-workspace"]
capabilities: ["transcript-only-learning-voice"]
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Learn Voice issue #189","url":"https://github.com/Vinosaamaa/interview-arc-voice/issues/189","kind":"issue"},{"label":"Learn workspace contract","url":"https://github.com/Vinosaamaa/interview-arc/blob/main/docs/contracts/learning-workspace.md","kind":"documentation"},{"label":"Pull request #193","url":"https://github.com/Vinosaamaa/interview-arc-voice/pull/193","kind":"pull-request"}]
verification: {"state":"verified","evidenceRefs":["issue:189","pull-request:193","documentation:learning-workspace"]}
visibility: public-safe
publicationEligibility: eligible
issue: 189
pr: 193
release: null
run: null
---
# Learning Voice Uses Transcript-Only Evidence

Learning capture reuses the established recording, transcription, integrity, and cursor-insertion path, then diverges at one explicit evidence-policy seam. Authoritative `/voice/context` data must identify exactly one running Learning Session with its pinned Course, Lesson, transcript revision, next sequence, and `transcript_only` policy. Ambiguous or inconsistent context falls back without guessing.

## Persistence and recovery

The native app creates one lowercase stable operation ID and turn ID after transcription, stores their exact transcript checksum and Learning revision snapshot under private local ownership, and inserts only the verbatim transcript into the visible Learning Specialist task. It never emits the Interview capture envelope.

The original audio remains local through insertion and `POST /voice/learning-transcripts` acknowledgement. A matching acknowledgement removes the pending record and transient audio. Insertion, transport, or acknowledgement failure retains one recoverable original; relaunch retries only the first incomplete stage with the same operation, turn, revision, sequence, transcript, and checksum. Changed local identities fail closed.

## Privacy boundary

Learning capture never registers Interview capture intent, uploads to R2, registers private-audio metadata, queues Delivery Coach, reports audio loss, or creates an Interview Finish blocker. Interview practice retains its permission-gated hosted delivery, and General Dictation remains local. Diagnostics continue to contain aggregate timing and enum data only.
