# False transcription generated from non-speech capture

- Incident issues:
  [#33](https://github.com/Vinosaamaa/interview-arc-voice/issues/33),
  [#81](https://github.com/Vinosaamaa/interview-arc-voice/issues/81)
- Status: whole-recording failure remediated; segment-local recurrence repaired
  pending merged-main installation verification
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

A later recurrence exposed a different failure shape: a valid long recording
contained real speech before and after a sustained thinking pause. The
whole-recording gate correctly accepted the capture, but the provider returned
invented text such as “Thank you” inside the silent interval. The follow-up
repair retains the existing local frame timeline and Groq segment metadata,
then suppresses a segment only when both sources independently identify its
timestamp interval as non-speech.

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

The segment-local recurrence was diagnosed from private local recordings
without committing their audio or transcript content. In one representative
capture, the returned phrase occupied approximately 86.9–90.8 seconds within
an approximately 17-second no-speech interval. Another long answer contained a
returned phrase inside an approximately 33-second no-speech interval.
Deterministic synthetic fixtures now reproduce those shapes.

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

The original analyzer also discarded every frame decision after computing one
capture-wide Boolean. Once any speech existed elsewhere, downstream code could
not ask whether the audio at a specific provider timestamp contained speech.
The Groq decoder similarly discarded `no_speech_prob`, `avg_logprob`, and the
assembled segment timeline. This made segment-local corroboration impossible.

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

For Enhanced protection, that same scan now retains each 20 ms frame's
speech-like decision and level. The existing verbose Groq response retains
timestamped segments plus `no_speech_prob` and `avg_logprob`. A segment is
omitted only when all safeguards agree:

- the provider no-speech probability is at least `0.60`;
- the provider average log probability is at most `-1.0`;
- the matching local interval, padded by 150 ms on both sides, has no sustained
  speech-shaped run;
- speech-like frames occupy no more than one percent of that interval; and
- the provider segments completely represent the canonical transcript.

Any missing metadata, incomplete segment coverage, local speech evidence, or
provider confidence preserves the text. The comparison happens before cursor
insertion and before linked pending-capture creation. The original M4A is never
edited and remains the object used for playback and private upload.

The repair deliberately rejected heavier alternatives:

- no phrase blacklist;
- no silence cutting or audio segmentation;
- no re-encoding;
- no second AI classifier;
- no automatic second provider request on the normal path;
- no punctuation or wording rewrite.

## Verification

Deterministic regression fixtures cover:

- digital silence;
- steady fan-like hum;
- isolated keyboard-like clicks;
- short, soft, speech-shaped audio.
- speech before and after one or multiple sustained pauses;
- a genuinely spoken “Thank you”;
- suspicious “Thank you” and prompt-derived vocabulary over silence;
- local/provider disagreement, which must preserve text;
- steady background sound and isolated impulses;
- incomplete provider segment metadata;
- one-provider-call behavior and older saved-result compatibility;
- bounded permission-0600 diagnostics with no private content.

The optimized frame comparison remains linear and uses the already decoded
timeline. Representative measurements put the synthetic 10-minute frame
analysis at approximately 14 ms and a warm decode of an 11.4-minute AAC file at
approximately 110–200 ms; upload and provider wait remain dominant. Local
diagnostics now separate finalization, integrity inspection, speech scan,
provider wait, response processing, segment validation, insertion, and total
elapsed time.

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
- Treat whole-recording speech evidence and segment-local transcript support as
  separate integrity questions.
- Keep segment filtering before all insertion, D1, R2, and coaching boundaries.
- Preserve older pending records when optional provider metadata is introduced.

## Rollback

If Enhanced rejects verified real speech, select Basic in Settings or revert
the segment validator while retaining the whole-recording gate. If the
whole-recording analyzer itself regresses, Off is an explicit warned escape
hatch. No server schema, D1, R2, or audio migration is required.

## Release verification for the segment-local follow-up

Resolution of #81 requires:

1. all deterministic regression tests on the macOS CI toolchain;
2. strict signature and package self-checks on the exact artifact produced from
   merged `main`;
3. staged launch and normal-user credential readiness before installation;
4. hash-identical installation of that artifact; and
5. an installed-app long-pause capture confirming that spoken regions remain,
   unsupported silent-interval text is absent, and the original recording
   remains playable.
