# Interview Arc Voice Architecture

## Linked practice flow

1. Read the focused Interview Arc activity through the authenticated API.
2. Resolve a deterministic vocabulary prompt from explicit terms, stored pack
   IDs, metadata triggers, and the specialty base pack.
3. Record one user answer as a continuous local M4A file.
4. Produce a speech-optimized transcription derivative.
5. Send the derivative and vocabulary prompt to Groq Large v3.
6. Insert the plain transcript into the focused editor through macOS
   Accessibility without using the clipboard; do not submit it.
7. Upload the original recording to private R2 and link it to the resulting
   user transcript turn.
8. Start delivery analysis in a background Codex task.
9. Persist per-answer delivery evidence in D1. On activity completion, the
   specialist includes a combined delivery review in the dated attempt bundle.

R2 upload and delivery analysis continue after visible cursor insertion.
Failures enter a local retry queue.

The user sends the inserted text through the visible Codex task. Voice does not
run a hidden specialist-resume command because that would duplicate the visible
message. The background Codex process is reserved for Delivery Coach analysis;
R2 remains the canonical website playback copy.

## General dictation flow

When the link toggle is off, or when current Interview Arc context has no
focused activity and registered specialist, the same recorder takes the
general route:

1. Record into the private temporary directory.
2. Transcribe verbatim through Groq.
3. Insert into the app that was active when recording began through the focused
   Accessibility text element, with Unicode keyboard events as a direct fallback.
4. Delete the temporary audio on success or failure.

This route never calls the Interview Arc capture, audio, delivery-analysis, or
Codex APIs. Automatic context refresh happens again before every recording, so
the route is based on the current activity rather than stale launch-time state.

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
