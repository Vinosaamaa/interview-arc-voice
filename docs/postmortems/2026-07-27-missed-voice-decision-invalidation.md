# Missed Voice Decision Invalidation

## Summary

On July 26, 2026, a protocol-v2 capture remained protected locally as
`waiting_for_specialist` after its authoritative server intent had already
become `activity_related`. Activity completion correctly remained blocked
because durable transcript, private audio, and coaching delivery had not
finished.

This was an eventual-consistency failure in the native client, not a failure of
the finish guard or the specialist decision.

Tracking issue:
[interview-arc-voice#72](https://github.com/Vinosaamaa/interview-arc-voice/issues/72)

## Impact

- One accepted answer could not complete its durable delivery.
- The associated activity continued returning the unresolved-capture finish
  guard.
- The original transcript and audio remained intact in the protected local
  store.
- No duplicate transcript turn or R2 object was created during diagnosis.

No transcript, audio, token, capture identity, or owner identity is included in
this document.

## Timeline

- A linked capture was transcribed, inserted, protected locally, and registered.
- The specialist resolved the exact intent as `activity_related`.
- The corresponding best-effort live invalidation was not observed by the
  installed client.
- More than 24 minutes later, the server remained `activity_related` while the
  local record remained `waiting_for_specialist` with no scheduled retry.
- Diagnosis confirmed that a healthy WebSocket had no eventual-consistency
  path after one missed event.

## Root cause

Two client liveness gaps combined:

1. The WebSocket decoder attempted to decode every frame as
   `practice_changed`. The server's `connected` frame has only `type` and
   `revision`, so it was discarded and socket open was not treated as a
   synchronization boundary.
2. The app only ran bounded snapshot fallback after WebSocket disconnection.
   While a socket remained healthy, a retained waiting capture had no
   independent future status read.

The startup retry path also required an already-created pipeline. When the
pipeline had not yet been constructed, that recovery call returned without
loading protected pending captures.

## Resolution

- Decode live frames into explicit `connected` and `practice_changed` signals.
- Preserve the latest owner revision across reconnects.
- Run one status-first capture reconciliation on every connection/open signal.
- Lazily construct the linked pipeline before background reconciliation.
- While relevant protected local captures exist, run a single-flight safety
  reconciliation after 15, 30, 60, and then 120 seconds.
- Stop the safety task when only settled, excluded, or quarantined captures
  remain.
- Continue using the existing paginated owner-status read before registration
  or delivery. Known capture identities are not registered again.

## Why this remains low traffic

The safety task is capture-scoped, not an application heartbeat. With no local
capture awaiting reconciliation, it does not run and produces no recurring
intent-status requests. Waiting is still a lifecycle state rather than a retry
failure, so it does not inflate retry counts.

## Regression prevention

Coverage now verifies:

- a connection frame triggers an authoritative synchronization signal;
- stale or duplicate practice revisions remain ignored;
- an unresolved waiting capture receives bounded safety scheduling;
- interrupted accepted delivery remains recoverable after relaunch; and
- settled captures create no recurring reconciliation schedule.

Canonical macOS CI runs the complete Swift test suite and packages the release
artifact. Reliability completion additionally requires testing the exact
merged-main artifact and the installed app against the deployed Worker.

## Follow-up

The shared cross-client production matrix remains tracked in
`interview-arc-voice#64` and `interview-arc#89`; resolving this incident does
not close either coordinator issue.
