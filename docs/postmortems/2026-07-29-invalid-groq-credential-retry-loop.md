# Invalid Groq credential exposed a recording retry loop

## Summary

On July 29, 2026, Interview Arc Voice finalized recordings correctly but could
not transcribe them because Groq rejected the saved API key with HTTP 401.
Voice presented the failure as an ordinary retryable transcription error.
Repeated **Retry transcription** actions therefore resubmitted the same
protected recording even though the credential was already known to be
invalid.

Issues: [#87](https://github.com/Vinosaamaa/interview-arc-voice/issues/87) and
[#88](https://github.com/Vinosaamaa/interview-arc-voice/issues/88).

## User impact

- New recordings produced no transcript.
- The audio was preserved, so there was no confirmed recording loss.
- The failure UI encouraged retries that could not succeed with the same key.
- Menu-bar transcript reinsertion was independently unreliable, making manual
  recovery harder than the floating-widget path.
- The first repair persisted the failure notice but not its recoverable-audio
  reference. After relaunch, the notice still advertised Settings, Play, and
  Save even though those menu actions had no live target.

No credential, transcript text, or raw audio is included in this document.

## Detection and evidence

The installed app's bounded diagnostics showed:

- finalized recordings with valid decoded duration;
- local integrity and speech scans completing;
- `providerWaitSeconds = 0`;
- repeated failed attempts against the same 61.4-second protected recording.

The protected local failure notice identified Groq HTTP 401 `Invalid API Key`.
This proves the active incident occurred before provider transcription rather
than during recording, cursor insertion, or Interview Arc delivery.

Follow-up installed-app testing showed that the protected M4A still existed in
Application Support while the relaunched process had `hasLastAudio = false`.
Source inspection also showed that the menu recovery card's Open Settings
button changed an unused disclosure Boolean instead of invoking the native
Settings presenter.

## Timeline

- Earlier July 29 captures completed normally.
- At approximately 1:37 PM Pacific, retries began failing before provider wait.
- At approximately 1:40 PM Pacific, the installed app retained the explicit
  Groq 401 failure.
- Investigation classified the issue as Reliability and opened #87 and #88.
- After the first merged artifact was installed, recovery-action testing found
  that Settings, Play, and Save were nonfunctional after relaunch. Issue #87
  remained open and received the follow-up evidence rather than being closed.
- Staged verification of the first recovery-action follow-up proved Settings
  and Save, then caught Play still failing specifically through the anchored
  popover. Direct playback worked, isolating a self-cancelling fallback task in
  the popover-dismissal handoff before that artifact was installed.

## Root cause

`GroqTranscriber` converted every non-2xx response into the same generic
`invalidResponse` error. The app could not distinguish a permanently rejected
credential from a transient provider or network failure. Its generic
transcription recovery state retained **Retry transcription**, so the same
preserved recording could be submitted repeatedly with the same rejected key.

The menu-bar insertion path also recomputed its target from the current
frontmost application. That is unsafe after opening a status-item window,
because the editor that owned the cursor may no longer be the frontmost
eligible application. The non-activating floating widget did not have this
focus transition, explaining why its insertion path worked.

The recovery notice was persisted independently from its in-memory audio
payload and URL. Relaunch therefore reconstructed the action list but not the
state those actions required. In addition, menu recovery reused the model-only
Open Settings action intended for a disclosure path that no longer owned a
visible Settings surface.

## Contributing factors

- Settings verified only that the Keychain value was persisted, not that Groq
  accepted it.
- Diagnostics intentionally contain timing rather than error text, so the 401
  was visible only in the protected failure notice.
- The app had no bounded local transcript history, leaving one transcript card
  as the main manual recovery surface.

## Resolution

- Map Groq 401/403 to a dedicated invalid-provider-credential error.
- Persist a non-secret rejection state, preserve audio, and disable Record and
  Retry until a different key is saved.
- Keep transient provider failures retryable.
- Make manual insertion surface-aware: menu insertion prefers the remembered
  external editor; floating insertion prefers the current eligible editor.
- Retain five transcript-only recovery records for 24 hours in a permission
  `0600` file with bounded navigation in the existing popover.
- Persist and validate one recoverable-recording reference, rehydrate it before
  exposing Play/Save after relaunch, and migrate the currently preserved audio
  once when no reference exists.
- Route menu recovery Settings through the native foreground presenter and
  explicitly foreground the native Save panel.
- Keep the popover-close notification as the preferred playback handoff, but
  ensure the bounded fallback never cancels its own task before executing the
  queued recovery action.

## Regression prevention

- Policy tests cover provider-auth classification and rejected-key replacement.
- Target-selection tests distinguish menu and floating surfaces.
- Store tests cover ordering, five-record bounds, 24-hour expiry, and file
  permissions.
- Recovery-store tests cover relaunch hydration, `0600` metadata permissions,
  missing/unsafe-path rejection, and bounded newest-audio migration.
- The release must repeat recording/transcription and menu insertion with the
  exact installed artifact produced from merged `main`.

## Release verification

Pending PR, merge, packaged-artifact installation, and valid-key production
verification.

## Known limitation

Voice cannot manufacture or recover a valid third-party Groq credential. The
user must provide a valid replacement key. The app's responsibility is to
preserve work, stop futile retries, and make that required action explicit.

## Technical glossary

- **Provider wait:** Time spent uploading audio and waiting for Groq.
- **Protected recording:** Finalized local audio retained for Play, Save, or a
  later explicit retry.
- **Non-retryable:** A failure that cannot succeed without a state change such
  as replacing a rejected credential.
- **Insertion target:** The external application and focused editor that should
  receive recovered transcript text.
