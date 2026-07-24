# Header-Only Recording Regression

- **Status:** Resolved and verified
- **Detected:** July 24, 2026 (Pacific time)
- **Affected product:** Interview Arc Voice for macOS
- **Impact level:** Critical — dictation could produce no usable transcript
- **Data exposure:** None
- **Affected modes:** General Dictation and linked Interview Arc capture

## Executive summary

The signed app could appear to record normally, then show **Needs attention**,
retain a disabled-looking memo toolbar, and offer a Retry action that never
produced text. The speech provider was not the failing boundary. The app had
created a roughly 4 KB M4A container with no playable audio frames.

The capture implementation treated a successfully started voice-processing
audio engine as proof that recording was viable. On the affected machine the
engine started, but its real-time tap never produced a finalized playable file.
Because the app remembered the file before inspecting it, the interface then
mistook an unplayable container for recoverable audio and offered
retranscription.

## Evidence

- New failed captures under Application Support were consistently about 4 KB.
- `afinfo` could not open those captures.
- The failure occurred before Groq transcription or editor insertion.
- Retry rewrote the same invalid bytes to a new temporary URL, so it could
  never recover missing speech.
- Older captures created through the system recorder remained decodable.

## Root cause

1. The voice-processing `AVAudioEngine` path was the primary recorder.
2. Successful engine startup did not guarantee that tap callbacks would deliver
   frames or that the AAC file would finalize.
3. Recording integrity was checked only after the file had already been exposed
   as the latest memo.
4. Every integrity failure set `canRetryLastTranscription` from the presence of
   bytes, even when those bytes contained no decodable audio.
5. Disabled memo actions remained visible in the compact widget, which implied
   that a usable recording existed.

## Resolution

- Use `AVAudioRecorder` as the production capture boundary so one system
  component owns encoding and finalization.
- Inspect the finalized file before showing memo recovery controls or calling
  speech-to-text.
- Classify complete audio, interrupted-but-playable audio, and header-only
  captures separately.
- Never offer retranscription for speech that was not recorded.
- Preserve playable partial audio for Play and Save, but ask the user to record
  again for a complete transcript.
- Hide memo actions when no usable last memo exists.
- Keep the link toggle available outside active recording, use a visible dark-blue
  broken-chain state, and add hover feedback to interactive widget and menu
  controls.

## Prevention

- Regression tests cover complete, playable-partial, and header-only recovery
  decisions.
- CI remains the canonical Swift/Xcode test environment.
- Release verification must use the exact signed artifact from merged `main`.
- The packaged app must complete a real general-dictation recording, produce a
  decodable M4A, insert text into a disposable editor, and exercise link
  on/off before installation is declared complete.

## Packaged-app verification

CI's full Swift test suite and packaging job passed on the repair pull request
and again after merge. The signed pull-request artifact was installed and
exercised before the exact merged-`main` artifact replaced it.

The packaged test confirmed:

- a clean launch hides Play, Copy, and Save instead of showing disabled ghosts;
- the dark-blue broken-chain button remains visible and toggles linking on and off;
- a real microphone capture reaches transcription and produces a recoverable
  memo with working Copy;
- unavailable capture bytes never reach the provider-retry path;
- the merged-main app matches the downloaded CI artifact and is the only
  installed Interview Arc Voice copy.

The automated desktop controller activates an app before clicking its window,
so it cannot preserve another editor as the foreground target while clicking
the floating recorder. Direct cursor insertion therefore remains verified by
the deterministic insertion suite and the existing signed-app insertion
postmortem rather than by claiming that this particular UI harness preserved
focus when it did not.

## Follow-up: timed near-silent AAC accepted as speech

The first repair distinguished a header-only file from a decodable file, but
it still accepted one additional failure shape. A real failed capture exported
from the packaged app reported 4.988 seconds and 79,808 valid decoded frames,
yet `afinfo` showed only 320 bytes of AAC audio data across 80 four-byte
packets—a 500-bit-per-second near-silent payload. Groq returned the guessed
single word “you.”

Two assumptions allowed this:

1. The `AVAudioRecorder` fallback converted its wall-clock duration into a
   synthetic written-frame count. That made elapsed time look like evidence
   that microphone frames had been written.
