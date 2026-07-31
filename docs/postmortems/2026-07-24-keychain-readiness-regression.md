# Keychain readiness regression

## Summary

The installed Voice widget could display a verified Interview Arc activity yet
reject Record with “Add your Groq API key.” A visible Keychain item was not
proof of a usable credential because the save verification treated an empty
submitted value read back as empty as a successful round trip.

The failure was visible and no recording began, so no audio or transcript was
lost. It nevertheless blocked the primary product flow and made the linked
status appear misleading.

## Evidence

- The signed installed application displayed a linked system-design activity.
- Selecting Record changed the widget to `Settings need attention`.
- Recovery detail identified the missing Groq API key.
- `CredentialSaveVerificationPolicy` compared normalized strings for equality
  without requiring a nonempty Groq value.
- `saveSettings()` wrote the draft before verifying it, so an empty secure
  field could replace the existing canonical item and still pass equality
  verification.
- Earlier builds searched the Keychain search list while the newest build
  targets the login Keychain explicitly, so a usable older candidate also
  needed a one-time read migration.

## Root cause

Credential presence and credential usability were modeled as the same thing.
The application had no rule saying that the required Groq value must be
nonempty before it is written, and its read path consulted only the current
canonical item.

## Repair

1. Required credential verification now rejects empty or whitespace-only
   values.
2. Settings validation rejects an empty Groq key before any Keychain write.
3. The optional Interview Arc token can remain empty for general dictation.
4. When the canonical login-Keychain item is empty, Voice searches compatible
   legacy candidates, selects the first nonempty value, and copies it into the
   canonical item.
5. Regression tests cover empty read-back rejection, optional-token behavior,
   and recovery from an empty primary item.

## Prevention

- A Keychain item is not considered configured unless its normalized secret is
  nonempty.
- Save validation occurs before persistence for required credentials.
- Packaged-app verification must exercise Record after launch in general,
  no-focused-activity, and linked-activity routes.
- The permanent widget contract requires a specific, compact recovery message
  and forbids claiming release success from source tests alone.

## 2026-07-26 verification correction

An initial command-line probe of the exact merged-main artifact from workflow
`30222283280` reported `errSecParam`. That probe ran inside Codex's restricted
process sandbox, which does not provide normal Keychain access. It was
therefore invalid evidence of an installed-application regression and should
not have been recorded as a recurrence.

The same packaged executable, run outside that sandbox, reported both the Groq
API key and Interview Arc token as saved. The installed GUI also loaded its
secure settings and enabled recording. No user credential was lost.

PR #66 still removed deprecated explicit Keychain selection as preventive
hardening. Generic-password operations now use the current macOS Keychain
search list directly, keyed by the stable service and account. This cleanup
was not a proven root-cause repair for the sandboxed probe.

Future packaged verification must run `--credential-status` in the same normal
user context as the installed application. A sandboxed Security-framework
result must be labeled as an environment limitation and cannot establish a
credential regression.

## 2026-07-31 ad-hoc identity recurrence

Two consecutive merged-main artifacts reproduced a separate authorization
boundary in the normal GUI context. The working installed application loaded
the existing credentials and enabled Record. Replacing it with a newer CI
artifact disabled Record; restoring the prior application restored access
without changing the Keychain items. The same result occurred when the newer
artifact launched from temporary staging and when it temporarily occupied the
normal installation path.

Both bundles used `app.interviewarc.voice` and embedded the text requirement
`designated => identifier "app.interviewarc.voice"`, but both were ad-hoc
signed. An ad-hoc signature contains no certificate and identifies only that
specific program. A caller-supplied text requirement does not turn it into a
persistent cryptographic update identity.

The release repair separates transport packaging from local installation:

1. CI continues to produce a credential-free, ad-hoc-signed artifact.
2. The Mac creates one user-scoped code-signing certificate whose private key
   is non-extractable and remains in the login Keychain.
3. Before installation, the exact merged-main artifact is re-signed locally
   with that certificate and a designated requirement binding both its bundle
   identifier and the certificate fingerprint.
4. The release check verifies the non-ad-hoc signature, designated
   requirement, pre-sign source hash, post-sign package integrity, and Keychain
   readiness in the normal GUI context. The whole executable hash changes
   because the Mach-O signature is embedded in that file; this expected change
   is recorded rather than mistaken for a source-code mutation.

The first transition from an older ad-hoc authorization may require one
explicit macOS approval or one credential re-save. Future releases must reuse
the same certificate; generating a replacement identity for every build would
recreate the original failure.
