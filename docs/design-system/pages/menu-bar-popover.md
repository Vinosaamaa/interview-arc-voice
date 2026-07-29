# Menu-bar popover

The 260-point menu-bar popover is Voice's detailed status and recovery surface.
The floating capsule remains a simple recording and timer instrument.

## Live state

- The refresh icon means **Refresh focused activity** only.
- Owner-scoped server events update timer and capture state.
- A disconnected connection uses bounded snapshot fallback.
- Local clocks may redraw once per second; that redraw performs no network
  request.

## Recent Captures

- Newest first.
- Three rows initially.
- **Show all** reveals a fixed-height scrolling list and never widens the
  popover.
- Each row shows a two-line transcript preview, activity title, and one truthful
  state:
  - Syncing
  - Waiting for specialist
  - Needs decision
  - Excluded
  - Related · syncing
  - Retry scheduled
  - Conflict · review required
- **Insert Again** reconstructs the complete Voice v2 envelope from the
  protected local record and always terminates with success or a recoverable
  error.
- Insertion retains the last eligible external editor while the menu-bar
  surface is open. Voice, Control Center, SystemUIServer, Dock, Notification
  Center, WindowManager, and loginwindow are never valid insertion targets.
- One context-aware **Copy** action copies the transcript plus its exact Voice
  v2 envelope when capture metadata exists. General dictation without metadata
  remains plain text; there is no separate “Copy for Codex” action.
- Attach/Delete appear only when a user decision is useful.
- Retry controls appear only for genuine transient work. Waiting is never
  labeled a retry.

## Recent transcripts

- The transcript card retains the five newest local transcript records for at
  most 24 hours. Its protected JSON file is permission `0600`.
- The newest transcript opens first. Bottom-right **Newer** and **Older**
  chevrons move through the bounded history without wrapping or changing the
  260-point popover width.
- The footer shows the selected transcript's word count, recording duration,
  and position such as `2 of 5`.
- Copy and Insert Again always use the selected record. A linked record keeps
  its exact Voice v2 envelope; general dictation stays plain text.
- Successful general-dictation audio retention is not extended for history.
  Play and Save are available only when the selected newest record still owns
  the recoverable in-memory audio.
- Menu-bar Insert Again prefers the last eligible external editor remembered
  before Voice or a system menu became active. The floating capsule continues
  to use the live focused editor.

## Rejected provider credentials

- Groq `401` and `403` responses are configuration failures, not retryable
  transcription failures.
- Voice preserves the finalized recording, disables Record and Retry for the
  rejected key, and offers Settings, Play, and Save.
- The failure clears only after a different key is saved. Transient provider or
  network failures keep the ordinary Retry path.

## Floating timer integration

When the timer drawer is expanded and a previous recording exists, the recorder
row replaces its redundant compact clocks with Play, Insert, context-aware
Copy, Save, and the timer-disclosure control so the expanded surface can still
collapse.
The activity title keeps the remaining flexible width. The authoritative
session/activity clocks remain in the drawer above.

Career Focus appears in the timer instrument with a `J` mark and finishes
directly without a result drawer. If a session finish is blocked by started
practice activities without results, the menu-bar popover owns the compact
multi-activity result resolver. The floating capsule shows only the attention
message and never contains the whole resolver.

## Accessory behavior

Voice is a menu-bar/floating accessory (`LSUIElement`). It does not appear in
the Dock or Command-Tab. Settings must still activate the app and raise the
existing Settings window explicitly.
