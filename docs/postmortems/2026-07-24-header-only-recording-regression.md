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
- Keep the link toggle available outside active recording, use a visible coral
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
- the coral broken-chain button remains visible and toggles linking on and off;
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
