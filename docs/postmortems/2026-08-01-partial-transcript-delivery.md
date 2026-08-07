# Postmortem: Partial transcript delivered while speech remained in the recording

**Date**: 2026-08-01  
**Status**: Reopened — cold local fallback caused prolonged foreground failure<br>
**Severity**: P0 silent data loss  
**Issue**: [interview-arc-voice#123](https://github.com/Vinosaamaa/interview-arc-voice/issues/123)  
**Pull requests**: [interview-arc-voice#136](https://github.com/Vinosaamaa/interview-arc-voice/pull/136), [interview-arc-voice#147](https://github.com/Vinosaamaa/interview-arc-voice/pull/147)

> **Recurrence update:** The exact #136/#140 installed artifact delivered a
> second incomplete 80.89-second transcript on 2026-08-01. The follow-up root
> cause was a malformed provider word timestamp combined with an unsafe
> nonempty-segment fallback. Pull request #147 added alternate overlapping
> recovery and safe uncertain-result preservation; its exact merged-main
> artifact completed installed verification on 2026-08-02.
>
> **Second recurrence:** An approximately 87-second installed-app capture on
> 2026-08-02 completed Groq in 1.868 seconds and local decoding in 1.801
> seconds, yet the foreground path lasted 42.076 seconds before failing. Source
> inspection showed that WhisperKit model loading and prewarming happened
> synchronously before the recorded local-inference timer. Both nonempty
> candidates then remained coverage-uncertain. The user therefore paid a
> roughly 38-second unreported cold-start cost without receiving ordinary
> output.

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
- 2026-08-02 — Pull request #147 passed the canonical macOS workflow and all
  configured quality gates. Main promoted the exact tested tree-addressed
  artifact instead of rebuilding it.
- 2026-08-02 00:13 — The promoted artifact passed package, signature, hash,
  single-process, and installed-widget verification. Issue #123 was resolved.

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
6. if every provider candidate remains uncertain, the best nonempty candidate
   is inserted immediately with a quiet **May be incomplete** warning and the
   original M4A is retained; and
7. a linked best-provider candidate follows the ordinary protocol-v2 envelope,
   specialist decision, D1, and R2 lifecycle exactly once.

The best-candidate rule remains safety-scoped: a candidate must be nonempty,
must include the missing-speech-coverage signal, and must not contain prompt
leakage or known hallucination boilerplate. Other incompleteness diagnostics
may remain on the visibly uncertain result because preserving partial user text
is safer than silently discarding it. This bounded provider path is distinct
from a legacy recovery record whose user must still explicitly choose
**Use this transcript**.

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
It is therefore not final verification for issue #123.

## Superseded alternate-recovery verification

This verification finalized the alternate provider-recovery repair in pull
request #147. It remains valid for that response topology, but it did not cover
the later cold-start latency recurrence and is therefore no longer the final
closure evidence for this reopened incident.

- Two retained long recordings reproduced the failure across three whole-file
  Groq submissions each. The provider timestamp JSON changed between runs, but
  each recording's canonical whole-file text repeated the same omission.
- Immediate approximately 30-second pieces with 1.5-second overlap produced
  materially different candidates, establishing a recovery topology that did
  not repeat the failed whole-file request shape.
- Pull request #147's final canonical workflow run `30736692244` passed in
  2 minutes 37 seconds, including all 191 tests and the package build. All
  configured quality, security, dependency, duplication, and coverage gates
  passed.
- The final PR artifact recorded Git tree
  `22f88872ecbfeafd9e06e18ce2b8f3363dacf01a`.
- Main workflow run `30737035142` verified the same tree and promoted that
  exact artifact from PR run `30736692244`; it did not rebuild the app.
- The promoted package passed its 21-vocabulary-pack self-check and strict
  code-signature validation. Its staged and installed executable SHA-256
  values matched exactly:
  `32731b05cb86e571408d3b4ee7010eb730bc54965d686a235798844f1af763da`.
- Exactly one process remained active from the installed Applications copy,
  and the floating widget was responsive with the expected general-dictation,
  memo-action, planner, and recording controls.

## Native local-fallback follow-up

Issue [#151](https://github.com/Vinosaamaa/interview-arc-voice/issues/151)
closes the remaining packaged-app gap without changing the healthy path:

- Settings can explicitly install, inspect, or delete the supported `base.en`
  WhisperKit model; Voice never downloads it automatically.
- A permission-0600, SHA-256 file manifest in private app-owned storage detects
  missing, changed, symlinked, or incompatible model files across relaunch.
- General and initial linked transcription pipelines receive the production
  local fallback, but invoke it only after the normal whole-file Groq request
  and bounded overlapping Groq recovery both remain coverage-uncertain.
- Local output passes the same integrity and silence-protection policy. A still
  uncertain result preserves the original M4A and best candidate rather than
  inventing success.
- Local decoding receives the same resolved vocabulary context as the primary
  request, normalized and bounded to 180 actual tokenizer tokens. The adapter
  previously accepted a prompt argument but dropped it, while the integrity
  fallback explicitly supplied an empty prompt; regression tests now cover
  both boundaries.
- Diagnostics record engine, model, inference duration, local attempt,
  conditioning presence/token count, and privacy-safe result codes without
  prompt, transcript, or audio content.
- Cancellation is checked before model loading and after inference; a missing
  or corrupt model leaves the existing recovery candidate actionable.
- The signed app packages an aggregate-only native verifier so retained local
  failures can be replayed through the exact installed WhisperKit runtime. Its
  output excludes transcript, prompt, audio, and path content, making numeric
  coverage evidence safe to summarize in release verification without exposing
  private recordings.

The local model remains an optional recovery capability, not a replacement for
Groq and not a dependency on a developer Python environment. Final closure of
#151 requires the exact merged-main signed artifact, staged and installed, plus
the repository-owned synthetic coverage fixture. Until then this section is an
implemented-local, release-verification-pending follow-up.

## Explicit uncertain-candidate promotion

Issue [#150](https://github.com/Vinosaamaa/interview-arc-voice/issues/150)
adds the deliberate recovery action for legacy discrepancy records that were
preserved before the bounded best-provider path. **Use this transcript** always
asks for confirmation and uses the exact visible recovered text plus the
retained original M4A. General Dictation stays local. A linked candidate
atomically persists one stable capture/turn/clip
identity from the activity context frozen when recording began, inserts the
ordinary Voice v2 envelope, and then waits for the specialist's normal
related/unrelated/uncertain decision. Repeated confirmation, relaunch, Insert
Again, and registration retry reuse that identity; confirmation never uploads
to D1/R2 or marks the capture related by itself.

## Cold-start recurrence and bounded foreground repair

The second recurrence was not slow provider inference. The aggregate timing
made Groq and local decoding visible but started the local timer only after
WhisperKit had loaded and prewarmed the installed model. On the first fallback
after launch, that unmeasured preparation took roughly 38 seconds. The
foreground orchestration then rejected the nonempty local result for the same
experimental coverage signal and reported failure.

The follow-up repair changes the ownership of model preparation and latency:

1. an installed model prewarms asynchronously after the app has presented its
   local UI and loaded secure settings;
2. readiness is exposed through a lock-protected nonisolated snapshot, so a
   foreground check never queues behind an in-progress model load;
3. local recovery runs only when the engine is already warm; otherwise Voice
   immediately preserves the best eligible provider candidate and original
   M4A as coverage-uncertain;
4. primary provider requests have a 20-second total request-transport bound and
   the much smaller approximately 30-second alternate-recovery uploads have an
   8-second total request-transport bound instead of the previous 300-second
   request timeout; and
5. privacy-safe diagnostics explicitly report when local recovery was skipped
   because the model was not warm.

Settings exposes this runtime distinction directly. An installed model reports
**Preparing local recovery…** until prewarm finishes, then **Ready for immediate
recovery**. A failed preparation remains visibly installed but not ready and
offers an explicit **Prepare** retry, so model presence can no longer be
mistaken for foreground readiness.

This does not weaken the trust boundary. A legacy discrepancy record still
requires explicit **Use this transcript** confirmation. The bounded
best-provider candidate described below is an ordinary inserted result with a
visible warning and, when linked, the ordinary specialist decision and D1/R2
lifecycle. Exact merged-main package and installed-app verification remain
pending for this reopened incident.

## 2026-08-03 bounded best-provider-candidate decision

Installed and retained-recording comparisons showed that automatic native
local fallback did not consistently improve provider coverage: across the
bounded Recent Transcript sample, `base.en` produced more words in seven
records, the same count in six, and fewer words in seven. Its median inference
was about 1.1 seconds, but cold preparation had already produced a roughly
38-second foreground stall. The native model therefore remains an explicit
diagnostic/recovery capability rather than an automatic foreground dependency.

The approved foreground path is now:

1. send the ordinary provider request;
2. when Enhanced detects missing speech coverage, immediately request the
   existing overlapping approximately 30-second provider windows;
3. select the longest eligible nonempty provider candidate deterministically;
4. insert it without a blocking confirmation and retain the original M4A; and
5. show a quiet **May be incomplete** warning in the widget and Recent
   Transcripts.

A linked uncertain candidate must still create exactly one ordinary protocol-v2
envelope with stable capture and turn identifiers. It follows the same
specialist decision, D1, and R2 lifecycle as any other linked recording; the
warning does not bypass classification or duplicate delivery. Empty text,
no-speech, recording failure, and provider authentication failure remain
blocking states.

## Lessons

Provider processing duration, timestamp coverage, and lexical coverage are
different signals. Integrity checks must tie timing evidence to actual
canonical text before using it to prove completeness.

## 2026-08-03 merged release verification

PR #164 merged as `8b54e93e21f581691966829df01b26a3f253b6cd`.
Canonical macOS run 30801061950 passed in 4m09s, and protected-main run
30801556050 promoted the exact tree-equivalent artifact without rebuilding.
The promoted package passed its 21-pack self-check, was signed with the stable
local identity, installed, launched, and matched the staged signed executable.

Regression coverage proves deterministic longest-candidate selection, bounded
overlapping provider recovery, immediate General Dictation delivery, one
stable linked Voice envelope, retained uncertainty state/audio, and unchanged
blocking behavior for empty, no-speech, and authentication failures. The
installed app is recording-ready and its approved Warp/tmux target is verified.
A naturally occurring installed coverage-uncertain capture remains the final
product-level evidence for the quiet warning and linked envelope path; no
private recording is rewritten to manufacture that state.

## 2026-08-06 prompt-leakage recurrence

A retained ten-minute linked recording produced nonempty initial and retry
transcripts, but both candidates carried `missingSpeechCoverage` and
`promptLeakage`. The best-candidate predicate admitted coverage uncertainty
only when prompt leakage was absent, so Voice discarded all reviewable text
and presented a hard failure. The original audio remained protected.

The containment for issue #179 broadens only that existing recovery boundary:
a nonempty candidate is eligible when all of its integrity reasons are
`missingSpeechCoverage`, `promptLeakage`, or both. Empty output, no-speech,
missing chunks, provider-duration mismatch, and other recording failures still
fail closed. Candidate ranking, one-time insertion, stable linked identity,
audio retention, and the existing uncertainty warning remain unchanged.

A separate six-minute recording observed during recovery contained only one
short spoken fragment followed by a near-empty AAC payload. No transcription
policy can reconstruct speech that was not recorded; that evidence remains a
recording-input failure and is not used to justify weakening the no-speech or
audio-integrity gates.
