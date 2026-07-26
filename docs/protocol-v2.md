# Interview Arc Voice Protocol v2

Protocol v2 separates visible dictation from durable practice evidence. The
native app inserts the exact transcript into Codex immediately, but it does not
send transcript text or audio to Interview Arc until the same specialist turn
classifies the capture.

## Destination boundary

- The recording-start destination is resolved locally.
- `com.openai.codex` plus a fresh focused activity enters the linked flow.
- Every other app uses general dictation and never calls the Interview Arc
  capture, audio, or delivery endpoints.
- A recording that started outside Codex cannot be rebound to an activity by a
  later focus refresh.

## Pending capture lifecycle

1. Voice transcribes locally from its protected recording file.
2. Voice creates stable `captureId`, `turnId`, and `clipId` values and a
   SHA-256 transcript checksum.
3. `POST /voice/intents` stores only owner-scoped identity, activity,
   specialty, occurrence time, status, and checksum.
4. Voice writes a permission-`0600` pending JSON record and retains the M4A
   locally.
5. Voice inserts the exact transcript and the `interview-arc-voice:v2`
   envelope into the focused Codex editor.
6. The specialist calls `resolve_voice_capture` with `activity_related`,
   `unrelated`, or `uncertain`.
7. Voice polls `GET /voice/intents`. Only `activity_related` captures may call
   `POST /voice/captures` and `/audio/upload`.

`uncertain` captures remain visible in Voice with Attach and Delete actions and
never expire automatically. `unrelated` content remains recoverable locally
for 24 hours, is hidden immediately, and is then deleted without upload.
Accepted local audio is removed only after the exact transcript, private R2
object, and delivery-coaching request have all completed successfully.

## Completion and deletion

Activity finish and specialist finalization reject unresolved `pending`,
`activity_related`, `uncertain`, or `deleting` captures. An accepted transcript
can be used while the idempotent R2/delivery work continues.

`DELETE /voice/captures/:captureId` marks the graph deleting, removes delivery
analysis, private R2 audio, clip metadata, and the transcript turn, then leaves
an owner-scoped tombstone. Repeating the request retries the same deletion.

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
