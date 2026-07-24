# Long-Dictation Transcript Integrity Failure

- **Status:** Repair in progress
- **Detected:** July 24, 2026 (Pacific time)
- **Affected product:** Interview Arc Voice for macOS
- **Impact level:** Critical — user speech could be truncated or contaminated
- **Data exposure:** None
- **Affected mode:** Most visible in General Dictation; transcript assembly was shared

## Executive summary

Interview Arc Voice sometimes produced a shorter and less accurate transcript
than ChatGPT from the same long recording. It could also append unrelated text,
including a sentence that exactly matched an internal transcription prompt.
The menu then displayed only two lines of the result, and a failed
transcription discarded its temporary audio, leaving no way to inspect or
retry the recording.

This was a pipeline failure, not a Groq long-recording limit. A controlled
116-second recording returned every test marker from Groq. Two implementation
defects then made production behavior unreliable:

1. General Dictation passed an English instruction paragraph through Whisper's
   `prompt` field. That field is prior-transcript context, not a protected
   instruction channel, so the model could continue or repeat the prompt as
   transcript text.
2. When Groq returned word timestamps, Interview Arc Voice ignored Groq's
   complete top-level transcript and rebuilt the answer from the timestamp
   array. Word alignment can be sparse around pauses or at the end of a long
   recording, so a complete transcript could become truncated.

The repair removes the General Dictation prompt entirely, uses Groq's complete
text as the canonical transcript, retains word timestamps only for delivery
coaching, and makes the last recording recoverable in memory. The menu now
provides a processing timer, scrollable transcript, copy, playback, explicit
audio-plus-text export, reinsertion, and retry after transcription failure.

## User impact

- A long answer could lose its closing sentences.
- Internal prompt text could appear as if the user had spoken it.
- Low-confidence or ambient speech could be transcribed as unrelated prose.
- The two-line transcript preview concealed whether the underlying result was
  complete.
- A failed General Dictation attempt could not be retried because its temporary
  audio was deleted.
- During a long request, the disabled microphone did not clearly communicate
  that transcription and insertion were still running.

No transcript or recording was committed to Git. General Dictation continues
to avoid automatic persistent storage; its most recent audio is kept only in
memory unless the user explicitly exports it.

## Evidence

### Controlled long-recording test

A synthetic 115.84-second, 307-word recording with unique opening, middle, and
closing markers was submitted through the same Groq model used by Voice. Both
prompted and unprompted requests returned the final marker. This ruled out a
normal two-minute service cutoff.

### Exact prompt match

The unexpected sentence “Preserve punctuation, names, acronyms, and technical
terminology” matched a literal string passed by
`GeneralDictationPipeline` through Groq's `prompt` field. No external source was
needed to explain that text.

### Assembly-path inspection

`TranscriptAssembler` selected `response.words` whenever that array was
nonempty and reconstructed all visible prose from those entries. The complete
`response.text` was used only when no word timestamps existed. This inverted
the intended source-of-truth relationship.

## Root causes

### Primary cause 1: an instruction was sent as transcript context

Whisper-style prompts bias transcription by describing text that precedes the
audio. They are useful for bounded names and technical terms, but they are not
system instructions. Sending “Verbatim general dictation…” made that prose part
of the model's linguistic context and allowed it to leak into output.

### Primary cause 2: timestamp alignment replaced canonical text

Timestamp words are intended for timing and delivery analysis. They are not a
more authoritative transcript than the provider's complete text. Treating them
as authoritative introduced silent data loss.

### Contributing causes

1. The menu preview used `lineLimit(2)`, making a long result appear cut off
   even when more text existed.
2. General Dictation deleted the temporary M4A in a `defer` block regardless of
   success or failure.
3. The busy state reused a generic disabled Record button instead of showing a
   live transcription state and elapsed time.
4. There was no user-controlled playback or retry path to distinguish an audio
   capture problem from an STT problem.
5. Regression tests checked punctuation and chunk overlap but did not model a
   complete top-level transcript paired with a sparse word array.
6. The first voice-processing capture implementation inherited `MainActor`
   isolation inside AVAudioEngine's real-time tap callback. Packaged-app
   testing caught the resulting queue-isolation crash before release.

## Five Whys

### Why was the end of a long answer missing?

1. Because the visible transcript was reconstructed from word timestamps.
2. Because the assembler preferred `words` whenever present.
3. Because word timestamps were assumed to be a complete transcription.
4. Because unit coverage used a word list that exactly matched the text.
5. Because the contract did not explicitly name top-level `text` as canonical.

### Why did an internal sentence appear in the transcript?

1. Because Voice supplied it through the speech model's prompt field.
2. Because the prompt was written like an instruction.
3. Because the prompt field was mistaken for an instruction channel.
4. Because clean short recordings did not consistently reproduce leakage.
5. Because there was no test asserting that General Dictation sends no prompt.

## Resolution

- General Dictation now sends an empty prompt; empty prompts are omitted from
  the multipart request.
- `response.text` is canonical for every chunk and is overlap-deduplicated
  across large-file chunks.
- Word timestamps remain available but can no longer shorten visible text.
- The current M4A is loaded into memory before its temporary file is deleted.
- A failed transcription retains that in-memory audio and exposes Retry.
- The menu shows a live progress indicator and elapsed processing time.
- The last transcript is scrollable and selectable.
- Copy, play/pause, save audio plus text, and insert-again controls are explicit
  icon actions with accessibility labels.
- Export is user initiated and writes a matching `.m4a` and `.txt`; General
  Dictation still performs no automatic persistent storage.
- Recording uses Apple's voice-processing input path for echo cancellation and
  noise suppression, with the original recorder as a compatibility fallback.
- The audio tap writes through an explicitly sendable, non-actor helper; only
  meter updates cross back to `MainActor`.

## Prevention and verification

- Add a regression test where `response.text` is complete but `words` ends
  early.
- Assert that General Dictation passes no prompt.
- Retain the existing overlapping-chunk test.
- Validate a multi-minute recording through the packaged app, not only through
  a direct API request.
- Verify the busy indicator, retry path, transcript scrolling, playback, copy,
  explicit export, and insertion in both Chromium and Electron editors.
- Keep raw user audio and transcripts outside Git and CI fixtures.
