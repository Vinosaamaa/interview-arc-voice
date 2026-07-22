# Interview Arc Voice Protocol v1

The native app and the Interview Arc Cloudflare Worker negotiate protocol
version `1`. Requests use the same personal bearer token as the Codex MCP
bridge. The token identifies the owner; client-provided owner IDs are ignored.

## Read focused context

`GET /voice/context`

Returns the focused activity, its stable `activityId`, question metadata used
for vocabulary selection, and the registered long-lived specialist task. A
missing activity or specialist is a normal, user-visible state.

## Persist a captured answer

`POST /voice/captures`

The client supplies a stable `turnId`, activity ID, specialty, exact transcript,
and occurrence time. The server verifies that the activity is still focused,
computes transcript sequence, and inserts the user turn idempotently. The app
inserts the same text into the visible focused editor but does not submit it or
resume the specialist task invisibly.

## Upload private audio

`POST /audio/upload`

Multipart fields are `activityId`, `transcriptTurnId`, `durationSeconds`,
`label`, and `file`. The server verifies ownership, writes the canonical M4A to
private R2, and stores only owner-scoped clip metadata in D1. Playback is always
through the authenticated `/api/audio/:id` route; an R2 object URL is never
public.

## Queue delivery analysis

`POST /voice/delivery`

Creates an attempt-specific delivery-analysis record after the clip exists.
The background Delivery Coach updates it through the MCP
`save_delivery_analysis` tool. Its observations are coaching evidence for the
dated attempt and never modify the reusable Problem Bank solution.

## Idempotency and retries

- `turnId`, clip ID, and analysis ID are stable per capture stage.
- Failed capture persistence, R2 upload, or Delivery Coach work remains in the
  local retry queue. Credentials are not included in retry files.
- Legacy `specialistDelivery` retry records from version 0.2 and earlier are
  discarded without sending so they cannot duplicate a visible user message.
