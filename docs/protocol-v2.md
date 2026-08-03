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
  Voice verifies both an Interview Arc/Codex workspace title and a live
  descendant `codex` executable. Voice reads neither terminal contents nor
  command arguments to make this decision.
- An approved terminal without both signals remains General Dictation. A title
  alone is never sufficient evidence.
- Every other app uses General Dictation and never calls the Interview Arc
  capture, audio, or delivery endpoints.
- A verified Codex target that starts from stale cached context may late-bind
  only after refresh proves the same activity was already running when the
  recording began. A recording from an unsupported target cannot be rebound.
- The visible linked/general state uses the same target decision as capture
  routing. Voice records only the bounded target kind and route-reason enums in
  local diagnostics; it never records a window title, process path, terminal
  content, or command argument.

## Pending capture lifecycle

1. Voice transcribes locally from its protected recording file.
2. Voice creates stable `captureId`, `turnId`, and `clipId` values and a
   SHA-256 transcript checksum.
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
