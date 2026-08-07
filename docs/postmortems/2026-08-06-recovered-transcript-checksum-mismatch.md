# Recovered transcript checksum mismatch

## Summary

Two linked recovery captures registered a checksum calculated from transcript
text with a final line feed while their protected records contained the same
text without that line feed. Related transcript delivery failed closed with
HTTP 409, so private-audio delivery never began and activity completion was
blocked.

Issue: [#182](https://github.com/Vinosaamaa/interview-arc-voice/issues/182)  
Repair PR: [#183](https://github.com/Vinosaamaa/interview-arc-voice/pull/183)

## Impact and detection

The original M4A files and readable transcript text remained protected
locally. D1 could not materialize the grouped response, R2 had no clip rows,
and retry could not repair the immutable identity mismatch. Activity finish
surfaced both captures as awaiting delivery.

## Root cause

The client and recovery procedures did not share one transcript-identity
constructor. Voice hashed raw text, while the Worker validates boundary-trimmed
text. A newline-terminated recovery file therefore produced a valid-looking
but incorrect immutable checksum.

## Resolution

Voice now constructs one boundary-trimmed transcript identity and reuses its
exact text and SHA-256 checksum for normal linked captures and recovery
promotion. Registration and related delivery also fail locally before any
network mutation if protected text and checksum diverge.

The two affected production records were repaired with exact identity guards;
their grouped transcript and response materialized, and both private audio
clips became available.

## Prevention and verification

- Regression coverage includes LF, CRLF, surrounding spaces, recovery
  promotion, and unchanged canonical input.
- The protocol documents one canonical transcript/checksum boundary.
- The merged-main signed package must be staged, installed, and exercised
  before issue closure.

## Known limitation

The guard preserves an inconsistent manually edited record rather than
silently registering it. Repairing already-registered historical identities
remains a coordinator-authorized production remediation.

## Glossary

- **Canonical transcript:** the exact boundary-trimmed text used everywhere
  after transcription.
- **Identity checksum:** SHA-256 of the canonical transcript bytes.
