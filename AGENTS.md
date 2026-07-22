# Interview Arc Voice Agent Instructions

Read `README.md`, `docs/architecture.md`, and `docs/protocol-v1.md` before
changing this repository.

## Scope

This repository owns the native macOS recording client only. The sibling
`../interview-arc/` repository owns Cloudflare, D1, R2, MCP, specialist
instructions, website playback, and journal publication.

## Non-negotiable behavior

- Never commit API keys, Interview Arc tokens, raw recordings, or transcripts.
- Store credentials in macOS Keychain.
- Store recordings under Application Support and upload them only to the
  authenticated private Interview Arc audio endpoint.
- Preserve the original recording. Transcription chunks are disposable.
- Never rewrite, summarize, or remove fillers from the user transcript.
- Delivery analysis is attempt-specific evidence and must never mutate the
  reusable Problem Bank solution.
- Use deterministic vocabulary resolution; do not add a per-recording LLM call.
- A missing tag or unknown custom question must fall back safely to the
  specialty base vocabulary.
- Keep Groq behind a protocol so local WhisperKit can remain a fallback.
- Keep UI controls keyboard accessible and expose meaningful accessibility
  labels for every icon-only control.

## Verification

Run `swift test` after every core or client change. Also run
`swiftc -frontend -parse Sources/InterviewArcVoiceCore/*.swift Sources/InterviewArcVoice/*.swift Tests/InterviewArcVoiceCoreTests/*.swift`
for a fast syntax pass. When Xcode is available, package the application and
verify microphone, Keychain, task resumption, R2 playback, and retry behavior.
