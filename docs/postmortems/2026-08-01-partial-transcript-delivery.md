# Postmortem: Partial transcript delivered while speech remained in the recording

**Date**: 2026-08-01  
**Status**: Final<br>
**Severity**: P0 silent data loss  
**Issue**: [interview-arc-voice#123](https://github.com/Vinosaamaa/interview-arc-voice/issues/123)  
**Pull request**: [interview-arc-voice#136](https://github.com/Vinosaamaa/interview-arc-voice/pull/136)

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
- A separate clear 46.78-second recording was rejected safely, but the original
  attempt and two manual retries all displayed the same generic failure while
  diagnostics falsely reported zero provider time.

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

### Contributing factors

- Provider top-level duration described processed audio, not lexical coverage.
- The integrity evaluator correctly preserved sparse timestamp results but did
  not distinguish complete lexical alignment from empty trailing metadata.
- The first issue remained open and had not completed merged-main installed
  verification against the recurrence shape.
- The failure boundary discarded both provider timing and integrity context,
  making an executed retry look like a dead control and a zero-millisecond
  provider call.

## Resolution

The repair:

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

## Regression prevention

- Production-shaped test: full-duration response with complete partial-word
  alignment plus an empty trailing segment.
- Failure test: two partial results must throw `missingSpeechCoverage` after
  exactly two provider calls while retaining their combined timing and tail
  evidence for diagnostics.
- Existing complete-transcript and sparse-timestamp cases continue to fail
  open rather than rejecting trustworthy text.
- The production-shaped tail test runs with Silence Protection Off, proving
  the P0 completeness guard does not depend on that preference.
- Reliability release requires the exact merged-main package and installed-app
  verification; merge and CI alone do not close issue #123.

## Merged-release verification

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

## Lessons

Provider processing duration, timestamp coverage, and lexical coverage are
different signals. Integrity checks must tie timing evidence to actual
canonical text before using it to prove completeness.
