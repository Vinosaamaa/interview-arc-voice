# Interview Arc Voice

Interview Arc Voice is the native macOS companion for Interview Arc. It records
one spoken practice answer, transcribes it through Groq, sends the transcript to
the focused Codex specialist, preserves the original recording locally and in
private R2 storage, and starts an asynchronous delivery review.

This repository intentionally lives beside, rather than inside, the main
`interview-arc` repository:

```text
Interview Prep/
├── interview-arc/          website, Cloudflare Worker, D1, R2, and MCP
└── interview-arc-voice/    native macOS client
```

The repositories remain part of the same Codex project. They communicate only
through the versioned Interview Arc API contract.

## What one click does

1. Reads the activity currently focused on Interview Arc Today.
2. Records one uninterrupted M4A under Application Support.
3. Selects a compact technical vocabulary prompt from the activity metadata.
4. Transcribes with Groq `whisper-large-v3`, chunking only when required.
5. Persists the exact user transcript turn in D1.
6. Resumes the registered Codex specialist task with that verbatim answer.
7. Uploads the original M4A to private R2 and links it to the answer.
8. Starts an ephemeral Delivery Coach task for observable speaking feedback.

R2 upload and visible specialist delivery run concurrently. A failed stage is
saved in a private local retry queue and automatically retried after relaunch;
the recording itself is never discarded.

## Product decisions

- Groq `whisper-large-v3` is the primary transcription engine.
- Local WhisperKit is a later offline/failure fallback, not the primary path.
- The original recording remains one continuous file and one website player.
- Internal transcription chunks are temporary and never appear in the UI.
- Delivery coaching is enabled for coding, system-design, and behavioral work.
- Vocabulary selection is deterministic. The bridge does not run an LLM to
  choose words.
- Groq and Interview Arc credentials are stored in macOS Keychain, never files.
- Stopping a recording sends immediately; there is no mandatory review step.

## First-time setup

You need macOS 14 or later, the ChatGPT/Codex desktop app, a Groq API key, and
your Interview Arc personal connection token.

1. Open Interview Arc, choose **Connect tools**, and copy the personal token.
2. Launch **Interview Arc Voice** from the packaged application.
3. Open **Connection settings** in its menu-bar panel.
4. Paste the Interview Arc token and Groq key. Keep these defaults unless the
   local installation moved:
   - API: `https://limitless-mcp.vinosama.workers.dev`
   - Interview Arc repository: `/Users/wenkxu/Projects/Interview Prep/interview-arc`
   - Codex executable: `/Applications/ChatGPT.app/Contents/Resources/codex`
5. Save. macOS stores both secrets in Keychain.
6. Focus an activity on Today and make sure its long-lived specialist task is
   connected. The activity title and task name will appear in the panel.
7. Select **Record answer**, speak, then select **Stop and send**.

The local originals live at:

```text
~/Library/Application Support/InterviewArcVoice/Recordings/
```

The website copy is private in R2 and streams only through Interview Arc's
authenticated audio route. Transcript text is not saved as a second standalone
text document; D1's activity transcript is its canonical copy.

## Vocabulary resolution

Every activity can provide explicit `speechTerms` and `vocabularyPackIds`.
When those are absent, the bridge matches normalized activity tags, topics,
company/project metadata, and title phrases against the bundled packs. If
nothing matches, it uses the specialty's base pack. The resolver always works,
including for custom questions with no metadata.

Priority order:

1. explicit activity speech terms;
2. explicit activity vocabulary pack IDs;
3. deterministic tag/topic/title trigger matches;
4. specialty base pack.

The final Groq prompt uses a conservative token estimate and stays below the
provider's 224-token prompt limit.

## Development

The project is a Swift package so it can be built with the command-line Swift
toolchain. A distributable `.app` will be produced by the release workflow on a
macOS runner with Xcode.

```bash
swift test
swift run InterviewArcVoice
./scripts/package-app.sh
```

The packaging script writes `dist/Interview Arc Voice.app` and applies an ad-hoc
local signature. GitHub Actions runs the full Xcode-backed test and packaging
job for every pull request. See `docs/architecture.md` and
`docs/protocol-v1.md` for the data flow and boundary decisions.

## Provider and terminology references

- [Groq Speech to Text](https://console.groq.com/docs/speech-to-text)
- [LeetCode Explore](https://leetcode.com/explore/learn/)
- [AWS Glossary](https://docs.aws.amazon.com/glossary/latest/reference/glos-chap.html)
- [Google Cloud Architecture Center](https://docs.cloud.google.com/architecture)
- [Amazon Leadership Principles](https://www.amazon.jobs/content/en/our-workplace/leadership-principles)
