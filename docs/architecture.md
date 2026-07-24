# Interview Arc Voice Architecture

## Linked practice flow

1. Refresh and cache the focused Interview Arc activity through the
   authenticated API while idle.
2. Resolve a deterministic vocabulary prompt from explicit terms, stored pack
   IDs, metadata triggers, and the specialty base pack.
3. Open the microphone immediately from the cached routing snapshot and record
   one user answer as a continuous local M4A file. The system recorder owns
   file finalization; a capture is not eligible for transcription until the
   finalized file reopens with decoded frames.
4. Reopen the finalized file and verify nonzero frames, write success, and
   media duration against recording wall time.
5. Produce a speech-optimized transcription derivative and send it with the
   bounded vocabulary prompt to Groq Large v3.
6. Insert the plain transcript plus a Markdown comment envelope containing its
   activity and turn IDs into the captured editor. Voice activates the captured
   application, snapshots the macOS pasteboard, posts a real Command-V through
   the HID event stream, waits for a renderer-backed editor to consume it, and
   restores the original pasteboard only if no other owner changed it. A
   read-back-verified Accessibility write remains the fallback; Voice never
   submits the message.
7. Upload the original recording to private R2 and link it to the resulting
   user transcript turn.
8. Start delivery analysis in a background Codex task.
9. Persist per-answer delivery evidence in D1. On activity completion, the
   specialist includes a combined delivery review in the dated attempt bundle.

R2 upload and delivery analysis continue after visible cursor insertion.
Failures enter a local retry queue.

The normal transcription path performs one provider request. Existing response
metadata is checked without another network call. A concrete failure,
incomplete provider result, implausible duration, known prompt leakage, or
missing output triggers exactly one unprompted retry. If the retry is also
suspicious, Voice does not claim success; it retains the original audio and
offers Play, Save, and Retry.

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
Codex APIs. Automatic one-second context refresh keeps the next capture's
routing snapshot current without delaying microphone start.

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

`interview-arc` owns identity, the focused activity, task registry, transcript
turn IDs, R2 metadata, delivery-analysis records, publication, and playback.

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
2. captures that target at recording start;
3. reactivates the same application before insertion;
4. posts a real paste event at `.cghidEventTap`;
5. holds the transient transcript for 1.5 seconds so asynchronous renderers can
   consume it;
6. restores the previous pasteboard only when `NSPasteboard.changeCount`
   confirms that no other owner has changed it; and
7. uses direct AX replacement only as a verified fallback.

See
[`postmortems/2026-07-23-universal-dictation-insertion.md`](postmortems/2026-07-23-universal-dictation-insertion.md)
for the evidence, failed approaches, diagrams, and regression plan.
