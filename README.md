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
Groq using a small terms-only global vocabulary prompt, inserts into the app
that was active when recording began, and atomically moves the successful
finalized audio into private Recent History. The
global prompt contains stable interview vocabulary such as “LeetCode”; it is
not a personal dictionary, does not learn replacements, and contains no prose
instructions. Voice uses a guarded transient pasteboard operation internally
for editors that require a real paste event; it restores the prior contents and
never leaves the transcript as the user's clipboard value. Direct insertion
requires macOS Accessibility access; without it, Voice keeps the transcript
available for **Insert again** and explains how to enable access.
General dictation never writes transcript, audio, or coaching data to Interview
Arc, D1, or R2. Its local audio follows the same 20-item/24-hour retention
window as Recent Transcripts. If capture or transcription integrity fails, the
original remains recoverable through Play, Save, and Retry instead of being
discarded.

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
- The Record/Stop shortcut defaults to `Control-Option-Space`. A separate
  configurable `Control-Option-L` shortcut toggles Interview Arc linking while
  Voice is idle. A third configurable shortcut, `Option-M`, switches the
  floating recorder between Standard and Mini.
- All three shortcuts are routed independently by their registered macOS hotkey
  ID.
  Settings temporarily suspends the registrations while learning a replacement,
  so an existing shortcut can be entered again; Escape or Cancel abandons
  capture.
- The packaged app is a normal Applications app and participates in the Dock
  and app switcher. Every Settings entry point activates and raises the existing
  Settings window instead of leaving it hidden behind another app.
- The menu panel is fixed at 260 points wide. It opens at its intrinsic content
  height and measures the rendered stack; only content taller than the current
  screen allowance switches to a bounded vertical scroller. The first menu
  frame never depends on `ViewThatFits` choosing a viable height inside the
  `MenuBarExtra` host. The always-on-top recorder is a
  layered 250-by-40-point capsule that smoothly widens to 360 points for
  seekable playback, then returns to its compact state. It uses one hollow
  chain icon family: an intact teal chain for an active Interview Arc link, a
  quieter intact chain while link mode waits with no open session, a deep-amber
  intact chain when a session is connected but no activity is running, and a
  dark-blue hollow broken chain when linking is off. The timer-free resting
  Standard capsule reserves Play, Insert, and Plan Today beside the readable
  activity title; a collapsed timer capsule instead keeps its dense title and
  clock cluster. An expanded upper surface adds context-aware Copy and Save
  without moving the title, Plan Today control, or trailing microphone; unavailable
  memo actions stay in their fixed slots with a disabled treatment. Save uses
  a native filename/location dialog with an optional sibling transcript. The
  capsule replaces its activity label with a live waveform while recording.
  Its timer surface, activity picker, and finish
  drawer grow upward from the fixed bottom capsule across a true 10-point
  visible gap. When the experimental dynamic recording interface is enabled,
  recording from any disclosure state uses one focused recording capsule;
  the hidden timers keep running, and Stop restores the exact surface the user
  left open.
  Playback keeps seek, pause/resume, Stop, and timer-disclosure controls
  available.
- Settings → Appearance also offers a persistent Mini presentation. Mini is a
  single circular microphone surface while unlinked or linked without a timer, and
  a dense timer-plus-microphone capsule while a linked activity or session
  timer exists. Tapping an activity timer can prepend the session countdown on
  the left without moving the activity clock or microphone. Recording always
  shrinks Mini to the same one-circle state and restores the prior timer
  disclosure on Stop. The red Stop mark becomes a four-point dot during
  silence and expands with local speech volume into a rounded square that
  remains inside the fixed circular control. Its fast attack and slower release
  make ordinary speech visible without moving the microphone face. The
  transparent Mini host never exposes a rectangular glow on light or dark
  backgrounds. Clicking toggles recording, while dragging past the movement
  threshold repositions the widget exactly with the pointer and suppresses
  both recording and timer-disclosure clicks.
  Detailed memo and recovery controls remain in the menu-bar panel. Standard
  and Mini share one trailing microphone control and one bottom-right-anchored
  window resize, preventing a mode switch from moving or flashing the control.
