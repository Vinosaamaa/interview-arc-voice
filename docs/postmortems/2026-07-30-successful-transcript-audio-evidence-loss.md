# Successful transcripts outlived their local audio evidence

## Summary

Interview Arc Voice retained up to 20 Recent Transcript records for 24 hours,
but it deleted a successful General Dictation M4A immediately after provider
transcription. It also deleted accepted linked audio locally after D1, private
R2, and Delivery Coach completed. A visible transcript could therefore outlive
the exact recording needed to investigate provider omissions or corruption.

Issue [#81](https://github.com/Vinosaamaa/interview-arc-voice/issues/81)
exposed the evidence gap. Issue
[#107](https://github.com/Vinosaamaa/interview-arc-voice/issues/107) owns the
repair.

## User impact

- A recent transcript could still be copied or inserted but not replayed.
- Provider text could not be compared with the original recording after a
  successful General Dictation.
- The enhanced silence-protection diagnostic could prove that it omitted no
  provider words while the original M4A was already unavailable.
- On cold launch, Recent Transcripts also appeared empty until unrelated
  Keychain, network, and pending-capture startup work completed.

Private R2 remained authoritative for accepted linked website playback. The
incident concerns missing local recent-history evidence, not public exposure or
confirmed deletion from R2.

## Detection and evidence

The affected diagnostic reported Enhanced protection, zero omitted segments,
zero omitted words, complete provider word timestamps, and an unchanged
provider transcript. Source inspection then showed:

- `GeneralDictationPipeline` deleted the finalized source file immediately
  after transcription;
- `VoicePipeline` deleted accepted linked local audio after delivery;
- `LocalTranscriptRecord` stored no audio identity;
- the app loaded local transcript history only after secure settings and remote
  initialization.

The user's July 30 cold-launch report independently reproduced the empty
history presentation. The permission-0600 transcript-history file still
contained records, confirming a load-order race rather than metadata deletion.

## Root cause

Two earlier privacy decisions were implemented independently:

1. keep Recent Transcript text for bounded manual recovery; and
2. minimize successful local audio retention.

The resulting contracts disagreed about what a “recent transcript” represented.
The UI implied a recoverable recent memo, but the successful pipeline treated
the M4A as disposable. Linked pending protection and Recent History also had no
separate ownership reasons, so the safest implementation was to delete on
delivery instead of transferring ownership.

The launch sequence compounded the confusion by serializing local history
behind credential and network work even though history requires neither.

## Contributing factors

- Transcript metadata had no stable relative audio identity.
- General and linked recordings used different deletion sites.
- There was no explicit `RecentHistory/` lifecycle owner or disk budget.
- UI Play and Save targeted only the newest in-memory audio.
- Relaunch testing emphasized failure recovery rather than successful-history
  playback.

## Resolution

- Introduce private lifecycle-separated `LinkedPending/`, `RecentHistory/`, and
  `Recovery/` ownership.
- Store only a validated relative M4A filename on a transcript record.
- Atomically move a successful General Dictation M4A into Recent History after
  foreground insertion settles.
- Keep one linked M4A in Linked Pending through D1 persistence, private R2
  upload, and Delivery Coach; move it into Recent History only when the
  associated visible transcript remains eligible.
- Preserve unresolved linked audio independently of the recent-20 limit.
- Enforce count, age, explicit-delete, Clear History, and disk-budget pruning on
  history-owned pairs with permissions 0700/0600.
- Load local history before Keychain, network context, reconciliation, and live
  updates; refresh it when the menu opens and at the next known expiry.
- Make Play, Save, and Delete target the exact visible transcript.

## Regression prevention

- Deterministic tests cover General archival, linked ownership transfer,
  unresolved-capture protection beyond 20 items, count/age/disk pruning,
  explicit deletion, Clear History, permissions, and interrupted-move repair.
- The canonical CI build must run the complete Swift test suite.
- Release verification must use the exact signed artifact produced from merged
  `main`, then exercise General Dictation, linked pending/accepted transitions,
  relaunch loading, navigation, Play, Save, Delete, and Clear History.

## Privacy and performance

- No raw audio, transcript, credential, or token is added to Git.
- General Dictation remains local-only and never calls Interview Arc, D1, R2,
  MCP, or Delivery Coach.
- The repair adds no provider call, audio decode, network wait, recurring poll,
  or cron.
- Foreground insertion finishes before same-volume archival and pruning.
- History-only recordings are bounded by newest-20, 24 hours, and a local disk
  budget. Lifecycle-protected linked evidence cannot be evicted by that budget.

## Release verification

Pending completion of the merged-main package and installed-artifact Reliability
check required by issue #107.

## Technical glossary

- **Lifecycle owner:** The feature whose unresolved requirement prevents a
  local file from being deleted.
- **History-only audio:** A completed recording retained solely for bounded
  Recent Transcript playback.
- **Atomic move:** A same-volume rename that changes ownership without copying
  the audio bytes.
- **Stable audio identity:** A validated relative filename rather than an
  persisted absolute path.
