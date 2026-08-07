# Interview Arc Voice Protocol v2

Protocol v2 separates visible dictation from durable practice evidence. The
native app inserts the exact transcript into Codex immediately, but it does not
send transcript text or audio to Interview Arc until the same specialist turn
classifies the capture.

## Destination boundary

- The recording-start destination is resolved locally.
- The desktop Codex application plus a fresh focused activity enters the
  linked flow.
- Codex CLI may enter the same flow only inside an approved terminal host when
  Link is enabled, the focused activity context is fresh, and Voice verifies an
  Interview Arc/Codex top-level window title. Process ancestry is not required
  because tmux detaches pane processes from the terminal GUI. Voice reads
  neither terminal contents nor command arguments to make this decision.
- An approved terminal without the workspace-title signal remains General
  Dictation.
- Apple Terminal additionally requires Accessibility evidence from its actual
  focused window; a visible-window fallback is insufficient for linked routing.
- Every other app uses General Dictation and never calls the Interview Arc
  capture, audio, or delivery endpoints.
- A verified Codex target that starts from stale cached context may late-bind
  only after refresh proves the same activity was already running when the
  recording began. A recording from an unsupported target cannot be rebound.
- The visible linked/general state uses the same target decision as capture
  routing. Voice persists only the bounded target kind, decision, and
  route-reason enums in local diagnostics. Host bundle identifiers and
  top-level window titles are evaluated transiently and are never persisted.
  Diagnostics also exclude process arguments, terminal content, transcript
  text, and credentials.

## Pending capture lifecycle

1. Voice transcribes locally from its protected recording file.
2. Voice removes boundary whitespace once, then creates stable `captureId`,
   `turnId`, and `clipId` values and a SHA-256 checksum from that exact
   canonical transcript. The same text is inserted, retained locally,
   registered, and delivered. A pre-network guard rejects any divergent local
   transcript/checksum pair.
3. Voice writes a permission-`0600` pending JSON record and retains the M4A
   locally.
4. Voice inserts the exact transcript and the `interview-arc-voice:v2`
   envelope into the focused Codex editor.
5. In a single-flight background task, `POST /voice/intents` stores only
   owner-scoped identity, activity, specialty, occurrence time, status, and
   checksum. Registration never blocks cursor insertion.
6. The specialist calls `resolve_voice_capture` with `activity_related`,
   `unrelated`, or `uncertain`.
7. Voice receives an owner-scoped revision event and queries the paginated
   status endpoint. Only `activity_related` captures may call
   `POST /voice/captures` and `/audio/upload`. A disconnected client uses
   bounded 15–120-second snapshot fallback, never a one-second loop.

WebSocket open/reopen also carries an owner revision and triggers exactly one
status-first reconciliation. Because revision events are best-effort, an
in-memory safety loop runs only while a protected local record is waiting,
needs a decision, or is completing accepted delivery. It reconciles at 15, 30,
60, and then 120 seconds, reads the paginated owner status before any mutation,
and stops when no such local record remains. A waiting state does not increment
retry counters, and known capture identities are never registered again.

If a specialist decision arrives before registration, the Worker stores a
24-hour identity-only deferred decision. Registration atomically validates the
activity and turn identity before merging it. A mismatch is a structured,
non-retryable `voice_capture_identity_conflict`.

`pending`, `uncertain`, and `unrelated` content remains recoverable locally for
at most 24 hours and is then deleted without upload. Permanent identity
conflicts enter a quarantined local state and are never retried automatically.
Accepted local audio is removed only after the exact transcript, private R2
object, and delivery-coaching request have all completed successfully.

The local lifecycle distinguishes:

- inserted / registration pending;
- waiting for specialist;
- needs decision;
- excluded grace period;
- related / delivering;
- quarantined conflict;
- complete.

Only genuine transient operations have `nextAttemptAt` and a retry count.
Waiting for a specialist or user is not retry work.

Accepted delivery is persisted by stage: transcript pending/committed, audio
pending/available or loss awaiting acknowledgement, coach pending/queued/
complete/failed, then complete. Relaunch resumes only the first incomplete
stage and reuses the stable capture, turn, clip, analysis, and response-group
receipt when present. Acknowledged stages are never intentionally replayed.

Delivery preserves `InterviewArcAPIError.code`, HTTP status, safe message, and
`retryable`. A non-retryable error or an identity, group, deletion,
authorization, activity, turn, or checksum conflict enters
`quarantined_conflict` immediately and clears scheduled retry. Genuine
transient delivery uses 15 seconds, 30 seconds, 60 seconds, 2 minutes, 5
minutes, 15 minutes, then at most 1 hour. Eight consecutive automatic attempts
or a six-hour stage window opens `needs_attention` and stops automatic network
work. Manual Retry performs one attempt and never restarts an unbounded loop.
Live events, wake, relaunch, and manual refresh are invalidation signals; they
must not reset a terminal state or stage retry budget.

Before retrying accepted content, Voice reads the activity's authoritative
delivery blockers once and records the canonical response-group identity and
digest. A member already reported as `received`, or already present as its
canonical user turn, advances local transcript state without retransmitting
content. A provisional group therefore delivers only missing members. A
quarantined group stops and exposes server repair; deleting/deleted cancels
local delivery under retention policy. The menu-bar recovery surface reports
the exact stage and retry state, while the floating widget remains
uncomplicated.

## Completion and deletion

Activity finish and specialist finalization reject unresolved `pending`,
`activity_related`, `uncertain`, or `deleting` captures. An accepted transcript
can be used while the idempotent R2/delivery work continues.

`DELETE /voice/captures/:captureId` marks the graph deleting, removes delivery
analysis, private R2 audio, clip metadata, and the transcript turn, then leaves
an owner-scoped tombstone. Upload revalidates accepted state after the R2 write;
if deletion won the race, the late object is removed before the request
returns. Repeating deletion retries the same fenced cleanup.

## Specialist receipts

For unrelated Voice turns the specialist returns exactly:

`*Not attached to this practice activity · Transcript not saved · Recording not uploaded*`

For unrelated typed administration the specialist returns exactly:

`*Not attached to this practice activity · Not saved to the practice transcript or publication*`

Receipts are UI feedback and are excluded from D1 transcripts and publication.

## Legacy

Protocol-v1 capture retries are accepted as legacy evidence so existing local
queues are not stranded. They are reviewable as legacy records and are never
mass-deleted automatically. `GET /voice/intents` returns likely legacy orphans
separately; Voice shows a small review list, and
`DELETE /voice/legacy-orphans/:clipId` runs the same owner-scoped R2/D1
deletion graph after an explicit user action.
