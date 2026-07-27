# Interview Arc Voice Architecture

## Linked practice flow

1. Fetch and cache the focused Interview Arc activity through the authenticated
   API at startup, reconnect, wake, explicit refresh, and revisioned
   owner-scoped server events. WebSocket connection/open is an authoritative
   synchronization boundary: Voice consumes the connection revision, preserves
   the last observed revision across reconnects, and performs one status-first
   snapshot. Visible clocks advance locally. A disconnected client falls back
   at a bounded 15–120-second cadence; it never performs an unconditional
   one-second HTTP loop. A 20-second WebSocket ping detects a half-open
   connection and forces the existing reconnect/fallback path instead of
   leaving the widget on an indefinitely stale workbench. A transient refresh
   failure retains the last verified display context.
2. Resolve a deterministic vocabulary prompt from explicit terms, stored pack
   IDs, metadata triggers, and the specialty base pack.
3. Begin microphone preparation immediately from the fresh cached routing
   snapshot and write into one continuous local M4A file. Preparation is a
   visible state, not a network wait. It ends as soon as the local capture
   backend begins advancing; output-profile identity and speech volume never
   block the live state. A bounded timeout crosses once to the independent
   audio-engine backend only if the primary backend itself does not advance;
   a second timeout fails visibly. The system recorder owns file finalization,
   and a capture is not eligible for transcription until the finalized file
   reopens with decoded frames.
   If the cached snapshot was briefly behind, the active refresh may late-bind
   the capture only when the server proves that activity's stopwatch began
   before recording started. An already linked recording never changes
   activity, and an activity started later never receives an earlier clip.
4. Reopen the finalized file and verify nonzero frames, write success, media
   duration against recording wall time, and a plausible encoded-audio payload
   rate. AAC containers that advance in time while carrying near-silent
   four-byte packets never reach speech-to-text.
5. Produce a speech-optimized transcription derivative and send it with the
   bounded vocabulary prompt to Groq Large v3.
6. Insert the plain transcript plus a Markdown comment envelope containing its
   activity and turn IDs into the captured editor. Voice activates the captured
   application, snapshots the macOS pasteboard, posts a real Command-V through
   the HID event stream, waits for a renderer-backed editor to consume it, and
   restores the original pasteboard only if no other owner changed it. A
   read-back-verified Accessibility write remains the fallback; Voice never
   submits the message.
7. Persist the protected local v2 record, insert its full envelope, and
   register minimal intent identity in a single-flight background task.
   Specialist permission may arrive before registration through a short-lived,
   identity-only deferred decision.
8. After an `activity_related` decision, upload the original recording to
   private R2 and link it to the resulting user transcript turn.
9. Start delivery analysis in a background Codex task.
10. Persist per-answer delivery evidence in D1. On activity completion, the
   specialist includes a combined delivery review in the dated attempt bundle.

R2 upload and delivery analysis continue after visible cursor insertion.
Only genuine transient failures receive local retry scheduling. Waiting for a
specialist or user does not. While unresolved local capture evidence exists,
Voice also performs one single-flight, status-first safety reconciliation at
15, 30, 60, and then 120 seconds. The loop stops as soon as no capture requires
reconciliation, so an idle healthy client produces no recurring intent reads.
This safety path recovers a decision whose best-effort live invalidation was
missed without re-registering known captures. Permanent identity conflicts are
quarantined.

General Dictation does not use activity matching. It sends a bounded,
terms-only prompt made from the highest-priority bundled base vocabulary. This
provides stable spellings such as LeetCode without creating a personal
dictionary, local replacement engine, or additional AI formatting stage.

Background reconciliation never owns the foreground recording, transcription,
insertion, playback, or failure presentation. Its completion may publish a
queued/idle status only when the foreground was idle and remained unchanged
throughout the request. The recorder's active stream is the authoritative
recording signal, so a background status update cannot make a live microphone
capture disappear from the widget.

If the native recorder terminates without an explicit Stop command, Voice
finalizes and retains the available M4A, restores the prior timer disclosure,
and presents an explicit recoverable failure. It never silently returns to idle
or automatically submits a possibly truncated linked answer. The user may
retry transcription, record again, play, or save the preserved audio.

The normal transcription path performs one provider request. Existing response
metadata is checked without another network call. A concrete failure,
incomplete provider result, implausible duration, known prompt leakage, or
missing output triggers exactly one unprompted retry. If the retry is also
suspicious, Voice does not claim success; it retains the original audio and
offers Play, Save, and Retry.

The compact recorder uses a layered material surface. Playback widens it,
exposes a seekable timeline, elapsed/duration text, explicit Stop, and timer
disclosure, and collapses smoothly after playback completes or Stop is chosen.
The recorder capsule remains the bottom anchor while its timer surface,
activity picker, and finish drawer grow upward. The optional dynamic recording
interface snapshots that disclosure, hides it behind one shared recording
capsule, and restores the snapshot immediately on Stop. Hidden clocks continue
to use authoritative timer state. AppKit owns the single bottom-anchored frame
animation; child surfaces fade without a competing move transition, preventing
the capsule from hopping vertically. The visible timer-to-recorder gap remains
10 points outside capture. Saving uses
the native macOS save panel: the user chooses the name and location, the
`.m4a` suffix remains canonical, and a sibling `.txt` transcript is optional.
Recovery actions that change capsule geometry first dismiss and settle their
anchored native popover. AppKit's completed-close notification—not a guessed
animation delay—releases playback and Record again, so they never resize the
anchor during popover teardown.

