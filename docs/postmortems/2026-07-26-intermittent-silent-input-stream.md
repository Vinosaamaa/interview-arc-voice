# Intermittent silent microphone stream during active recording

**Date:** 2026-07-26
**Severity:** Reliability / user-data risk
**Status:** Released and installed verification complete
**Issue:** #58
**PR:** #61

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

## Detection gap

The app already measured live input level and changed `signalHealth` to absent
after 2.5 seconds. That signal was used for a warning and final integrity
evaluation only. It did not attempt to reopen a stream that had started on a
dead route.

## Root cause

The immediate software cause was a missing recovery transition:

1. `AVAudioRecorder.record()` returned success.
2. The app therefore entered the recording state.
3. Metering remained below the plausible-speech threshold.
4. The app retained the original recorder until Stop instead of rebuilding it.

The underlying platform trigger is most likely an input-device/profile
transition around recorder startup, but the prior implementation did not log
enough route identity to distinguish Bluetooth profile changes, device
replacement, and a transient Core Audio stream failure.

## Remediation

- Add one controlled automatic recorder restart when the live signal remains
  absent beyond the warm-up interval.
- Preserve the user-facing elapsed clock across the restart.
- Reset only signal-attempt metering/history so the replacement stream receives
  a fresh warm-up window.
- Never loop: a second absent stream remains a visible failure.
- Refresh and retain the selected input-device name for diagnosis.
- Keep post-capture file, decoded-frame, bitrate, and local speech checks as a
  second independent layer.

## Why one retry

A single retry addresses a transient dead stream without creating a hidden
infinite loop or repeatedly discarding intentional silence. If the user waits
silently at the beginning, the restarted stream remains ready for later speech.
If the device is truly muted or unavailable, the second attempt fails visibly.

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

## Follow-up

- Add explicit default-input route-change telemetry with device identity before
  and after recovery.
- Add a deterministic fault-injection seam so packaged UI testing can simulate
  a recorder that starts successfully but reports no signal.
- Track recovery count in diagnostic export without storing transcript or audio
  content.
