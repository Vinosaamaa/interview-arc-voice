---
schemaVersion: 1
id: capability-dossier-voice-capture-reliability
revision: 1
type: capability-dossier
status: accepted
title: Voice Capture Reliability
repository: interview-arc-voice
capabilityIds: ["voice-capture", "recording-integrity", "delivery-recovery"]
createdAt: 2026-08-12
reconstructed: false
confidence: verified
unknowns: []
modules: ["voice-capture-pipeline", "pending-capture-lifecycle"]
interfaces: ["recording-driver", "transcription-provider", "interview-arc-protocol-v2"]
seams: ["capture-to-transcription", "transcript-to-cursor", "accepted-capture-to-hosted-delivery"]
adapters: ["system-recorder", "audio-engine", "groq", "accessibility-insertion", "renderer-paste-insertion"]
relatedRecords: []
decisions: []
incidents: []
features: []
capabilities: []
amends: []
supersedes: []
learningRefs: []
sources: [{"label":"Voice architecture","url":"https://github.com/Vinosaamaa/interview-arc-voice/blob/main/docs/architecture.md","kind":"documentation"},{"label":"Voice protocol v2","url":"https://github.com/Vinosaamaa/interview-arc-voice/blob/main/docs/protocol-v2.md","kind":"documentation"},{"label":"Voice adoption issue #190","url":"https://github.com/Vinosaamaa/interview-arc-voice/issues/190","kind":"issue"}]
verification: {"state":"not-recorded","evidenceRefs":[]}
visibility: public-safe
publicationEligibility: eligible
issue: 190
pr: null
release: null
run: null
---
# Voice Capture Reliability

Interview Arc Voice preserves one continuous local recording as the evidence boundary while separating foreground transcript insertion from background hosted delivery.

## Capability

Voice begins capture from a previously verified routing snapshot, produces one canonical M4A, and validates finalization, decoded frames, media duration, and encoded payload before transcription. The capture identity does not change when a local backend recovers or hosted context refreshes.

The ordinary speech path performs one provider request. A second request is bounded to a concrete provider or transcript-integrity signal, and all derivatives remain disposable. The original recording stays available when no candidate is trustworthy.

## Module boundary

The capture pipeline owns recording integrity, deterministic vocabulary selection, transcript preservation, insertion completion, and the stable identities required by delivery. Callers do not rewrite transcript text or treat provider duration as proof of lexical coverage.

The pending-capture lifecycle owns durable stage receipts for transcript commit, private audio availability, Delivery Coach work, and settled local retention. Reconciliation resumes only the first incomplete stage and never replays a stage already acknowledged by the server.

## Interfaces and Adapters

Recording and transcription remain behind explicit Interfaces so the system recorder, audio-engine recovery, Groq provider, and optional local diagnostic engine can evolve without changing canonical evidence semantics.

Cursor insertion has two Adapters: a read-back-verified Accessibility write and a guarded transient pasteboard path for renderer-backed editors. Both preserve the exact transcript and leave Send as a user action.

## Privacy and recovery

Credentials remain in macOS Keychain. Linked audio is stored under app-owned private storage and uploaded only after an activity-related decision. General Dictation never writes transcript, audio, or coaching data to Interview Arc.

Diagnostics contain bounded enum and numeric evidence only. They exclude transcript text, prompt text, audio, credentials, private URLs, raw window titles, and filesystem paths.

## Consequences

Foreground insertion can complete while hosted delivery continues quietly. Genuine transient failures use bounded recovery; permanent identity conflicts quarantine the capture. Unresolved evidence is retained rather than silently deleted, and a failed recording or transcription remains playable, saveable, and retryable.

The capability deliberately does not expose a Voice Engineering UI or a Learn action. Voice contributes canonical public-safe evidence to the shared Engineering Journal; the Arc Journal Module owns ingestion, correction history, search, and rendering.

## Interview view

The architectural leverage comes from separating canonical evidence from replaceable Adapters. The recording and exact transcript remain stable while microphone backends, speech providers, editor insertion mechanisms, and hosted delivery stages recover independently.

The critical reliability rule is receipt-driven idempotency: every accepted delivery stage records durable completion, so relaunch and retry can resume without duplicating transcript turns, audio objects, or coaching work.
