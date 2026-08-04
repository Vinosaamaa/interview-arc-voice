# Postmortem: Voice response-group delivery retry conflict

**Date:** 2026-08-04  
**Status:** In review  
**Severity:** Reliability / user-work blocked  
**Tracking:** `interview-arc-voice#64`, paired with `interview-arc#157`

## Summary and impact

A reserved three-capture response group never completed its canonical D1
exchange. Voice retained the recordings but retried delivery more than fifty
times. Activity Finish correctly stayed blocked. Recovery then exposed a
server comparison defect that quarantined the stored group after a caller
supplied a non-exact replay. Six exact captures across two corrupted groups
were permanently removed only after explicit user authorization, and the
affected activity was then closed as solved with help.

No transcript or audio was silently published. Exact identifiers, content,
credentials, and owner information are excluded from this public-safe record.

## Root cause

The native delivery reconciliation path used one broad catch. Although the API
client decoded the HTTP status, stable server code, and `retryable`, the catch
discarded them, stored `transient_delivery_failure`, incremented one counter,
and always scheduled another attempt. Exponential delay was capped at one hour
but attempt count and elapsed retry time were unbounded. Delivery also lacked
persisted transcript/audio/coach stage receipts, so every trigger re-entered a
monolithic completion operation.

The paired server path separately treated a caller mismatch as proof that
stored evidence was corrupt. Count-only Finish errors and missing blocker/
repair tools made the situation difficult to diagnose safely.

## Contributing conditions

- Permanent 409 and transient 503 paths were not exercised through the same
  delivery catch.
- Wake, relaunch, live invalidation, safety reconciliation, and manual refresh
  could all re-enter the retry path.
- Manual Retry and background retry used the same entry point.
- UI copy said “retry scheduled” even when no future retry could succeed.

## Repair

- Persist transcript, audio, and coach stage receipts with stable identities.
- Catch `InterviewArcAPIError` first and preserve code/status/message/
  retryability across relaunch.
- Quarantine permanent identity/group/deletion/authorization conflicts after
  one failed attempt.
- Use a bounded 15s/30s/60s/2m/5m/15m/1h schedule with eight attempts and a
  six-hour stage window.
- Move exhausted transient work to `needs_attention`; manual Retry runs once.
- Keep detailed recovery in the menu-bar popover with a copyable redacted
  diagnostic; do not add recovery complexity to the floating widget.
- Depend on the paired server's immutable receipt, non-destructive conflict,
  exact blocker read, audited repair, and quarantined deletion support.

## Verification still required

- CI/type-check tests for transient 503 twice then success, permanent 409,
  relaunch at every stage, exhaustion, and one-shot manual retry.
- Worker-first deployment and MCP reconnect before native rollout.
- Exact signed merged-main artifact verification with disposable fixed-ID
  three-member groups and simultaneous Companion traffic.
- Confirm no existing local record is deleted or reclassified during migration.

## Rollback

Roll back the native artifact while preserving migrated local JSON and original
M4A files. Never clear the pending store as rollback. The backward-compatible
server receipt and non-destructive conflict behavior remain deployed.
