# Interview Arc Voice Protocol v1

The native app and the Interview Arc Cloudflare Worker negotiate protocol
version `1`. Requests use the same personal bearer token as the Codex MCP
bridge. The token identifies the owner; client-provided owner IDs are ignored.

## Read focused context

`GET /voice/context`

Returns the focused activity, its stable `activityId`, question metadata used
for vocabulary selection, its activity-timer `startedAt` and `runningSince`
timestamps, and the registered long-lived specialist task. A missing activity
or specialist is a normal, user-visible state. The timestamps allow the native
client to repair a briefly stale cache without ever attaching a recording to
an activity that began later.

The response also includes a lightweight `timerInstrument` snapshot. It keeps
the focused session, paused last-focused activity, remaining session
activities, timer revisions, and the server clock needed by the floating
instrument. D1 records state transitions only. The app advances visible clocks
locally between snapshots instead of writing once per second.

The instrument distinguishes ordinary practice from Career Focus:

- practice activities have `activityClass: "practice"` and
  `requiresOutcome: true`;
- Job applications have `activityClass: "focus_block"` and
  `requiresOutcome: false`.

Career Focus may be standalone or share a session countdown, but it is never
shown in the LeetCode Companion.

## Control the timer instrument

`POST /voice/timers`

The native widget may start, resume, pause, or finish the current session and
may start, resume, or pause one of that session's activities. Starting an
activity resumes its parent session and pauses any competing activity through
the same D1 transition rules as the website and Chrome companion.

An activity cannot use the generic `finish` mutation. Clicking Finish in the
widget opens an inline drawer; the client then sends one `finish-activity`
mutation containing the explicit result and current star choice. The server
stores that choice, finishes the timer, and schedules or clears review state.
The normal timer rows and next-activity picker never expose result or star
controls. A Career Focus activity is the exception: it uses the generic finish
mutation and requires no result. If finishing a session finds started practice
activities without results, Voice directs the user to one resolver in the
menu-bar popover; the floating capsule does not grow into a multi-activity
form.

## Persist a captured answer

`POST /voice/captures`

The client supplies a stable `turnId`, activity ID, specialty, exact transcript,
and occurrence time. The server verifies that the activity is still focused,
computes transcript sequence, and inserts the user turn idempotently. The app
inserts the same text into the visible focused editor followed by a Markdown
comment envelope containing the activity and turn IDs. It does not submit the
message or resume the specialist task invisibly. The specialist treats every
enveloped user turn as Voice-managed and must not append it to D1 again.

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
