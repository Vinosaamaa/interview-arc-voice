# Intermittent silent microphone stream during active recording

**Date:** 2026-07-26
**Severity:** Reliability / user-data risk
**Status:** Released and installed; natural recurrence monitoring remains
**Issue:** #58
**PR:** #61 and #65

## Summary

Interview Arc Voice could enter its recording state, advance the clock, and
produce a valid M4A timeline while receiving effectively no microphone payload.
The failure was intermittent and was followed by healthy recordings from the
same installed application. Because the UI looked active, a user could speak
for several seconds before learning at finalization that no usable answer had
been captured.

## Impact

- Spoken content during an affected capture was not recoverable.
- The failure looked like user silence or mute even though the recording state
  was active.
- Post-capture integrity checks prevented false transcription/upload, but they
  detected the loss only after the user stopped.

No affected audio or transcript was uploaded. Existing integrity gates rejected
the silent files.

## Evidence

Preserved application recordings included multiple 3–8 second M4As with only
204–488 encoded audio bytes (about 500 bits/second), while later recordings
from the same app instance encoded at roughly 30–36 kilobits/second. This rules
out a merely hidden waveform: the recorder had a valid container timeline but
the selected input stream delivered no meaningful signal.

The app did not record input-route transition telemetry, so a Bluetooth or
default-input profile transition is the leading hypothesis rather than a
proven root cause.

### Recurrence

The installed release later entered the same `NO MICROPHONE SIGNAL` state.
A subsequent capture could succeed, preserving the intermittent
classification and proving that permanent microphone permission denial was
not the cause. Source inspection established that the first remediation
stopped `AVAudioRecorder` and immediately created another
`AVAudioRecorder` with identical settings. The retry could therefore reacquire
the same stalled Core Audio route and was not an independent recovery path.

## Detection gap

The app already measured live input level and changed `signalHealth` to absent
after 2.5 seconds. That signal was used for a warning and final integrity
evaluation only. It did not attempt to reopen a stream that had started on a
dead route.

## Root cause

The initial immediate software cause was a missing recovery transition:

1. `AVAudioRecorder.record()` returned success.
2. The app therefore entered the recording state.
3. Metering remained below the plausible-speech threshold.
4. The app retained the original recorder until Stop instead of rebuilding it.

The underlying platform trigger is most likely an input-device/profile
transition around recorder startup, but the prior implementation did not log
enough route identity to distinguish Bluetooth profile changes, device
replacement, and a transient Core Audio stream failure.

The recurrence exposed a second software cause: the recovery transition reused
the same capture backend immediately. It changed the recorder object without
changing the boundary that had failed.

## Remediation

- Add one controlled automatic recovery when the live signal remains absent
  beyond the warm-up interval.
- Make recovery cross an implementation boundary: start an `AVAudioEngine`
  input tap using the active hardware format before releasing the stalled
  `AVAudioRecorder`.
- Do not enable the Voice Processing input unit in the recovery backend. A
  prior voice-processing engine path could start without delivering writable
  frames.
- Replace the destination only after the independent backend starts; preserve
  the initial file if fallback startup itself fails.
- Preserve the user-facing elapsed clock across the restart.
- Reset only signal-attempt metering/history so the replacement stream receives
  a fresh warm-up window.
- Never loop: a second absent stream remains a visible failure.
- Refresh and retain the selected input-device name for diagnosis.
- Keep post-capture file, decoded-frame, bitrate, and local speech checks as a
  second independent layer.

## Why one recovery

A single cross-backend recovery addresses a transient dead stream without
creating a hidden infinite loop or repeatedly discarding intentional silence.
If the user waits silently at the beginning, the replacement stream remains
ready for later speech. If the device is truly muted or unavailable, the
second attempt fails visibly.

## Verification

Completed:

- Unit policy: absent signal restarts at count zero, never after count one, and
  never for a detected signal.
- Parser validation for all application and core Swift sources.
- CI Swift test, release package, signature, and resource validation.
- Staged and installed exact-artifact capture plus waveform smoke.
- Production protocol-v2 destination-gating check.

Not deliberately induced during release verification:

- switching between built-in and headset microphones during an active capture;
- forcing a Core Audio first-stream failure in the signed app; or
- changing the user's current Bluetooth route and volume state.

## Released-package verification

PR #61 merged as `dee34619761df01fba563be8f843379e8ac5d800`.
Merged-main workflow `30220192661` passed the complete Swift test and package
job. The downloaded application passed strict code-signature and package
resource verification. Its executable SHA-256 was:

