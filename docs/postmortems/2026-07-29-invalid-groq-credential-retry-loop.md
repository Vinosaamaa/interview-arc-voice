# Invalid Groq credential exposed a recording retry loop

## Summary

On July 29, 2026, Interview Arc Voice finalized recordings correctly but could
not transcribe them because Groq rejected the saved API key with HTTP 401.
Voice presented the failure as an ordinary retryable transcription error.
Repeated **Retry transcription** actions therefore resubmitted the same
protected recording even though the credential was already known to be
invalid.

Issues: [#87](https://github.com/Vinosaamaa/interview-arc-voice/issues/87),
[#88](https://github.com/Vinosaamaa/interview-arc-voice/issues/88), and the
August 2 follow-up
[#161](https://github.com/Vinosaamaa/interview-arc-voice/issues/161).

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
- A second staged test showed the deeper ordering race: AppKit could deliver
  `didClose` synchronously before the fallback was assigned. The close handler
  started playback, then the newly assigned fallback toggled it off 900 ms
  later. The fallback must be armed before dismissal so the close handler can
  cancel it.
- On August 2, a newly saved key worked and Voice later presented **Groq key
  rejected** again. The released client had discarded the provider status and
  safe error code after mapping both HTTP 401 and 403 into the same error, so
  the recurrence could not be classified conclusively after the fact.
- On August 3, the exact artifact containing the 401/403 classification repair
  again prompted for key replacement. Bounded diagnostics showed subsequent
  Groq captures succeeding, and current preferences no longer contained a
  rejection flag. Source inspection found that launch still promoted an older
  text-only `Request failed (401)` notice into a rejection of whichever key
  happened to be in Keychain at that later launch.

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

The first repair then introduced a distinct classification defect: it treated
Groq HTTP 401 and 403 as equivalent invalid credentials. HTTP 401 means the
request is not authenticated. HTTP 403 can mean an authenticated project is
not permitted to use the requested model. Collapsing both responses into a
hard credential rejection invalidated a possibly valid Keychain entry and
instructed the user to rotate a key even when project or model permissions
could be the required change. Because the response class and safe provider
error code were not retained in bounded diagnostics, the August 2 event lacked
the evidence needed to tell those cases apart.

The follow-up classification repair left one backward-migration path coupled
to human-readable failure text. It did not bind that historical failure to the
fingerprint of the credential that produced it. A replacement entered through
another Keychain-aware process, or legacy rejection state without a stored
fingerprint, could therefore be treated as though Groq had rejected the new
value. That stale-state promotion explains how the replacement prompt could
reappear even though later requests with the current credential succeeded.

## Contributing factors

- Settings verified only that the Keychain value was persisted, not that Groq
  accepted it.
- Diagnostics intentionally contain timing rather than error text, so the 401
  was visible only in the protected failure notice.
- The app had no bounded local transcript history, leaving one transcript card
  as the main manual recovery surface.

## Resolution

- Map Groq 401 to a dedicated invalid-provider-credential error.
- Map Groq 403 to a separate provider-permission error that preserves the key,
  disables futile automatic retries, and directs the user to project/model
  permissions.
- Record only the provider HTTP status and a bounded safe error identifier in
  diagnostics; never retain the response message, key, transcript, or audio in
  that diagnostic record.
- Persist a non-secret rejection state, preserve audio, and disable Record and
  automatic retry until a different key is saved.
- Preserve an explicit user-initiated Retry for the protected recording in the
  floating recovery popover and its matching Settings diagnostic. Persist the
  original linked/general destination so a retry after relaunch cannot guess
  its delivery semantics or create a duplicate linked turn.
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

- Policy tests cover 401 authentication rejection, 403 permission denial,
  retryable 429/5xx failures, and rejected-key replacement.
- Rejection reconciliation tests bind a persisted 401 to one credential
  fingerprint, clear it when Keychain contains a different nonempty value,
  allow one fresh provider check for legacy state without a fingerprint, and
  retain the rejection when the exact same key remains installed.
- Target-selection tests distinguish menu and floating surfaces.
- Store tests cover ordering, five-record bounds, 24-hour expiry, and file
  permissions.
- Recovery-store tests cover relaunch hydration, `0600` metadata permissions,
  original-destination restoration, missing/unsafe-path rejection, and bounded
  newest-audio migration.
- Settings renders all records retained by the existing 100-record diagnostic
  store instead of silently presenting only the newest five.
- The release must repeat recording/transcription and menu insertion with the
  exact installed artifact produced from merged `main`.

## Release verification

- The repair shipped through PRs
  [#90](https://github.com/Vinosaamaa/interview-arc-voice/pull/90),
  [#91](https://github.com/Vinosaamaa/interview-arc-voice/pull/91), and
  [#92](https://github.com/Vinosaamaa/interview-arc-voice/pull/92).
- Merged `main` commit
  `561905b104b5864d796d38bc8d195275060b6083` passed the canonical
  `Validate Interview Arc Voice` workflow in run
  [30497996457](https://github.com/Vinosaamaa/interview-arc-voice/actions/runs/30497996457).
- The exact packaged artifact from that run was verified with
  `codesign --verify --deep --strict`. Its executable SHA-256 is
  `71e89030c05c75bad68607dc53ddecbb0a9a390c99d9bc93af0cafee99eca60e`.
- Native staged-artifact testing reproduced the rejected-key recovery state
  after relaunch and verified that **Play** entered active playback, **Save**
  opened the foreground `Save Voice Memo` panel, and **Settings** opened the
  native settings window.
- The exact artifact was installed at
  `~/Applications/Interview Arc Voice.app`; its executable hash
  matched the staged artifact. The same three recovery actions passed again
  from the installed app.
- The synthetic failure flags and recovery reference used for verification
  were removed afterward. The underlying preserved recording was not changed,
  and the installed app relaunched in its normal general-dictation state.

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
