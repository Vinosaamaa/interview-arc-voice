# Artifact executable-mode loss during main promotion

## Summary

The merged-main Voice artifact could contain the correct tested application
bytes while losing the executable permission bits on files under
`Contents/MacOS`. The application then looked complete but could not pass the
installation signing gate without a manual `chmod` repair.

Issue: [#143](https://github.com/Vinosaamaa/interview-arc-voice/issues/143)

## User impact

The release artifact was not directly installable. Installation stopped before
signing, and a developer had to restore executable permissions manually. No
installed application, user recording, transcript, credential, or server data
was changed by the failed installation attempt.

## Detection and evidence

The pull-request artifact packaged executable files correctly. The merged-main
workflow downloaded that unpacked artifact and uploaded it again. The final
download showed ordinary-file modes for both app executables, and
`sign-app-for-install.sh` rejected the primary executable because it was not
executable.

## Root cause

GitHub Actions artifacts are ZIP transports and do not preserve Unix mode bits
for unpacked files. The promotion workflow treated an unpacked `.app` directory
as a mode-preserving payload. Downloading and re-uploading the directory kept
file contents but normalized its executable modes.

## Contributing factors

- Provenance verified the Git tree and source run, but not filesystem modes.
- The package gate checked modes before the first upload, not after a complete
  artifact round trip.
- The promoted artifact had no mode-preserving inner archive.

## Resolution

The workflow now creates a canonical compressed tar archive after packaging,
extracts it into a clean temporary directory, verifies both app executables are
executable, and removes the unpacked application before artifact upload. Main
promotion reuses the exact tested archive bytes; fallback main builds create
the same archive.

## Regression prevention

- Workflow policy validation requires archiving on both PR and fallback-main
  packaging paths.
- The archive script fails if either packaged or cleanly extracted executable
  lacks executable permission.
- The install lifecycle extracts the canonical archive before stable local
  signing and smoke verification.

## Verification requirement

The issue may close only after CI passes and a downloaded merged-main archive
extracts to an application whose two `Contents/MacOS` files are executable
without a manual permission repair.

## Technical glossary

- **Mode bit**: Unix filesystem metadata that marks a file executable.
- **Artifact promotion**: reusing a successful pull-request build for the same
  merged Git tree instead of rebuilding it.
- **Canonical payload**: the file whose exact bytes are promoted and installed.
