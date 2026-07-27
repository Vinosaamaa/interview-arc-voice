# Live synchronization polling and capture retry storm

## Summary

Website, Picture-in-Picture, Companion, and Voice independently treated a
one-second display tick as a network synchronization tick. Voice also treated
every protected pending-capture file as immediately retryable work and
re-registered it before reading server status. Retained immutable-identity
conflicts therefore became a permanent hot loop that consumed shared Worker
CPU and requests.

The Voice v2 permission boundary still held: the diagnosed unrelated capture
created no activity transcript turn and no private R2 object.

Coordinator: [interview-arc#89](https://github.com/Vinosaamaa/interview-arc/issues/89)  
Native client: [interview-arc-voice#64](https://github.com/Vinosaamaa/interview-arc-voice/issues/64)

## Root cause

- Context refresh also scheduled capture reconciliation.
- A local JSON file represented both protected evidence and retry eligibility.
- Reconciliation wrote registration before it read server status.
- Permanent 409 identity conflicts had no terminal local state.
- Foreground insertion waited for metadata registration.
- No shared owner-scoped invalidation channel existed.

## Repair

- Replace Voice's one-second HTTP loop with owner-scoped WebSocket
  invalidations and 15–120-second disconnected fallback.
- Keep visible clocks local and D1/REST authoritative.
- Insert the transcript and full v2 envelope immediately after the
  permission-`0600` record is saved; register identity in a single-flight
  background task.
- Query cursor-paginated owner status before registering only missing IDs.
- Distinguish waiting, needs-decision, excluded, delivering, transient retry,
  quarantined conflict, and complete states.
- Give only genuine transient work a `nextAttemptAt`.
- Expire pending, uncertain, and unrelated local evidence after 24 hours.
- Put detailed recovery in Recent Captures in the menu-bar popover; keep the
  floating recorder focused on ordinary recording controls.
- Restore menu-bar accessory behavior and keep Settings explicitly raisable.

## Prevention

- Server/client reliability changes must pass the simultaneous production
  matrix in the coordinator issue.
- No client may equate a one-second display clock with a network request.
- Waiting for a specialist or user must never be counted as a retry.
- Permanent conflicts require an explicit terminal/quarantine state.
- The server contract deploys before the dependent signed Voice artifact.
- Merge alone does not resolve either issue; record deployed Worker versions,
  the exact installed Voice build, Companion reload, and request/CPU evidence.

## Native follow-up: capture action completion

The first installed reliability build exposed a separate foreground-state
defect in the new Recent Captures recovery surface. `Insert Again` awaited the
bounded text injector correctly, but its caller did not leave the global
`inserting` phase when that await returned. The operation could therefore
finish while the Voice interface continued to present an indefinite spinner.

The follow-up repair gives every manual insertion attempt an explicit terminal
outcome, uses one context-aware Copy action that preserves the exact v2
envelope, and keeps a timer-disclosure control available when previous-memo
actions replace the compact clocks. Regression coverage now treats successful
and unsuccessful manual insertions as terminal states rather than relying on
incidental phase changes elsewhere in the recording pipeline.
