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
