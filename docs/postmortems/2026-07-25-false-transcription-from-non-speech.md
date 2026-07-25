# False transcription generated from non-speech capture

- Incident issue: [#33](https://github.com/Vinosaamaa/interview-arc-voice/issues/33)
- Status: remediated in the consolidated Voice open-issues release
- Affected surface: general dictation and Interview Arc-linked recording
- Severity: data-integrity risk

## Summary

Very short or silent captures could contain enough encoded audio data to pass
the recording-integrity checks. Whisper-family transcription could then infer a
plausible phrase such as “you” or “thank you” from room tone, a click, or another
non-speech signal. General dictation could insert that phrase at the focused
cursor. Linked mode could additionally persist the false transcript and enqueue
audio delivery and coaching.

The application now performs local speech-evidence analysis on the finalized
audio before any transcription request. Captures without sustained
speech-shaped frames are rejected with “No speech detected.” They are not sent
to Groq and cannot reach insertion, D1, R2, or delivery coaching.

## Impact

The issue could create a false user turn from audio in which the user did not
actually speak. Even though the resulting text was usually short, this violated
the product’s source-of-truth rule: Interview Arc must not invent transcript
content or practice evidence.

## Detection

The user reproduced the behavior in both Interview Arc Voice and another
Whisper-backed dictation product by starting and stopping a capture without
speaking. Existing tests covered header-only files, low bit rate, missing
decoded frames, duration mismatch, and provider transcript anomalies, but did
not model a structurally valid file containing non-speech sound.

## Root cause

The pre-transcription gate measured file integrity and broad signal presence,
not speech presence:

1. A valid AAC file with room tone or a transient click has decoded frames,
   duration, bytes, and sometimes a peak above the “microphone connected”
   threshold.
2. Those checks correctly prove that recording worked, but they do not prove
   that a person spoke.
3. The provider was therefore asked to decode acoustically ambiguous input.
4. Language-model priors could turn that ambiguity into a common short phrase.

The known-boilerplate transcript filter was intentionally insufficient. A
global blacklist for “you” or “thank you” would also delete legitimate speech.

## Resolution

`LocalSpeechEvidenceAnalyzer` decodes the finalized file locally and evaluates
20 ms frames using:

- adaptive energy above the capture’s noise floor;
- zero-crossing bounds that reject steady noise and extremely noisy frames;
- crest factor to reject impulse-like clicks;
- a minimum sustained run and total count of speech-like frames;
- short-capture thresholds that preserve soft, brief real speech.

Only audio with positive local speech evidence continues to transcription.
This adds no network request and uses a small linear pass over decoded mono
samples. On a 30-minute answer, the work remains O(n) with bounded frame state.

## Verification

Deterministic regression fixtures cover:

- digital silence;
- steady fan-like hum;
- isolated keyboard-like clicks;
- short, soft, speech-shaped audio.

The release checklist also requires a signed-app manual matrix with silence,
room tone, a click, “Thank you,” a soft short answer, general dictation, and
linked mode. Network logs and Interview Arc state must confirm that rejected
captures create no provider call, insertion, D1 turn, R2 object, or coaching
job.

## Prevention and follow-up

- Treat recording integrity, speech evidence, transcription integrity, and
  delivery integrity as separate gates.
- Add a non-speech fixture whenever a new recorder or codec path is introduced.
- Never solve provider hallucination by blacklisting legitimate phrases.
- Keep the local decision observable through structured metrics without
  logging raw audio or private transcript content.

## Rollback

If the analyzer rejects verified real speech, the local gate can be disabled in
one release while retaining all existing recording and transcription integrity
checks. No schema or server rollback is required.