`6da4310d6ee9f136c64aff854f8902619644e734e1d2e64bb67ca3f44ce0ff07`

That exact artifact was first launched from a temporary staging directory, then
installed at `~/Applications/Interview Arc Voice.app`. The installed executable
matched the staged hash exactly. The installed widget completed a real capture
cycle, rendered the new fine waveform without changing capsule geometry, and
returned to its compact timer state after Stop. Because the test began outside
Codex, it correctly used general dictation and the authenticated production
protocol-v2 endpoint remained at zero pending intents afterward.

The test did not deliberately disrupt the user's active microphone route or
create a synthetic linked practice turn. The bounded dead-stream restart is
therefore verified by deterministic policy coverage and the packaged recording
path, while the next naturally occurring input transition remains useful
observational evidence for the platform-level trigger hypothesis.

The independent-backend follow-up shipped in PR #65 as merge commit
`5c2385f98aa4c14f44a4ebad85bbc7865098ab14`. Merged-main workflow
`30222283280` passed the complete Swift test and signed-package job. PR #66
subsequently hardened Keychain access without changing the capture repair;
workflow `30222739145` also passed.

The exact artifact downloaded from workflow `30222739145` was staged and then
installed at `~/Applications/Interview Arc Voice.app`. The staged and installed
executables had the same SHA-256:

`3bb963d610bde598e6a1ede0f20ad8fcbfef127178279aa20d6c7ad1570f09fa`

The installed app loaded both saved credentials in the normal user context,
restored the focused Interview Arc activity, and completed a real general-
dictation capture cycle. During recording, the signed app displayed the
one-point waveform across the available interval and returned to the compact
state after Stop. The smoke test did not change the active practice timer or
assign an activity result.

The release test did not deliberately force Core Audio to return a dead first
stream. That failure mode is covered deterministically by the one-recovery
policy and the independent `AVAudioEngine` fallback path; the next naturally
occurring route transition remains observational verification of the platform
trigger.

## Second recurrence: live UI preceded microphone readiness

On 2026-07-27 the user observed a narrower but still destructive form of the
same incident: after pressing Record with AirPods, Voice immediately displayed
the red live state while the first approximately one to three seconds contained
no useful microphone signal. Input then appeared after the Bluetooth profile
finished changing.

The earlier repair detected and replaced a stream that stayed silent for 2.5
seconds, but the product still equated `AVAudioRecorder.record()` returning
`true` with user-visible readiness. That API confirms that recording was
requested; it does not confirm that Bluetooth has completed the A2DP-to-
hands-free transition or that useful input is arriving. The design therefore
allowed users to speak into a UI that claimed to be live before the hardware
boundary was ready. Post-capture integrity checks and the independent fallback
could reject or recover the stream later, but they could not recover words
spoken during the misleading startup interval.

The follow-up changes the contract:

1. Record first enters a visible **Preparing microphone** phase.
2. The destination file is already open, preserving the earliest usable
   pre-roll.
3. Bluetooth readiness requires the output profile to change away from its
   pre-recording route and remain stable, plus usable recorder input.
4. Only then does Voice expose the red Recording state and start its visible
   elapsed clock.
5. A bounded timeout crosses to the independent `AVAudioEngine` backend once;
   a second timeout fails visibly instead of claiming success.
6. Repeating the record command during preparation cancels it and removes the
   partial local file.

Issue #58 was reopened for this recurrence. Issue #78, created before this
incident history was rediscovered, was closed as a duplicate.

## Third recurrence: the readiness repair blocked on output state

The first follow-up repair was too strict. It required the active Bluetooth
**output** profile to differ from its pre-recording signature and remain stable
for 0.6 seconds. On the affected Mac, Core Audio could retain the same logical
route identity, briefly flap between observable profiles, or expose a usable
microphone before the output signature changed.

That turned a diagnostic proxy into a blocking product dependency:

- a usable recorder could remain stuck in Preparing microphone;
- after four seconds, Voice unnecessarily opened the independent fallback;
- the fallback could trigger another profile transition and then wait another
  two seconds before failing;
- the user observed repeated switching and a new failure mode that did not
  exist before the readiness gate.

The corrective rule is narrower: microphone startup becomes live as soon as
the selected capture backend advances. It never waits for output-route
identity, a fixed 0.6-second stabilization interval, ambient noise, or speech.
The independent fallback remains bounded and is used only when the primary
backend itself does not advance. Existing post-start signal health and
finalized-file integrity checks remain responsible for detecting a genuinely
silent or invalid stream without delaying every healthy recording.