- The menu-bar panel retains the 20 newest transcript/audio pairs locally for
  at most 24 hours in permission-0600 storage. **Recent Transcripts** loads from
  disk before Keychain or network startup, keeps its position and navigation
  controls in a stable header, and keeps Copy, Play, Save, Delete, and Insert
  actions on the visible item. Clear History removes only history-owned audio;
  unresolved linked evidence remains protected. Menu insertion preserves the
  last eligible external editor, dismisses the menu window fully, then restores
  that editor before inserting.
- The permanent widget visual and interaction contract is
  [`design-system/pages/floating-widget.md`](design-system/pages/floating-widget.md).
- Settings → Appearance offers five persistent widget themes: the original
  `Arctic Teal`, plus `Neon Circuit`, `Aurora Night`, `Solar Ember`, and
  `Sakura Glass`. Themes apply immediately and change only centralized
  material/color tokens; widget geometry and behavior remain identical.
- Agents changing any visible Voice interface must begin with
  [`design-system/AGENTS.md`](design-system/AGENTS.md), then read the current
  global master and the applicable page contract.
- Cheap local audio checks run for every capture. Normal audio uses exactly one
  speech-to-text request. Only a provider failure or concrete integrity signal
  triggers one unprompted retry.
- The finalized AAC payload must contain a plausible amount of encoded audio
  for its duration. A timed but near-silent container is rejected before Groq
  so ambient noise cannot become a guessed one-word transcript.
- A provider-reported duration is not proof that every spoken interval was
  transcribed. Voice ties complete provider word alignment to the canonical
  text and compares its final valid lexical timestamp with local speech
  evidence. Segment timestamps are acoustic windows and never substitute for
  lexical word coverage. Sustained
  speech after that boundary triggers one prompt-free retry; a second partial
  result preserves the recording and fails visibly instead of inserting text.
  This completeness check remains active when optional Silence Protection is
  Off; that setting controls hallucination filtering, not silent-loss safety.
- Settings → Silence protection offers `Off`, `Basic`, and
  `Enhanced — Experimental`. Basic rejects an entire recording with no
  sustained speech. Whole-capture admission requires both the existing
  acoustic-frame heuristic and a pinned local WebRTC VAD decision; neither
  mode adds another provider request. Enhanced reuses the same local scan and
  Groq request, then
  omits a returned segment only when its local timestamped audio and Groq's
  confidence metadata both identify it as unsupported non-speech. When a
  provider segment mixes genuine speech with a hallucinated phrase over
  silence, Enhanced can instead remove the unsupported timestamped words—but
  only when the existing local 20 ms evidence strongly verifies their
  intervals as silent. Complete Groq word coverage maps every timestamp
  directly. When timestamps are incomplete elsewhere, one consecutive silent
  word run may still be removed if its normalized text maps to exactly one
  source range in the canonical provider transcript. Missing or ambiguous
  candidate alignment preserves the text. A terminal “thank you” is removed
  only when complete word alignment identifies that exact ending and the
  combined timestamped tail contains no sustained local speech; evaluating the
  phrase as one tail prevents a brief Stop transient from authorizing two short
  invented words. Genuinely spoken instances remain. This uses no second Groq request or
  audio decode and never cuts, rewrites, or replaces the original M4A.
- Settings → Diagnostics records a bounded local timing breakdown for capture,
  validation, Groq, transcript corroboration, response handling, and insertion,
  plus privacy-safe WebRTC VAD frame/run counts, segment/word coverage, and
  omission counts. The report can be copied, revealed, or cleared and never
  contains transcript text, audio, credentials, tokens, or private URLs.

## First-time setup

You need macOS 14 or later, the ChatGPT/Codex desktop app, a Groq API key, and
your Interview Arc personal connection token.

1. Open Interview Arc, choose **Connect tools**, and copy the personal token.
2. Launch **Interview Arc Voice** from the packaged application.
3. Open **Connection settings** in its menu-bar panel.
4. Paste the Interview Arc token and Groq key. Keep these defaults unless the
   local installation moved:
   - API: `https://limitless-mcp.vinosama.workers.dev`
   - Interview Arc repository: `~/Projects/Interview Prep/interview-arc`
   - Codex executable: `/Applications/ChatGPT.app/Contents/Resources/codex`
