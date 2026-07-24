# Linked Dictation Integrity and Capture-Latency Incident

- **Status:** Repair in verification
- **Detected:** July 24, 2026 (Pacific time)
- **Affected product:** Interview Arc Voice for macOS
- **Impact:** Critical transcript truncation/contamination; moderate capture latency
- **Data exposure:** None

## Summary

After the first long-dictation repair, linked Interview Arc recordings could
still truncate a long answer or append unrelated phrases. Starting capture
also regressed from immediate response to a visible one-to-three-second delay,
and the floating recorder sometimes continued to show processing after text
was already present in the editor.

The failures crossed three independent boundaries:

1. Record waited for an authenticated context request before opening the
   microphone.
2. The real-time audio tap ignored M4A write errors, so a partial file could
   proceed to transcription without evidence that capture was complete.
3. Linked speech still used vocabulary prompt context and had no integrity
   gate or selective unprompted retry for contaminated provider output.

The completion lag had a fourth cause: the pasteboard safety path deliberately
held the method open for 1.5 seconds after dispatching Command-V, even though
the editor had already received the text.

## User impact

- The beginning of an answer could be lost while Record waited on the network.
- A long answer could end early or contain speech the user never said.
- A write interruption could be mistaken for a successful capture.
- The recorder appeared busy after the visible insertion was complete.
- A generic sticky “Needs attention” state did not clearly distinguish link,
  capture, transcription, insertion, and background-delivery failures.

## Evidence and root cause

The capture action called `refreshContext(showProgress: true)` before
`AnswerRecorder.start`. That made network latency part of microphone latency.
The AVAudioEngine tap used `try? file.write`, explicitly discarding the only
signal that a real-time write had failed. Linked transcription sent the
activity vocabulary prompt directly to Whisper but did not compare duration,
chunk completeness, output shape, or prompt leakage before insertion. Finally,
the insertion method waited synchronously for pasteboard restoration.

The user-provided paired transcripts demonstrated that the same spoken answer
was complete in ChatGPT while the linked Voice output ended early and added
unrelated phrases. Because the original M4A, provider response, and assembled
result were not retained as separate diagnostic boundaries, the prior build
could not prove which stage introduced every phrase. That observability gap is
itself a contributing cause.

## Resolution

- Refresh activity context every second while idle and use the cached snapshot
  at Record time.
- Start the microphone without awaiting Interview Arc.
- Record audio-write errors and written frame counts.
- Reopen every finalized M4A and compare decoded duration, frames, file size,
  and write status before speech-to-text.
- Inspect the existing provider result for empty output, missing chunks,
  duration mismatch, implausibly short text, known hallucination boilerplate,
  and prompt leakage.
- Make no extra request for a healthy result. Retry exactly once without a
  prompt only when the first result is concretely suspicious.
- Preserve the original and expose Play, Save, and Retry if integrity remains
  uncertain.
- Complete the foreground UI as soon as editor insertion succeeds; R2 and
  delivery coaching continue separately.
- Restore the user's pasteboard asynchronously instead of blocking visible
  completion.
- Add explicit link-state color/symbol semantics and compact recovery controls
  to the 250×40 floating recorder.

## Prevention

- Reliability changes now require reproduction, boundary-by-boundary evidence,
  a regression test, signed-package verification, and an incident update.
- Fixture-driven tests cover healthy one-request behavior, selective
  unprompted retry, prompt leakage, sparse timestamps, partial capture, and
  duration mismatch.
- CI owns the Xcode-backed package test. Development testing uses a diagnostic
  sink and does not repeatedly take over the user's cursor.
- Release completion requires installing the artifact built from merged
  `main`, not an unmerged local app.
