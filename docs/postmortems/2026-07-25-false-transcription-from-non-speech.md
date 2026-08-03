# False transcription generated from non-speech capture

- Incident issues:
  [#33](https://github.com/Vinosaamaa/interview-arc-voice/issues/33),
  [#81](https://github.com/Vinosaamaa/interview-arc-voice/issues/81)
- Status: recurrence repair in progress; exact merged-artifact verification
  required
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

A later recurrence exposed two increasingly specific failure shapes. A valid
long recording contained real speech before and after a sustained thinking
pause. The whole-recording gate correctly accepted the capture, but the
provider returned invented text such as “Thank you” inside the silent interval.
The first follow-up retained the existing local frame timeline and Groq segment
metadata, then suppressed a segment only when both sources independently
identified its timestamp interval as non-speech. Production diagnostics later
showed that this repair ran but omitted zero segments: the provider can place
real speech and a silent-interval hallucination in the same segment or report
the mixed segment with high confidence. Segment-granularity deletion therefore
could not safely remove the false phrase.

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

The mixed-segment recurrence was detected through the installed app's bounded
privacy-safe diagnostics. Of the latest 100 attempts inspected, 96 used
Enhanced, all 96 executed the local scan, 94 reached provider delivery, and all
94 executed transcript validation. None omitted a segment. Most validation
durations appeared as `0 ms` because the prior UI rounded sub-millisecond work
to an integer, not because validation was skipped.

A second installed recurrence occurred after word-level protection shipped. A
152-second natural capture returned 124 word timestamps for a 135-token
canonical provider transcript, so complete alignment was false. The validator
therefore disabled word-level removal globally and inserted one contiguous
42-token fabricated passage even though its independently timestamped region
could be checked against local evidence.

A terminal recurrence was retained in Recent History on August 1. The
58.12-second delivered transcript ended with a two-word generic closing phrase,
while an independent local transcription did not. Independent speech ended at
56.26 seconds. Across the remaining 1.98 seconds, the median level was
approximately -83.7 dBFS and only 5 of 99 20-millisecond frames exceeded
-38 dBFS. Groq's final lexical timestamp nevertheless extended to 58.50
seconds. Complete word alignment was true, but the validator evaluated the two
short terminal words independently. A brief Stop transient could make each
small padded interval exceed the one-percent local-frame threshold even though
the combined phrase and remaining tail contained no sustained speech.

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

The first segment-local repair then made a second coarse-granularity
assumption: one provider segment would correspond to one locally supported or
unsupported acoustic interval. Provider segmentation does not guarantee that.
A segment may contain both genuine speech and a hallucinated phrase timestamped
over a pause. Deleting that segment would lose real speech, while preserving it
kept the hallucination. Its provider-level confidence can also remain high
because confidence is aggregated across the mixed segment.

The first word-level follow-up made another overly broad safety decision:
incomplete word coverage anywhere in the recording disabled every word-level
decision. Groq word timestamps may be sparse around a pause or another
unrelated portion of a long answer. That global fail-open rule preserved
genuine text, but it also prevented a separate, uniquely identifiable
timestamped hallucination run from being removed.

A third installed recurrence occurred after the hand-built whole-capture
threshold was extended to require a 260 ms speech-like span. The exact
merged-main executable passed one staged silent capture, then admitted a second
silent AirPods capture after installation. That attempt reached the provider
and delivered a known two-word hallucination. The byte-identical result proved
that a longer Bluetooth/profile-transition artifact could still satisfy the
energy, zero-crossing, crest-factor, and duration heuristic. Threshold tuning
alone was not an adequate independent proof of human speech.

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

The third recurrence adds an independent whole-capture admission check using
the WebRTC voice-activity detector pinned through Swift Package Manager.
Decoded samples are deterministically resampled to 16 kHz and evaluated in
20 ms frames using the detector's very-aggressive mode. The final Boolean now
requires both gates:

- the existing acoustic-frame heuristic must find the minimum sustained span;
- WebRTC VAD must find at least 12 consecutive active frames and at least 12
  active frames total for sub-750 ms captures, or 14 total for longer
  captures; and
- detector setup or processing failure fails closed.

The existing frame timeline remains unchanged for Enhanced timestamp-local
validation. The VAD does not rewrite audio, inspect transcript text, invoke an
AI classifier, or add a provider request. Diagnostics persist only the VAD
active-frame count and longest run.

For Enhanced protection, that same scan retains each 20 ms frame's speech-like
decision and level. The existing verbose Groq response retains timestamped
segments and words plus segment `no_speech_prob` and `avg_logprob`. A complete
segment is omitted only when all safeguards agree:

- the provider no-speech probability is at least `0.60`;
- the provider average log probability is at most `-1.0`;
- the matching local interval, padded by 150 ms on both sides, has no sustained
  speech-shaped run;
- speech-like frames occupy no more than one percent of that interval; and
- the provider segments completely represent the canonical transcript.

When real and unsupported text share a segment, Enhanced performs one narrower
local comparison:

- normalized segment tokens must exactly cover the canonical transcript;
- normalized word-timestamp tokens must independently cover that complete
  canonical transcript;
- each candidate word interval is padded by 150 ms and expanded to at least
  450 ms of evidence;
- that interval must contain analyzed frames, no sustained speech-shaped run,
  and no more than one percent speech-like frames; and
- only the exact canonical source-text range for verified words is removed.

Complete normalized word coverage maps every timestamp directly. When coverage
is incomplete elsewhere, consecutive timestamped words over strongly verified
local silence form one candidate run. The run is removed only when its
normalized tokens occur exactly once in the canonical provider transcript.
Unmatched canonical text is preserved, and a repeated or otherwise ambiguous
candidate fails open. Punctuation and capitalization are preserved because the
filter deletes source ranges rather than reconstructing the transcript. The
comparison happens before cursor insertion and before linked pending-capture
creation. The original M4A is never edited and remains the object used for
playback and private upload.

The repair deliberately rejected heavier alternatives:

- no phrase blacklist;
- no silence cutting or audio segmentation;
- no re-encoding;
- no second AI classifier;
- no automatic second provider request on the normal path;
- no second Groq call for word timestamps (they are requested in the existing
  verbose response);
- no punctuation or wording rewrite.

The August 1 terminal repair adds one deliberately narrow combined-tail rule in
Enhanced mode. When complete word alignment maps the canonical transcript's
exact final tokens to “thank you,” the validator evaluates both timestamped
words plus the remainder of the real audio as one interval. It removes the
pair only when it reaches the recording tail, Groq corroborates the rejection
through unsupported confidence metadata or a material timestamp overrun beyond
the real audio, analyzed local frames contain no sustained speech-shaped run,
and at most ten percent of the combined interval is speech-like. The higher
combined-interval allowance tolerates a short Stop transient; it is not applied
to arbitrary text or non-terminal occurrences. Sustained local evidence and a
quiet, high-confidence in-range closing are both preserved.

## Verification

Deterministic regression fixtures cover:

- digital silence;
- steady fan-like hum;
- isolated keyboard-like clicks;
- short, soft, speech-shaped audio.
- Bluetooth/profile-transition noise rejected by independent VAD;
- valid short speech accepted at both 16 kHz and the 24 kHz AirPods fallback
  rate;
- speech before and after one or multiple sustained pauses;
- a genuinely spoken “Thank you”;
- suspicious “Thank you” and prompt-derived vocabulary over silence;
- real speech and silent-interval hallucination inside the same provider
  segment;
- exact full word coverage;
- incomplete word coverage elsewhere with a uniquely aligned silent run;
- ambiguous partial alignment, which must preserve the transcript;
- local/provider disagreement, which must preserve text;
- steady background sound and isolated impulses;
- incomplete provider segment metadata;
- one-provider-call behavior and older saved-result compatibility;
- bounded permission-0600 diagnostics with no private content.
- backward-compatible diagnostic decoding with optional VAD metrics.
- a terminal two-word hallucination separated from silence by brief Stop noise;
- genuinely spoken terminal “Thank you” remains preserved;
- a quiet, high-confidence, in-range terminal “Thank you” remains preserved.

The optimized frame comparison remains linear and uses the already decoded
timeline. Word alignment and source-range filtering are also linear in the
returned transcript size. Representative measurements put the synthetic
10-minute frame analysis at approximately 14 ms and a warm decode of an
11.4-minute AAC file at approximately 110–200 ms; upload and provider wait
remain dominant. There is no extra decode, upload, or provider request. Local
diagnostics now separate finalization, integrity inspection, speech scan,
provider wait, response processing, transcript validation, insertion, and
total elapsed time; sub-millisecond values display as `<1 ms` instead of
rounding to zero.

The release checklist also requires a signed-app manual matrix with silence,
room tone, a click, “Thank you,” a soft short answer, general dictation, and
linked mode. Network logs and Interview Arc state must confirm that rejected
captures create no provider call, insertion, D1 turn, R2 object, or coaching
job.

For the third recurrence, staged and installed verification must additionally
confirm that a silent AirPods/profile-transition capture reports `noSpeech`,
provider wait remains zero, and the diagnostic contains VAD frame/run counts.
The exact same installed executable must then preserve a genuine short AirPods
utterance. Issues #33 and #58 remain open until that installed positive/negative
matrix passes.

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
- Treat provider segments as presentation groupings, not guaranteed acoustic
  truth boundaries; use exact source-range alignment when a mixed segment must
  be narrowed.
- Preserve a partial candidate whenever its canonical source range is not
  unique.
- Preserve older pending records when optional provider metadata is introduced.

## 2026-07-31 follow-up: spoken tail omitted after 30 seconds

### Impact

A General Dictation capture longer than 30 seconds preserved clear speech on
both sides of that boundary, but the delivered transcript compressed much of
the later spoken passage into a shorter question. The missing text could not be
recovered from the inserted transcript, although the original M4A remained
available in Recent Transcripts.

### Evidence and boundary isolation

- the preserved M4A contains the missing speech;
- an independent local transcription preserves speech on both sides of the
  30-second boundary;
- the installed diagnostic reports five evaluated provider segments, complete
  word alignment, zero omitted segments, and zero omitted words;
- the stored Recent Transcript and inserted text are identical;
- the sub-megabyte recording took the direct-upload path because chunking
  considered only the 23 MB file-size threshold;
- a single-chunk response is assembled from Groq's canonical top-level text
  without an overlap merge or wording rewrite.

### Root cause

The transport treated compressed byte size as the only signal for chunking.
Normal AAC dictations therefore stayed far below 23 MB even when they exceeded
Whisper Large v3's approximately 30-second optimized audio context. In this
incident, the provider compressed or omitted speech beginning at that context
boundary. Enhanced silence protection and cursor insertion preserved the
provider result exactly; neither stage removed the spoken words.

### Repair and prevention

- split on acoustic duration as well as byte size;
- cap every provider window at 30 seconds with a 1.5-second overlap and balance
  the windows so no tiny tail request is created;
- keep windows concurrent so provider latency is bounded by the slowest request
  rather than their sum;
- retain exact overlap deduplication and timestamp offset restoration;
- add a regression based on the observed small-but-long recording shape so
  compressed recordings cannot bypass duration chunking again;
- keep the original M4A as the recovery and playback source.

This change does not alter Off, Basic, or Enhanced filtering decisions. It
repairs the provider input boundary before those modes evaluate the returned
transcript.

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

PR #83 merged as `bc462f4b9be970b007da6822c2baf6afb2ac4f7c`.
Merged-main workflow `30394045237` passed the complete Swift test and package
job. The downloaded application passed strict code-signature and package
resource verification. Its executable SHA-256 was:

`3743de08ff2e07319469d32a3daa78ef8027869c39eb3b96a5d9706c5f4591ed`

That exact artifact was launched from a temporary staging directory, where it
loaded the normal linked/general-dictation context without a credential prompt.
It was then installed at `~/Applications/Interview Arc Voice.app`; the installed
executable matched the staged hash exactly and loaded the same normal user
context.

The deterministic mixed-segment matrix, exact package checks, staged launch,
and installed launch are complete. The next naturally occurring long-pause
capture remains required before closing #81 so the release record does not
substitute synthetic evidence for the reported acoustic environment.

## 2026-07-29 whole-capture recurrence

The installed application again inserted short fabricated transcripts from
captures where the user reported saying nothing while the microphone route was
also failing. The bounded local history and privacy-safe diagnostics recorded:

- a 1.678-second capture delivered three provider words;
- a 1.838-second capture delivered one provider word;
- a 2.502-second capture delivered two provider words; and
- a nearby 1.437-second capture was correctly rejected as `noSpeech`.

The fabricated outputs included the same short provider patterns that motivated
the original incident. They are not reproduced here as a blacklist: legitimate
users can say those words.

The confirmed software gap was the whole-capture gate. It treated as speech as
few as seven speech-like 20-millisecond frames, with only four consecutive
frames required. A short, amplitude-varying Bluetooth/profile-transition burst
can satisfy the energy, zero-crossing, crest-factor, peak, and range checks even
though no human speech exists. Once that gate passed, a confident provider
hallucination was retained because segment-local rejection deliberately
requires provider silence/low-confidence corroboration.

The exact delivered source files had already followed normal successful-capture
cleanup, so this postmortem does not claim a byte-level acoustic classification
of those three files. The user report, simultaneous no-signal recorder state,
diagnostics, and a deterministic route-transition fixture establish the failed
software boundary without inventing unavailable evidence.

The recurrence repair strengthens only the whole-capture authorization:

- short captures require at least twelve speech-like frames;
- longer captures require at least fourteen;
- at least six frames must be consecutive;
- evidence must span at least 260 milliseconds; and
- the existing dynamic-range and peak safeguards remain.

The segment/word validator keeps its more local thresholds so genuine short
words inside an otherwise valid answer are not removed. A deterministic
Bluetooth transition burst now fails closed, while the existing 550-millisecond
soft-speech fixture remains accepted. The normal path still performs one local
decode and one provider request; rejected captures never reach the provider,
cursor, D1, R2, or Delivery Coach.

Issue #33 was reopened for this recurrence and is cross-linked to the active
silent-microphone recurrence in #58. Final merged-main artifact and installed
acoustic verification are recorded in those issue resolution histories.

## 2026-08-03 terminal-tail recurrence with malformed provider time

A retained Enhanced-mode recording again ended with the known terminal phrase
although the user did not speak it. The private audio and transcript remained
local; only aggregate evidence is recorded here:

- decoded audio duration: 29.859625 seconds;
- provider lexical coverage end: 59.46 seconds;
- complete word alignment across 43 timestamped words and three segments;
- zero omitted segments and zero omitted words; and
- the installed local verifier covered 36 words through 23.74 seconds.

The earlier terminal-tail guard recognized a material timestamp overrun but
then opened the local acoustic evidence window at the provider word start.
Because that start was already beyond the decoded audio end, the window held no
frames and the guard failed open.

For an exact terminal phrase with a material provider timestamp overrun, the
repair right-aligns a bounded phrase-duration window to the real decoded audio
end. The phrase is removable only when that real tail contains no sustained
speech and remains below the existing speech-like fraction threshold. A
paired regression supplies genuine tail speech with the same malformed
provider timeline and requires the phrase to remain. This is not a global text
blacklist and remains limited to Enhanced protection.