When the linked timer drawer is expanded and a previous capture exists, the
recorder row replaces its duplicate timer cluster with Play, Insert,
context-aware Copy, Save, and the timer-disclosure control. The expanded timer surface above
remains authoritative. Voice stays
an `LSUIElement` accessory app: it does not occupy the Dock or Command-Tab, and
Settings explicitly raises its existing window.

Background-audio lowering is one recording-scoped session rather than one
device write. Voice records the pre-capture route signature before acquiring
the microphone, treats Bluetooth stereo and hands-free profiles as distinct
routes even when macOS reports the same device UID, and applies the configured
relative level without compounding it. Stop restores adjusted temporary routes
but keeps the durable session pending until the exact pre-capture route returns;
this prevents a late stereo-profile switch from inheriting the ducked level.

The user sends the inserted text through the visible Codex task. The rendered
message shows the answer while the specialist receives the comment envelope and
reuses the already-persisted D1 turn instead of appending a duplicate. Multiple
captures may be sent together; every capture keeps its own turn and envelope.
Voice does not run a hidden specialist-resume command because that would
duplicate the visible message. The background Codex process is reserved for
Delivery Coach analysis; R2 remains the canonical website playback copy.

## General dictation flow

When the link toggle is off, or when current Interview Arc context has no
focused activity and registered specialist, the same recorder takes the
general route:

1. Record into the private temporary directory.
2. Transcribe verbatim through Groq.
3. Activate the app that was active when recording began and insert through the
   guarded paste-event path described above. If paste dispatch is unavailable,
   use direct Accessibility replacement only when the resulting `AXValue`
   exactly matches the expected UTF-16 edit.
4. Delete the temporary audio after a trustworthy result. Preserve it for
   explicit recovery when recording or transcription integrity fails.

This route never calls the Interview Arc capture, audio, delivery-analysis, or
Codex APIs. Server events keep the next routing snapshot current without
delaying microphone start.

## Vocabulary resolution without runtime AI

The resolver is a rule engine, not an intelligent agent.

```text
explicit speech terms
        ↓
explicit pack IDs
        ↓
tag/topic/company/project/title trigger matches
        ↓
specialty base pack
```

Question-bank entries can be enriched once with `vocabularyPackIds` and
`speechTerms`. Unknown custom questions still have a title and specialty; title
phrases are matched against pack triggers, and the base pack is always present.
If a specialist discovers important terminology while preparing an activity,
it may persist explicit speech terms once through Interview Arc. The bridge
then consumes those terms without contacting an LLM during recording.

## Repository boundary

`interview-arc-voice` owns microphone capture, linked local files, temporary
general-dictation files, transcription, Keychain secrets, Delivery Coach CLI
work, global shortcut registration, direct text insertion, and retry state.
Global shortcuts are dispatched by their Carbon hotkey identifier rather than
only by the shared event class. Shortcut capture unregisters both combinations
until it succeeds or is cancelled, then restores both registrations.

`interview-arc` owns identity, the focused activity, task registry, capture
intent metadata, accepted transcript turn IDs, R2 metadata, delivery-analysis
records, structured LeetCode Code Attempts, publication, and playback.

Protocol v2 treats capture acceptance as a permission boundary. Voice retains
exact transcript/audio locally and sends only stable identity plus checksum
until the specialist or user resolves intent. Activity completion and
finalization pause while an intent is unresolved. See `protocol-v2.md`.

Detailed capture recovery belongs to the 260-point menu-bar popover, not the
floating widget. Recent Captures shows waiting, decision, excluded, delivering,
retry, and conflict states; it reconstructs the exact v2 envelope from the
protected local record for Insert Again or the single context-aware Copy
action. The top refresh button refreshes focused activity only.

The client must negotiate an explicit protocol version before mutating server
state. Unknown versions fail closed with a user-visible update prompt.

## Audio model

One stop action produces one canonical clip. Long clips may be divided into
overlapping transcription chunks and processed concurrently. Those derivatives
are deleted after the transcript is assembled. The original recording is
uploaded as one R2 object and remains a single seekable player in Past. At the
current 48-kbps capture rate, a 30-minute answer is far below the 100-MB private
upload boundary.

## Delivery analysis

All three specialties use the same delivery pipeline. Delivery analysis may
describe observable speech evidence such as pace, pauses, fillers, clarity,
organization, vocal variation, and perceived confidence. It must not infer the
speaker's mental state or other sensitive traits.

## Universal insertion reliability

Native AppKit controls, Chromium web editors, and Electron editors expose
different editing behavior. A successful return from
`AXUIElementSetAttributeValue` is not sufficient evidence that a web editor's
DOM or application model changed. Likewise, posting a keyboard event directly
to a Chromium parent PID does not guarantee delivery to its renderer process.
The production path therefore:

1. remembers the last non-Voice foreground application PID;
   transient system surfaces such as Control Center and SystemUIServer are
   excluded from that memory;
2. captures that target at recording start;
3. reactivates the same application before insertion;
4. posts a real paste event at `.cghidEventTap`;
5. holds the transient transcript for 1.5 seconds so asynchronous renderers can
   consume it;
6. restores the previous pasteboard only when `NSPasteboard.changeCount`
   confirms that no other owner has changed it; and
7. uses direct AX replacement only as a verified fallback.

Accessibility messaging to an eligible fallback target has a finite timeout;
manual Insert never remains in a permanent loading state because a system
process captured focus while the menu-bar popover was open.

See
[`postmortems/2026-07-23-universal-dictation-insertion.md`](postmortems/2026-07-23-universal-dictation-insertion.md)
for the evidence, failed approaches, diagrams, and regression plan.