## Follow-up

- Add explicit default-input route-change telemetry with device identity before
  and after recovery.
- Add a deterministic fault-injection seam so packaged UI testing can simulate
  a recorder that starts successfully but reports no signal.
- Track recovery count in diagnostic export without storing transcript or audio
  content.

## Fourth recurrence: the independent fallback also stayed silent

On 2026-07-29 the installed application again reported **No microphone
signal** / **Recording ended early** while the system still identified the
AirPods Max as the default 24 kHz input. The first bounded repair was active,
but it could not recover this instance.

The remaining state-machine gap was deterministic. Voice allowed one automatic
restart:

1. the primary `AVAudioRecorder` stream stayed silent;
2. Voice switched to an independent `AVAudioEngine` input tap; and
3. if that engine bound before the Bluetooth route became viable,
   `maximumAutomaticRestarts == 1` prohibited any later rebind.

The UI could therefore remain attached to the dead fallback until Stop. The
same route-transition interval also contributed to the whole-capture
hallucination recurrence tracked by reopened issue #33.

The repair permits exactly one final bounded rebind. When the first engine
fallback also remains silent for the normal 2.5-second signal window, Voice
stops and releases that engine and tap before constructing a fresh input node
and destination. It never runs two input engines concurrently, never loops
beyond two recovery transitions, preserves the capture identity and routing
destination, and retains the last finalized local evidence if the final rebind
cannot start.

Review of the first draft exposed a second state-machine defect before release:
the periodic recovery decision was guarded by the presence of the original
system recorder. That recorder is intentionally removed after the first
fallback, so the final rebind would have been unreachable. The recovery policy
now receives an explicit active-backend state, and the timer evaluates both the
system recorder and audio-engine fallback.

Privacy-safe diagnostics now include the microphone recovery-attempt count.
They continue to exclude device names, transcript text, audio, credentials,
tokens, and private URLs. Regression coverage requires restart decisions
`true, true, false` for completed recovery counts `0, 1, 2`.

Issue #58 remains the canonical microphone incident. Final merged-main package,
AirPods verification, executable hash, and rollback location are recorded in
its resolution history after release.

## Fifth recurrence: transition audio passed whole-capture admission

The two-transition recovery state machine shipped through PR #97 and passed
CI, signature checks, package checks, and one staged silent capture. A second
silent capture using the exact same executable after installation nevertheless
reached Groq and delivered a known two-word hallucination.

The capture-backend repair remained present: Voice still bounded recovery to
the primary recorder, one engine fallback, and one clean engine rebind. The
remaining failure was downstream. The hand-built whole-capture speech
heuristic treated a longer AirPods/profile-transition artifact as sustained
speech. Once that gate passed, provider confidence and complete two-word
alignment could not prove that the input was non-speech.

The follow-up preserves the recovery state machine and adds an independent
WebRTC VAD requirement before any provider call. The decoded mono audio is
resampled to 16 kHz, inspected in 20 ms frames, and must contain a sustained
VAD-positive run. The preexisting energy/zero-crossing/crest heuristic remains
the second required gate and continues to own Enhanced timestamp-local
evidence. Either detector failing rejects locally. Diagnostics add only
privacy-safe VAD frame/run counts.

Deterministic coverage includes silence, hum, isolated clicks, a modeled short
Bluetooth transition, soft short speech, and speech at the AirPods 24 kHz
fallback rate. Release completion still requires the exact merged-main signed
artifact to pass both a silent AirPods capture with zero provider wait and a
genuine short spoken AirPods capture. Until then, issues #58 and #33 remain
open.

## Sixth recurrence: switched input preserved only a playable prefix

On 2026-08-03 a recording made immediately after changing microphone input
ran for 8 seconds but finalized with 5 seconds of decodable audio. The payload
was neither empty nor silent: it averaged 51,394 bits per second and peaked at
-17.4 dB. The integrity evaluator correctly reported `durationMismatch`, but
the recovery policy treated every incomplete-but-playable file as preservation
without retranscription. The failure card therefore offered only Record again,
Play, and Save even though the 5-second prefix was transcribable.

The missing 3 seconds cannot be reconstructed, so Voice must not describe the
prefix as a complete answer. The recovery action now exposes **Retry
transcription** explicitly and labels it as partial, while retaining Record
again, Play, and Save. It does not automatically retry or silently discard the
preserved recording. A deterministic 8-second/5-second fixture prevents this
recovery-policy gap from returning.
