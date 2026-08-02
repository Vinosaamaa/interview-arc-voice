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

## Timeline

- **2026-07-30:** A provider-omission investigation established that the
  successful General Dictation transcript remained but its finalized M4A had
  already been deleted.
- **2026-07-30:** Issue #107 defined lifecycle-separated local storage, bounded
  retention, and the Reliability verification matrix.
- **2026-07-30:** Regression tests for General archival, linked transfer,
  protected unresolved audio, pruning, permissions, and interrupted moves were
  committed before the production repair.
- **2026-07-30:** A cold-launch report showed Recent Transcripts as empty even
  though the permission-0600 metadata file still contained 20 records. The
  investigation added startup ordering to #107 rather than treating it as
  deletion.
- **2026-07-31:** PR #111 merged as
  `3fc1a27f9534936a487c29619f1bb0abe4b23edf`.
- **2026-07-31:** Merged-main workflow `30600336860` passed the complete test
  and package lane. The exact artifact was downloaded, signature-checked,
  package-checked, installed, and cold-launched.
- **2026-07-31:** Issue #107 was reopened after an early automatic closure so
  the post-merge Reliability evidence could be completed before final
  resolution.

## Resulting architecture

```text
recording starts
      |
      +-- General Dictation --> temporary M4A --> transcript + insertion
      |                                             |
      |                                             v
      |                                      RecentHistory/
      |
      +-- linked capture ----> LinkedPending/ --> D1 + private R2 + coach
                                                    |
                                    completed + still recent?
                                      |                     |
                                      v                     v
                               RecentHistory/          local delete

TranscriptHistory/transcript-history.json
      |
      +-- relative audio identity --> exact visible M4A
      +-- newest 20 / 24 hours / disk budget
      +-- cannot evict LinkedPending lifecycle evidence
```

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

## Failed or insufficient approaches

- Keeping transcript-only history was privacy-bounded but did not preserve the
  evidence required to diagnose provider omissions.
- Copying a second M4A into history would have created ambiguous ownership and
  doubled storage. The repair transfers one canonical file between lifecycle
  owners instead.
- Treating all local audio as one queue would allow the 20-item history limit
  to delete an unresolved linked capture. `LinkedPending/` and
  `RecentHistory/` therefore have independent deletion rules.
- Loading history after secure settings eventually populated the UI but left a
  false empty state whenever Keychain or network initialization was slow.
  Local history now loads first and refreshes again whenever the menu opens.

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

- PR [#111](https://github.com/Vinosaamaa/interview-arc-voice/pull/111)
  merged as `3fc1a27f9534936a487c29619f1bb0abe4b23edf`.
- Merged-main workflow
  [30600336860](https://github.com/Vinosaamaa/interview-arc-voice/actions/runs/30600336860)
  passed 156 Swift Testing tests, 13 XCTest tests, packaging, and the embedded
  21-vocabulary-pack verification.
- The downloaded artifact passed strict deep code-signature verification. Its
  executable SHA-256 was
  `8f1df29a0e4cde256160e59ce8a59a0dc5d01c36d1803617bf9ce204aac33a0c`.
  The installed executable produced the same hash and passed the same package
  self-check.
- The exact merged-main app was staged, installed at
  `~/Applications/Interview Arc Voice.app`, and cold-launched with the
  persistent Mini preference. Its recording control was available immediately.
- The installed cold launch preserved all 20 existing transcript records,
  retained permission `0600` on transcript metadata, and created private
  `RecentHistory/` with permission `0700`. Source and installed-state evidence
  confirmed that this local load occurs before Keychain, network context,
  pending reconciliation, and live updates.
- The merged-main deterministic suite exercised successful General archival,
  accepted linked transfer, 30 unresolved linked files, count/age/disk/delete
  and Clear History pruning, lifecycle protection, permissions, and
  interrupted-move repair. No synthetic capture was uploaded to the user's
  production D1 or R2 during release verification.

## Follow-up

- Existing transcript records created before this release intentionally remain
  transcript-only; the repair does not guess which older M4A belongs to which
  transcript.
- Normal use of the first post-release General and linked recordings provides
  final user-facing acceptance of the new Play and Save controls. A recurrence
  should reopen #107 with the affected transcript and release evidence.
- The later #64/#93 durability repair keeps accepted linked audio locally until
  the server acknowledges D1 status `available`, which is written only after
  the private R2 put succeeds. Local cleanup therefore cannot win the upload
  boundary merely because transcript delivery completed.
- If the local source is irrecoverably missing or unreadable before that
  acknowledgement, Voice reports `audio_lost` with a privacy-safe reason. The
  server rejects that report when the clip is already `available`; otherwise
  Finish blocks until the user acknowledges the loss and publication renders
  **Recording unavailable** without a player or fabricated coaching evidence.

## Technical glossary

- **Lifecycle owner:** The feature whose unresolved requirement prevents a
  local file from being deleted.
- **History-only audio:** A completed recording retained solely for bounded
  Recent Transcript playback.
- **Atomic move:** A same-volume rename that changes ownership without copying
  the audio bytes.
- **Stable audio identity:** A validated relative filename rather than an
  persisted absolute path.
