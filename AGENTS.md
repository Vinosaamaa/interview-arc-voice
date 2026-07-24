# Interview Arc Voice Agent Instructions

Read `README.md`, `docs/architecture.md`, and `docs/protocol-v1.md` before
changing this repository.

Before changing any visible interface, read and follow:

1. `design-system/AGENTS.md`
2. `design-system/interview-arc-voice/MASTER.md`
3. the matching file under `design-system/pages/`, when one exists

Before changing the always-on-top recorder, its status icons, macOS panel
shape, playback expansion, or recovery popover, reading
`design-system/pages/floating-widget.md` is mandatory. Page-specific contracts
override the global master.

Do not merge an interface change based only on a SwiftUI preview or source
inspection. Package the merged `main` artifact, install it, and exercise the
actual macOS windows on both light and dark backgrounds.

## Scope

This repository owns the native macOS recording client only. The sibling
`../interview-arc/` repository owns Cloudflare, D1, R2, MCP, specialist
instructions, website playback, and journal publication.

## Non-negotiable behavior

- Never commit API keys, Interview Arc tokens, raw recordings, or transcripts.
- Store credentials in macOS Keychain.
- Store linked-practice recordings under Application Support and upload them
  only to the authenticated private Interview Arc audio endpoint.
- Preserve an original linked-practice recording. General-dictation recordings
  are temporary and must be deleted after transcription; transcription chunks
  are always disposable.
- Never rewrite, summarize, or remove fillers from the user transcript.
- Delivery analysis is attempt-specific evidence and must never mutate the
  reusable Problem Bank solution.
- Use deterministic vocabulary resolution; do not add a per-recording LLM call.
- A missing tag or unknown custom question must fall back safely to the
  specialty base vocabulary.
- Keep Groq behind a protocol so local WhisperKit can remain a fallback.
- Keep UI controls keyboard accessible and expose meaningful accessibility
  labels for every icon-only control.
- Insert every successful transcription directly at the captured editor cursor.
  Renderer-backed editors may require a transient `NSPasteboard` snapshot and
  restore so they receive a real paste event. Never leave the transcript on the
  user's clipboard, overwrite a newer clipboard change, or submit or resume the
  visible specialist task automatically. Treat an Accessibility write as
  successful only after read-back verification.
- Refresh Interview Arc context continuously while idle. Record must use that
  cached snapshot and open the microphone without waiting for a network
  request. Linking on with missing activity/specialist must fall back to
  general dictation rather than blocking or crashing.
- Treat the original finalized M4A as the evidence boundary. Before calling
  speech-to-text, verify file finalization, decodable frames, write errors, and
  wall-time versus media duration. Never attempt to "repair" speech that was
  not recorded.
- Run one provider request in the normal path. A second unprompted request is
  allowed only after a concrete provider failure or transcript-integrity
  signal. Preserve the original recording and expose Play, Save, and Retry when
  neither result is trustworthy.
- Foreground insertion completion and background Interview Arc delivery are
  separate states. Stop the floating recorder's busy indication as soon as
  insertion completes; R2 upload and delivery coaching may continue quietly.

## Reliability change protocol

For every recording, transcription, insertion, or packaged-app reliability
change:

1. Reproduce the reported failure before changing production behavior.
2. Inspect each boundary independently: original audio, provider response,
   transcript assembly, and final editor insertion.
3. Add a regression test for the proven failure mode before the repair.
4. Use deterministic fixtures and a non-user text sink during development.
   Do not repeatedly take over the user's active cursor.
5. Exercise the exact signed packaged application after CI succeeds. A source
   build alone is not release evidence.
6. For data loss, transcript contamination, crash, or silent delivery failure,
   update or add a blameless postmortem with evidence, root cause, prevention,
   and packaged-app verification.
7. Install and test the artifact produced from merged `main`; never declare a
   release complete from an unmerged branch build.

## Verification

Run `swift test` after every core or client change. Also run
`swiftc -frontend -parse Sources/InterviewArcVoiceCore/*.swift Sources/InterviewArcVoice/*.swift Tests/InterviewArcVoiceCoreTests/*.swift`
for a fast syntax pass. CI's macOS Xcode runner is the canonical package
environment; local development must not require a full Xcode installation.
Verify microphone, Keychain, task resumption, R2 playback, and retry behavior
with the signed CI artifact. Keep any real-cursor smoke test short and perform
it only after fixture-driven tests pass.