5. Save. macOS stores both secrets in Keychain.
6. Allow Accessibility when prompted so Voice can activate the captured app and
   insert at its focused cursor.

CI artifacts carry an ad-hoc transport signature and must not directly replace
the installed app. On a new Mac, run
`./scripts/bootstrap-local-signing-identity.sh` once. Before every install, run
`./scripts/sign-app-for-install.sh '/path/to/Interview Arc Voice.app'` against
the exact merged-main artifact. The install signature is backed by one
persistent, non-extractable certificate in the user's Keychain, so later app
versions share one macOS privacy and Keychain identity. The first transition
from an older ad-hoc build may still require one macOS Keychain approval or one
credential re-save; subsequent replacements signed by the same certificate do
not.
7. For interview practice, focus an activity on Today. Keep **Link to Interview Arc** on.
   The activity title appears in the floating recorder.
8. Select the microphone or press `Control-Option-Space`. Voice uses the
   continuously refreshed focused activity and immediately starts the local
   capture backend without a network or Bluetooth output-route wait.
   **Preparing microphone** lasts only until that backend begins advancing;
   it does not wait for a particular output-profile signature. Select stop or
   press the shortcut again when finished. The transcript appears at the
   cursor; press Send yourself.
9. For ordinary dictation, turn **Link to Interview Arc** off. The resulting
   text is inserted into the active app and its finalized recording moves into
   bounded local Recent History for Play and Save.

Unresolved linked-practice originals live at:

```text
~/Library/Application Support/InterviewArcVoice/LinkedPending/
```

Completed recordings that remain visible in Recent Transcripts live at:

```text
~/Library/Application Support/InterviewArcVoice/RecentHistory/
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

General Dictation uses only the highest-priority terms from the bundled base
packs, capped at 32 unique terms. It does not apply activity matching, personal
replacement rules, or a second formatting pass.

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
local signature. The complete pull-request workflow records the source commit
and Git tree in its 14-day artifact. After merge, GitHub Actions promotes that
exact successful artifact when merged `main` has the same Git tree; otherwise
it rebuilds and tests merged `main`. See `docs/artifact-promotion.md`,
`docs/architecture.md`, and
`docs/protocol-v2.md` for the current intent-gated data flow and boundary
decisions. `docs/protocol-v1.md` documents legacy accepted captures.

The complete engineering record for the universal-insertion failure and repair
is in
[`docs/postmortems/2026-07-23-universal-dictation-insertion.md`](docs/postmortems/2026-07-23-universal-dictation-insertion.md).
The long-dictation integrity analysis and repair record is in
[`docs/postmortems/2026-07-24-long-dictation-transcript-integrity.md`](docs/postmortems/2026-07-24-long-dictation-transcript-integrity.md).
The packaged capture regression and recovery-policy repair are documented in
[`docs/postmortems/2026-07-24-header-only-recording-regression.md`](docs/postmortems/2026-07-24-header-only-recording-regression.md).
The partial-transcript recurrence caused by non-lexical trailing provider
segments is documented in
[`docs/postmortems/2026-08-01-partial-transcript-delivery.md`](docs/postmortems/2026-08-01-partial-transcript-delivery.md).
The Keychain readiness and empty-credential repair is documented in
[`docs/postmortems/2026-07-24-keychain-readiness-regression.md`](docs/postmortems/2026-07-24-keychain-readiness-regression.md).
The recording-start self-rejection and lifecycle-policy repair is documented
in
[`docs/postmortems/2026-07-24-recording-start-readiness-regression.md`](docs/postmortems/2026-07-24-recording-start-readiness-regression.md).

The non-speech transcription integrity incident and local speech-evidence gate
are documented in
[`docs/postmortems/2026-07-25-false-transcription-from-non-speech.md`](docs/postmortems/2026-07-25-false-transcription-from-non-speech.md).

## Provider and terminology references

- [Groq Speech to Text](https://console.groq.com/docs/speech-to-text)
- [LeetCode Explore](https://leetcode.com/explore/learn/)
- [AWS Glossary](https://docs.aws.amazon.com/glossary/latest/reference/glos-chap.html)
- [Google Cloud Architecture Center](https://docs.cloud.google.com/architecture)
- [Amazon Leadership Principles](https://www.amazon.jobs/content/en/our-workplace/leadership-principles)
