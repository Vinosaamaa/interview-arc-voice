# Interview Arc Voice

Interview Arc Voice is a native macOS dictation tool and Interview Arc
companion. It records speech, transcribes through Groq, and either inserts the
text directly at the active editor's cursor or links the same visible practice
answer to D1, private R2 audio, and asynchronous delivery review.

This repository intentionally lives beside, rather than inside, the main
`interview-arc` repository:

```text
Interview Prep/
├── interview-arc/          website, Cloudflare Worker, D1, R2, and MCP
└── interview-arc-voice/    native macOS client
```

The repositories remain part of the same Codex project. They communicate only
through the versioned Interview Arc API contract.

## Two capture modes

**Link to Interview Arc** is on by default. Voice refreshes the focused
dashboard activity continuously while idle, so pressing Record can open the
microphone immediately without waiting for the network. When an activity and
specialist are available, one click:

1. Reads the activity currently focused on Interview Arc Today.
2. Records one uninterrupted M4A under Application Support.
3. Selects a compact technical vocabulary prompt from the activity metadata.
4. Verifies that the finalized audio duration and frames match the recording,
   then transcribes with Groq `whisper-large-v3`, chunking only when required.
5. Persists the exact user transcript turn in D1.
6. Inserts the verbatim answer plus a Markdown comment envelope at the focused
   text cursor. For renderer-backed web and Electron editors, Voice briefly
   snapshots and replaces the macOS pasteboard so the editor receives a real
   paste event, then restores the prior contents if no other app changed them.
   The user never performs a manual copy/paste. The envelope identifies the D1
   turn so the specialist does not append it twice; the user reviews the answer
   and presses Send.
7. Uploads the original M4A to private R2 and links it to the answer.
8. Starts an ephemeral Delivery Coach task for observable speaking feedback.

R2 upload and delivery-analysis setup run in the background and do not keep the
floating recorder in a busy state after text reaches the cursor. A failed stage is
saved in a private local retry queue and automatically retried after relaunch;
the recording itself is never discarded.

When linking is off—or when no usable Interview Arc activity is focused—Voice
works as **general dictation**. It records to a temporary file, transcribes with
Groq, inserts into the app that was active when recording began, and deletes the
temporary audio. Voice uses a guarded transient pasteboard operation internally
for editors that require a real paste event; it restores the prior contents and
never leaves the transcript as the user's clipboard value. Direct insertion
requires macOS Accessibility access; without it, Voice keeps the transcript
available for **Insert again** and explains how to enable access.
General dictation never writes transcript, audio, or coaching data to Interview
Arc, D1, or R2. Successful temporary audio is deleted. If capture or
transcription integrity fails, the original remains recoverable through Play,
Save, and Retry instead of being discarded.

## Product decisions

- Groq `whisper-large-v3` is the primary transcription engine.
- Local WhisperKit is a later offline/failure fallback, not the primary path.
- The original recording remains one continuous file and one website player.
- Internal transcription chunks are temporary and never appear in the UI.
- Delivery coaching is enabled for coding, system-design, and behavioral work.
- Vocabulary selection is deterministic. The bridge does not run an LLM to
  choose words.
- Groq and Interview Arc credentials are stored in macOS Keychain, never files.
- Stopping a recording inserts immediately but never presses Send. The visible
  editor remains the review boundary.
- The always-on-top recorder and menu-bar panel expose the same record/stop and
  link controls.
- The global shortcut defaults to `Control-Option-Space` and is configurable in
  Settings.
- The menu panel is fixed at 260 points wide. The always-on-top recorder is a
  fixed 250-by-40-point capsule. It uses a filled teal chain for an active
  Interview Arc link, an amber chain for general fallback, and a gray broken
  chain when linking is off. The capsule exposes Play, Copy, and Save for the
  latest capture and replaces its activity label with a live waveform while
  recording.
- Cheap local audio checks run for every capture. Normal audio uses exactly one
  speech-to-text request. Only a provider failure or concrete integrity signal
  triggers one unprompted retry.

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
6. Allow Accessibility when prompted so Voice can activate the captured app and
   insert at its focused cursor.

The packaged app carries a stable local designated requirement for
`app.interviewarc.voice`. After the first Accessibility grant, replacing the
app with a newer package from this repository preserves the same macOS privacy
identity instead of requiring permission again after every build.
7. For interview practice, focus an activity on Today. Keep **Link to Interview Arc** on.
   The activity title appears in the floating recorder.
8. Select the microphone or press `Control-Option-Space`. Voice uses the
   continuously refreshed focused activity and starts capture immediately, so
   switching problem timers never requires a manual refresh. Speak, then select stop or press the
   shortcut again. The transcript appears at the cursor; press Send yourself.
9. For ordinary dictation, turn **Link to Interview Arc** off. The resulting
   text is inserted into the active app and the temporary recording is deleted.

Linked practice originals live at:

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

The complete engineering record for the universal-insertion failure and repair
is in
[`docs/postmortems/2026-07-23-universal-dictation-insertion.md`](docs/postmortems/2026-07-23-universal-dictation-insertion.md).
The long-dictation integrity analysis and repair record is in
[`docs/postmortems/2026-07-24-long-dictation-transcript-integrity.md`](docs/postmortems/2026-07-24-long-dictation-transcript-integrity.md).

## Provider and terminology references

- [Groq Speech to Text](https://console.groq.com/docs/speech-to-text)
- [LeetCode Explore](https://leetcode.com/explore/learn/)
- [AWS Glossary](https://docs.aws.amazon.com/glossary/latest/reference/glos-chap.html)
- [Google Cloud Architecture Center](https://docs.cloud.google.com/architecture)
- [Amazon Leadership Principles](https://www.amazon.jobs/content/en/our-workplace/leadership-principles)