2. A decodable duration was treated as sufficient even though AAC can encode
   silence into tiny packets while still advancing the media timeline.

The follow-up repair removes the synthetic frame count and reads
`kAudioFilePropertyAudioDataByteCount` from the finalized container. Captures
lasting at least two seconds whose encoded payload is below 1,500 bits per
second are classified as insufficient signal, kept away from Groq, and ask the
user to record again. The interface does not expose Retry or insert a guessed
transcript for that capture.

A second packaged-app control recording lasted 46.844 seconds, contained
282,369 AAC audio bytes at 48,087 bits per second, and returned the complete
deterministic paragraph. This separated a transient microphone-signal failure
from the normal recorder and provider path.

The signed follow-up build then completed an end-to-end foreground test:

- 39.932 seconds captured through the installed application;
- 237,142 AAC audio bytes at 47,352 bits per second;
- the full opening, technical terms, and final “sapphire lighthouse” marker
  returned from transcription; and
- the resulting transcript inserted directly into the focused disposable
  TextEdit document.

The same build was launched cleanly with linking off. Its dark-blue chain with
a diagonal break rendered visibly on a pale-blue circle, and no memo controls
appeared until the first valid recording existed.

## Recurrence: valid timelines with no live microphone signal

Later on July 24, four additional packaged-app captures reproduced the
near-silent shape:

- 13.692 seconds at 692 bits per second;
- 6.460 seconds at 500 bits per second;
- 72.892 seconds at 500 bits per second; and
- 2.364 seconds at 500 bits per second.

All four files had valid M4A timelines, so file finalization itself succeeded.
Their encoded microphone payload was effectively silence. The integrity gate
correctly kept these files away from Groq, but the product still reduced the
failure to the generic label **Needs attention**. It neither warned while the
user was still speaking nor identified the active input after the recording.

The recurrence exposed two additional gaps:

1. recorder metering was used only for the waveform, not as a live health
   signal; and
2. AVAudioRecorder delegate errors and the selected input device were not
   retained as actionable diagnostics.

The follow-up adds a cheap, entirely local signal monitor. After a short warmup
it warns while a capture has not crossed the microphone-level threshold. It
also retains the finalized recording, selected input, duration, payload rate,
and integrity reasons in a persistent recovery notice. Encode/finalization
callbacks now contribute diagnostics instead of being discarded.

The same review found an independent retry-routing defect: a failed linked
capture could be retranscribed through the general-dictation route, losing its
Interview Arc activity association. Retry now preserves the original capture
destination and re-enters the linked pipeline with the same activity context.

These checks do not add a second transcription call to healthy recordings.
They run from the recorder's existing local meter and the finalized-file
inspection that already guarded the provider boundary.

## Recurrence-fix packaged verification

Pull request 18 and merged-main run `30106887060` passed the complete Swift
test-and-package workflow. The downloaded merged-main application passed
strict code-signature verification and package-resource verification before it
replaced the installed application. The installed executable SHA-256 was
`46471a47b9da85096ceb94595959d06315a444d6f437991895b431da8e1f5bdb`.

The exact installed artifact then completed a real desktop smoke test:

- linking off rendered the visible dark-blue broken chain;
- auto-link on with no running activity rendered the same chain geometry with
  the amber waiting badge and clearly stayed in general fallback;
- the live microphone meter reacted immediately during an 11-second capture;
- the finalized audio reached Groq and returned a punctuated transcript;
- Play widened the widget into its elapsed/total-time seek control and returned
  to compact mode when playback completed; and
- Copy, Save, and Record remained individually discoverable and accessible.

No Interview Arc activity was running during this verification, so the release
test intentionally did not create a synthetic production attempt or R2 object.
Linked retry routing is covered by the merged control-flow repair and CI;
production D1/R2 verification remains part of the next real linked practice
turn rather than contaminating the user's journal with test data.

The desktop automation harness activates an application before interacting with
it, so it cannot faithfully preserve a user's editor focus while clicking a
nonactivating floating panel. The test therefore verifies capture,
transcription, playback, icon states, and recovery affordances without making a
new direct-cursor claim beyond the established insertion regression suite.
