# Postmortem: Partial transcript delivered while speech remained in the recording

**Date**: 2026-08-01  
**Status**: Reopened — alternate recovery repair in implementation<br>
**Severity**: P0 silent data loss  
**Issue**: [interview-arc-voice#123](https://github.com/Vinosaamaa/interview-arc-voice/issues/123)  
**Pull requests**: [interview-arc-voice#136](https://github.com/Vinosaamaa/interview-arc-voice/pull/136), [interview-arc-voice#147](https://github.com/Vinosaamaa/interview-arc-voice/pull/147)

> **Recurrence update:** The exact #136/#140 installed artifact delivered a
> second incomplete 80.89-second transcript on 2026-08-01. The follow-up root
> cause was a malformed provider word timestamp combined with an unsafe
> nonempty-segment fallback. The chronology, failed control, and corrective
> action below have been updated; the incident is not considered closed until
> the replacement merged-main artifact completes installed verification.

## Executive summary

Interview Arc Voice inserted a plausible but incomplete transcript for a
general-dictation recording. The original M4A was complete and retained clear
speech after the final delivered words. The application labeled the attempt
delivered, so the user had no warning that later speech was absent.

The transcription-integrity guard compared local tail speech with the maximum
end time of every provider segment. A provider response can include an empty or
metadata-only trailing segment that reaches the audio duration even when its
lexical transcript stops earlier. That segment made the response appear to
cover the full recording, bypassing the retry and recoverable-failure path.

## User impact

- One confirmed 52.97-second dictation lost the later spoken section from the
  inserted transcript.
- The original audio was retained locally, so the speech evidence was
  recoverable.
- The application reported success instead of an incomplete-transcript error.
- A previous report had the same failure class, establishing recurrence.
- A later 80.89-second dictation contained independently recoverable speech
  through approximately 80.66 seconds, while the delivered provider text ended
  at approximately 73.46 seconds. The app again reported `delivered`.
- A separate clear 46.78-second recording was rejected safely, but the original
  attempt and two manual retries all displayed the same generic failure while
  diagnostics falsely reported zero provider time.
- A later 14.40-second retained recording contained a second spoken section
  recovered by independent local transcription. Groq returned only nine words,
  but stretched its final lexical timestamp to 13.84 seconds. Enhanced mode
  omitted zero segments and zero words, so the incomplete provider result was
  delivered unchanged.
- A later 328-second recording was rejected safely but could not be recovered:
  four visible attempts consumed eight whole-file provider calls and every
  prompt-free retry reproduced `missingSpeechCoverage`. The user retained the
  audio but received no usable text from the application.
- A separate 241-second preserved recording reproduced the same failure class.

No transcript or recording content was exposed outside the intended local and
provider boundaries.

## Detection

The user noticed that the inserted text ended before the recording did. The
application had no alert for this response shape. Diagnosis compared each
boundary independently:

| Boundary | Evidence |
| --- | --- |
| Recording | 52.99-second decodable M4A, 847,808 valid frames |
| Local speech scan | 1,384 WebRTC VAD speech frames |
| Independent transcription | Recovered clear speech through 52.70 seconds |
| Provider metadata | 37 word timestamps and 7 segments |
| Enhanced protection | Removed 0 segments and 0 words |
| Delivery | Marked `delivered` without retry or warning |

The preserved audio and independent local transcription are private diagnostic
evidence and are not committed to Git.

## Timeline (Pacific time)

- 2026-07-31 — The first partial-transcript report created issue #123.
- 2026-07-31 — An initial tail-coverage guard was merged with a synthetic test
  whose segments all ended with lexical content.
- 2026-08-01 00:36 — A package containing that guard was installed.
- 2026-08-01 10:56 — A 52.97-second dictation was delivered without its later
  spoken section.
- 2026-08-01 11:00 — The user reported recurrence and requested P0 treatment.
- 2026-08-01 11:19 — A second complete recording failed safely; two manual
  retries executed but returned the same incomplete-provider result.
- 2026-08-01 — Boundary inspection confirmed complete audio, retained tail
  speech, no Enhanced-filter omission, and an insufficient coverage decision.
- 2026-08-01 — Pull request #136 passed the canonical macOS package workflow
  and all configured quality gates, then merged as `58b30a1`.
- 2026-08-01 — Merged main rebuilt and packaged tree `d275b7e` in workflow
  run `30715292109`; the exact artifact was stably signed, staged, installed,
  and launched.
- 2026-08-01 14:13 — That exact installed artifact delivered an 80.89-second
  capture with approximately 7.20 seconds of later speech absent. Diagnostics
  reported complete word alignment but omitted the lexical-coverage field.
- 2026-08-01 14:18 — Issues #123 and #138 were reopened. The preserved audio
  was confirmed complete and independently transcribed without committing
  audio or transcript content to Git.
- 2026-08-01 — A production-shaped regression reproduced the false pass: one
  canonical word had zero duration, the remaining valid word timings ended
  before sustained local speech, and a nonempty provider segment reached the
  full recording duration.
- 2026-08-01 15:52 — A 14.40-second dictation reproduced a second topology:
  Groq omitted an internal spoken passage while a later word timestamp still
  reached the recording tail. Independent local transcription recovered the
  omitted passage; app diagnostics confirmed zero local-filter omissions.
- 2026-08-01 — Two preserved long recordings were replayed three times each.
  For both, the two prompt-free whole-file requests returned exactly identical
  canonical text while their word/segment timestamp JSON differed.
- 2026-08-01 — The current internal-gap detector rejected all six replayed
  responses. Several local-evidence fractions were close to its 10% threshold,
  while independent local and chunked transcriptions disagreed about whether
  the same intervals contained omitted words.
- 2026-08-01 — Immediate approximately 30-second pieces with 1.5-second
  overlap recovered materially different text. The 328-second recording
  assembled 581 words versus 556 from whole-file prompt-free retry; neither
  alternate output was treated as ground truth.

## Root cause

### Proximate cause

`ReliableSpeechTranscriber` used the maximum `segment.end` as provider coverage.
An empty or metadata-only trailing segment could therefore extend coverage to
the full audio duration without contributing any words to the canonical text.

### Why the first guard did not prevent recurrence

1. The regression fixture represented truncation as an absent final segment.
2. Production can represent it as a present final segment with no lexical
   content.
3. The guard treated all segment timing as transcript timing.
4. The diagnostic record did not include the chosen coverage boundary, tail
   evidence, retry status, or integrity reasons, delaying direct detection.

### Why the second guard still did not prevent recurrence

1. The follow-up correctly ignored empty trailing segments, but retained a
   fallback to nonempty segment timing.
2. It filtered malformed word timestamps before comparing returned word tokens
   with the canonical transcript. One zero-duration word therefore made an
   otherwise complete word-token alignment appear incomplete.
3. The code then accepted the enclosing nonempty segment because its text
   normalized to the canonical transcript.
4. Provider segments are acoustic decoding windows. A segment can reach the
   end of processed audio even when the words returned for that window omit
   later speech, so its end time was not a trustworthy lexical boundary.
5. The resulting boundary equaled the recording duration. No trailing local
   interval was evaluated, no retry ran, and the partial response was inserted.

The recurrence diagnostic's combination of `wordAlignmentComplete: true` and
an absent lexical-coverage field was consistent with this path. Independent
local transcription recovered 165 normalized words versus the delivered 146,
with material speech continuing for roughly 7.20 seconds after the delivered
ending.

### Contributing factors

- Provider top-level duration described processed audio, not lexical coverage.
- The integrity evaluator correctly preserved sparse timestamp results but did
  not distinguish complete lexical alignment from empty trailing metadata.
- The first issue remained open and had not completed merged-main installed
  verification against the recurrence shape.
- The failure boundary discarded both provider timing and integrity context,
  making an executed retry look like a dead control and a zero-millisecond
  provider call.
- The internal-gap threshold treated weak local evidence as an absolute veto
  even though Groq word timestamps varied between byte-distinct responses with
  identical canonical text.
- `missingSpeechCoverage` remained active in Off and Basic even though it was
  an experimental cross-signal heuristic rather than a structural provider
  failure.
- Recovery repeated the same whole-file strategy. For both preserved long
  recordings, prompt-free retry text was deterministic, so repeated manual
  Retry actions could not escape the failure topology.

## Initial resolution (superseded)

The superseded repair:

1. normalizes the canonical provider text;
2. uses word coverage only when all valid timestamped words map exactly to that
   canonical text;
3. otherwise uses only nonempty lexical segments that map exactly to the text;
4. ignores empty and metadata-only trailing segments;
5. compares sustained local speech after the lexical boundary;
6. retries exactly once without the vocabulary prompt; and
7. preserves the audio and raises a recoverable failure when the retry remains
   partial.

The lexical-tail completeness check uses the always-on local integrity scan;
the optional Silence Protection setting may disable hallucination filtering
but cannot disable silent-loss detection.

Diagnostics now record the lexical coverage end, trailing speech-like frames
and fraction, whether transcription retried, and integrity reason codes on
both success and recoverable failure. The recovery message explicitly states
when Groq returned incomplete text twice.

## Recurrence repair

The follow-up repair removes provider segments from lexical completeness
decisions entirely:

1. compare every returned word token with the canonical provider text before
   discarding malformed timing metadata;
2. when those tokens align, compute coverage from only finite,
   positive-duration word ends;
3. preserve usable word boundaries even when one aligned word has malformed
   timing;
4. never use an acoustic segment end as a lexical fallback; and
5. retain the existing fail-open behavior when no trustworthy word boundary is
   available rather than inventing coverage from unrelated metadata.

The regression fixture matches the recurrence topology: a full-duration
nonempty segment, complete word-token alignment, one zero-duration word, local
speech beyond the final valid word end, and a complete prompt-free retry. The
old implementation delivers the partial first response; the repaired
implementation retries it.

The subsequent internal-omission repair also scans meaningful gaps between
consecutive provider word timestamps against the already-computed local VAD
timeline. Sustained speech inside a provider lexical gap makes the response
suspicious even when a later returned word reaches the end of the audio. The
same one-retry/recoverable-failure rule then applies; no additional provider
call is introduced for healthy responses.

## Alternate recovery repair

The approved recurrence repair keeps the healthy path unchanged at one
complete-file request and changes only the experimental coverage path:

1. internal provider-word-gap and tail-speech coverage decisions run only in
   Enhanced — Experimental;
2. Off and Basic preserve usable provider text and do not spend another call
   on timestamp-gap suspicion;
3. an Enhanced missing-coverage result spends the one provider-recovery
   allowance on immediate approximately 30-second pieces with 1.5-second
   overlap, submitted with a concurrency ceiling of four;
4. every expected piece must return before canonical top-level text is
   overlap-deduplicated and timestamp evidence is offset;
5. an optional local fallback interface can supply a final candidate without
   making local transcription a required packaged dependency;
6. if every candidate remains uncertain, the best nonempty candidate and
   original M4A are retained as a visibly labeled Recent Transcript; and
7. uncertain recovery text is not inserted, registered as a Voice v2 intent,
   uploaded to D1/R2, or presented as an ordinary success.

The best-candidate rule remains safety-scoped: a candidate must be nonempty,
must include the missing-speech-coverage signal, and must not contain prompt
leakage or known hallucination boilerplate. Other incompleteness diagnostics
may remain on the visibly uncertain preview because preserving partial user
text is safer than silently discarding it; none of those candidates is inserted
or delivered automatically.

Implementation ownership is split deliberately: alternate provider windows
and request concurrency live in
`Sources/InterviewArcVoiceCore/GroqTranscriber.swift`; integrity decisions,
fallback orchestration, and candidate selection live in
`Sources/InterviewArcVoiceCore/IntegrityMonitoring.swift`; local retention and
trusted replacement live in `Sources/InterviewArcVoiceCore/TranscriptRecovery.swift`
and `Sources/InterviewArcVoice/InterviewArcVoiceApp.swift`. Regression coverage
is in `AudioChunkerTests.swift`, `IntegrityMonitorTests.swift`, and
`TranscriptRecoveryPolicyTests.swift`.

## Regression prevention

- Production-shaped test: full-duration response with complete partial-word
  alignment plus an empty trailing segment.
- Recurrence-shaped test: one malformed aligned word timestamp plus a
  full-duration nonempty segment must not suppress the lexical-tail retry.
- Enhanced internal-gap test: sustained local speech between provider word
  timestamps must trigger the alternate overlapping-window recovery even when
  the final word timestamp reaches the recording tail.
- Basic-mode test: the same timestamp topology remains one provider call and
  does not reject usable text.
- Failure test: two coverage-uncertain candidates preserve the best usable text
  and original audio locally while retaining timing and integrity evidence.
- Recovery-window test: approximately 30-second windows overlap by 1.5 seconds
  and assemble without duplicating the boundary words.
- Existing complete-transcript and sparse-timestamp cases continue to fail
  open rather than rejecting trustworthy text.
- Off and Basic continue to enforce structural failures but do not run the
  experimental timestamp-gap veto.
- Reliability release requires the exact merged-main package and installed-app
  verification; merge and CI alone do not close issue #123.

## Previous merged-release verification (superseded by recurrence)

- Production evidence boundary inspection confirmed both original recordings
  were complete before implementation.
- Every changed Swift source and test file passed the parser check, and
  `git diff --check`, artifact-promotion policy, signing policy, and the public
  safety audit passed.
- The authoritative pull-request workflow passed in 1 minute 40 seconds,
  including the complete Swift test suite and package build. All configured
  quality, security, dependency, duplication, and coverage gates passed.
- Pull request #136 merged as `58b30a1908a7433cbc4952d1f20ab63bf42e8b62`.
- Because another mainline change preceded the merge, the main workflow
  correctly rejected PR-artifact promotion and rebuilt the combined merged
  tree `d275b7ed665f708971ef5657153b3e628556b0fb`. Workflow run
  `30715292109` passed in 2 minutes 33 seconds.
- The downloaded artifact's provenance manifest matched that merge commit,
  tree, workflow run, and `push` event. Its package self-check found all 21
  bundled vocabulary packs.
- The artifact was signed with the existing stable local identity, launched
  from temporary staging, then installed. The staged and installed executable
  SHA-256 values matched exactly:
  `5112132e6bd0dd79e86625529bcef2eb312750aff61cd4924b92d79961f161c0`.
- The installed application launched successfully, retained its existing
  Keychain-backed settings, exposed the recorder controls, and kept the
  preserved 46.78-second recovery recording complete and decodable.

The provider's exact empty-trailing-segment response is nondeterministic and
cannot be requested from the live API on demand. The merged release therefore
verifies that response shape with the production-shaped deterministic fixture,
while installed-app verification covers package identity, startup, retained
state, credentials, recorder availability, and recovery evidence. A future
provider response that remains partial after the single automatic retry will
now fail visibly and preserve the recording instead of being delivered.

This verification proved artifact provenance and the empty-segment fixture,
but it did not cover the later malformed-word/nonempty-segment response shape.
It is therefore not final verification for issue #123. The recurrence repair
requires a new canonical workflow, exact merged-main artifact installation,
and a fresh long-dictation acceptance check before closure.

## Lessons

Provider processing duration, timestamp coverage, and lexical coverage are
different signals. Integrity checks must tie timing evidence to actual
canonical text before using it to prove completeness.
