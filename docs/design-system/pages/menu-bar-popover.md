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
- **Insert Again** and **Copy for Codex** reconstruct the complete Voice v2
  envelope from the protected local record.
- **Copy transcript** copies plain text.
- Attach/Delete appear only when a user decision is useful.
- Retry controls appear only for genuine transient work. Waiting is never
  labeled a retry.

## Floating timer integration

When the timer drawer is expanded and a previous recording exists, the recorder
row replaces its redundant compact clocks with Play, Copy transcript, and Save.
The activity title keeps the remaining flexible width. The authoritative
session/activity clocks remain in the drawer above.

## Accessory behavior

Voice is a menu-bar/floating accessory (`LSUIElement`). It does not appear in
the Dock or Command-Tab. Settings must still activate the app and raise the
existing Settings window explicitly.
