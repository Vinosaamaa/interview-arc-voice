# Floating Widget Visual Contract

This page-specific contract overrides
`design-system/interview-arc-voice/MASTER.md` for the always-on-top recorder.
Every agent changing `FloatingRecorderView`, its macOS panel, its status icons,
or its recovery popover must read this file first.

## Product character

The recorder is a compact interview instrument: a frosted-glass capsule with
quiet teal instrumentation and one strongly layered microphone control. It is
not a generic Material toolbar, a flat white rectangle, or a colorful consumer
voice memo.

Its signature is the elevated microphone halo. Spend the visual depth there
and keep the surrounding information calm.

## Palette

The following table defines the default `Arctic Teal` theme.

| Token | Value | Use |
| --- | --- | --- |
| `glass` | `#F4FAFA` at 88–94% | Capsule surface |
| `glassHighlight` | `#FFFFFF` at 65–80% | Inner rim and raised faces |
| `coolBorder` | `#C8DADB` | Capsule and control outline |
| `timerSurface` | `#E5F3F2` | Activity timer inset |
| `teal` | `#148E89` | Primary instrumentation |
| `tealDark` | `#087B77` | High-contrast teal marks |
| `tealGlow` | `#BFEDE8` at 35–55% | Microphone halo |
| `ink` | `#172A32` | Primary text |
| `secondaryInk` | `#587074` | Labels and annotations |
| `divider` | `#BACCCD` | Structural divider |
| `coolShadow` | `#557B7D` at 12–18% | Broad capsule shadow |
| `linkOff` | `#173A68` | Hollow broken-chain mark |
| `connectedIdle` | `#A65D1C` | Interview Arc connected, but speech is using general dictation |
| `warning` | `#B85A32` | Compact actionable failure |

Alternate themes replace these values through the centralized palette only.
Status colors may be used only when they communicate a real state.

### Theme invariants

- The approved themes are `Arctic Teal`, `Neon Circuit`, `Aurora Night`,
  `Solar Ember`, and `Sakura Glass`.
- Every theme preserves the 250-by-40 resting capsule, host transparency,
  spacing, typography roles, icon family, microphone elevation, timer layout,
  playback width, and motion timing.
- One theme is visible at a time. Never mix accents or surfaces from two
  themes inside the same widget.
- Link-off, connected-idle, warning, and recording states remain semantically
  recognizable in every theme and never rely on color alone.
- Theme selection exists only in Settings → Appearance, applies immediately,
  and persists between launches.
- Theme previews use the real palette tokens and component geometry rather
  than screenshots or hand-maintained approximations.

## Typography

- Activity title: SF Pro Display, medium or semibold.
- Labels: SF Pro Text, semibold, uppercase, increased tracking.
- Timers: SF Mono, medium, tabular digits.
- Supporting text: SF Pro Text at a legible compact size.
- Symbols: one rounded, stroke-led system with consistent optical weight.

Timer values must never change width as they count.

## Geometry and material

1. The resting widget is a 250-by-40-point capsule.
2. The actual `NSPanel`, hosting view, and SwiftUI root must all be transparent
   outside the capsule. A rounded child inside an opaque rectangular host is a
   release-blocking defect.
3. The capsule uses a cool one-point outer rim and a restrained inner white
   highlight.
4. Use one broad, low-opacity cool shadow. Never enable the rectangular native
   panel shadow.
5. Circular controls use a diffuse halo, a structural rim, and a bright
   translucent face.
6. The microphone is the only strongly elevated control.
7. Controls stay vertically stable when the widget changes width.
8. Playback and active instrumentation widen the same capsule smoothly; they
   never open an unrelated rectangular strip.

## Information hierarchy

The compact state prioritizes the link state, activity/general-dictation
identity, previous-capture actions, and microphone. When an open D1 timer
instrument exists, the activity title includes a quiet disclosure chevron.
Linked recording and playback may widen to reveal timing or transport
controls. Long activity names scroll on one line when motion is allowed.
The compact timer cluster is deliberately dense: activity and session clocks
share at most 84 points, use no decorative stopwatch badge, and preserve at
least 58 points for the activity title.

## Expanded timer instrument

- The recorder capsule is the stable bottom surface. Expanding reveals one
  second frosted surface above it in the same transparent `NSPanel`.
- Preserve a real 10-point visible transparent gap. Any unused height in the
  expanded host belongs above the timer surface, never between the timer and
  recorder. The surfaces must read as two coordinated components, not one
  opaque card.
- Expansion is right-edge and bottom-edge anchored. The timer, activity picker,
  and result drawer all grow upward. Collapsing restores the 250-by-40 capsule
  without moving it.
- Session and activity rows use the same three columns: identity/title, stable
  monospaced time, and controls.
- Normal timer rows contain only Pause/Resume and Finish.
- The session is a countdown and may render `+HH:MM:SS` overtime. The activity
  is an elapsed stopwatch and may also exceed its allocation.
- A paused last-focused activity remains visible and resumable while its
  session continues or is paused.
- Finish on an activity opens an inline drawer inside the second surface. Only
  this drawer contains the explicit result flags and problem star control.
- The next-activity picker contains activity identity plus Start, Resume, or
  Start-and-open controls. It never contains result flags or stars.
- Timer digits advance locally from the latest server timestamp. D1 receives
  state transitions, not one write per displayed second.

## Link icon family

- All states use the same hollow chain geometry, size, orientation,
  stroke cap, and stroke weight.
- `linked`: intact hollow teal chain.
- `waiting`: intact hollow quiet-teal chain when no session is open.
- `connected idle`: the same intact hollow chain in deep amber when a session
  remains open but no activity is running. This state is still connected; it
  must never use the broken-chain icon.
- `off`: the same chain split at its center, rendered as a hollow dark-blue
  broken chain.
- Never fake the broken state by drawing a filled slash over a chain.
- Never place a filled background inside one chain state when the other states
  are hollow.

## State behavior

- Linked activity: teal chain, activity title, and linked instrumentation.
- Link enabled with no open session or activity: intact quieter chain and
  “No focused activity · general dictation.”
- Link enabled with an open session but no running activity: intact amber
  chain and either “General dictation · no activity running” or “General
  dictation · session paused.” A paused last-focused activity remains
  resumable in the expanded timer surface but must not replace this compact
  general-dictation title.
- Link off: hollow dark-blue broken chain and “General dictation.”
- Recording: microphone halo brightens and the activity label yields to live
  audio feedback and elapsed time.
- With the experimental dynamic recording interface enabled, starting from
  either compact or expanded mode transitions into the same focused recording
  capsule. The timer surface, activity picker, and finish drawer are hidden
  rather than closed; their disclosure is snapshotted and restored exactly on
  Stop. Session and activity clocks continue advancing while hidden.
- The recording capsule uses the live dot, historical waveform, recording
  tint/outline, elapsed clock, and unmistakable Stop control in every theme.
  Theme-specific tokens must preserve sufficient contrast.
- The historical waveform uses 64 one-point samples. Its inter-sample spacing
  adapts to the live instrument width so the history fills the available area
  between the live dot and elapsed clock. Do not reintroduce a short waveform
  surrounded by unused horizontal gaps.
- Compact timer values stay on one line in fixed-width columns. The activity
  title scrolls only when it overflows; Reduce Motion replaces scrolling with
  truncation.
- Playback retains seek, pause/resume, explicit Stop, and timer disclosure.
  Opening or closing the timer surface must not stop playback.
- Playback or Record again launched from a recovery popover dismisses that
  anchored popover and waits for AppKit's completed-close notification before
  changing recorder geometry. A bounded delay exists only as a safety fallback;
  the popover and its anchor must never survive into an intermediate playback-
  or recording-width frame.
- Processing: show a compact progress mark only after meaningful elapsed
  processing time. Do not keep the widget busy after insertion succeeds.
- No previous capture: Play, Copy, and Save controls are absent, not disabled.
- Failure: show the concise cause in the capsule and an anchored recovery
  popover narrower than the 250-point widget.

## Recovery popover

- Target width: 220–236 points.
- Use one concise title, a one- or two-line actionable explanation, and only
  the actions that can resolve the failure.
- Put diagnostic detail behind a compact disclosure or allow it to wrap below
  the primary action; do not default to a 430-point inspector.
- The copy names the failed boundary: microphone, secure settings,
  transcription, insertion, or Interview Arc delivery.
- “Needs attention” by itself is not sufficient.

## Motion and interaction

- Hover: brighten the raised surface and lift it by at most one point without
  shifting neighboring layout.
- Press: compress the control by about three percent.
- Width changes: 200–260 ms ease-in-out, anchored to the widget’s right edge.
- Timer expansion changes both width and height over the same 200–260 ms
  interval, anchored to the widget’s bottom-right corner.
- The activity picker and finish-result drawer use the same 300 ms
  ease-in-out transaction in both directions. Their content fades with a
  restrained bottom-anchored scale while AppKit owns the corresponding window
  resize; opening and closing must feel symmetric.
- AppKit is the only owner of animated window geometry. The SwiftUI root fills
  every intermediate host size and pins its content bottom-trailing; it must
  not jump immediately to the final model size while the panel is still
  interpolating.
- The visible recorder capsule follows the live host width at every
  intermediate AppKit frame. It must not bind directly to the final model
  width, which makes collapse appear to snap even while the panel is animating.
- The compact activity title fills the available row height and remains
  vertically centered while its horizontal marquee or truncation changes.
- Respect Reduce Motion by replacing movement with short opacity changes.
- Every icon-only control has an accessibility label and a tooltip.
- A Record press must react immediately; cached activity routing must not add a
  network wait before microphone capture.

## Release checklist

- No rectangular host background is visible around the capsule.
- Test that transparency on both a pure-white window and a near-black window;
  the host window's 250-by-56-point bounds must not be detectable on either.
- The blur material and the custom shadow must both use the capsule silhouette.
  Applying a shadow to the hosting view or leaving the blur effect rectangular
  is a release-blocking defect even when it is subtle on the desktop wallpaper.
- Linked, waiting, and off icons are demonstrably one hollow icon family.
- The failure popover is narrower than the widget.
- Record works in link-off, link-on/no-activity, and link-on/active-activity
  routes.
- Silent input does not produce a guessed transcript.
- Previous-capture controls appear only when corresponding content exists.
- Timer rows expose no result or star controls until Finish opens its drawer.
- The next-activity picker exposes no result or star controls.
- Pausing a session freezes both clocks and preserves the last-focused
  activity; resuming it never changes to the broken-chain state.
- Pausing the only running activity immediately changes the compact capsule to
  the amber general-dictation state. General captures in this state never
  create activity transcript, audio, or coaching records in D1 or R2.
- Starting and stopping a dynamic recording must not mutate the remembered
  timer, picker, or finish-drawer disclosure. Stop restores the snapshot in one
  bottom-anchored resize without an intermediate compact frame.
- The visible gap between the timer surface and recorder is exactly 10 points;
  oversized transparent host slack remains above both surfaces.
- Playback exposes both Stop and timer disclosure; expanding the timer leaves
  playback position and transport state intact.
- Session and activity overtime remain legible and do not resize their columns.
- Both compact clocks remain on one line while the title keeps a readable
  viewport; the clock cluster never consumes more than 84 points.
- Intermediate expansion and collapse frames visibly resize the capsule; no
  target-width snap may be hidden inside an otherwise animated native panel.
- Expand and collapse keep the capsule on one bottom baseline with no vertical
  hop, flash, or competing SwiftUI geometry animation.
- Hover, keyboard focus, press feedback, Reduce Motion, and accessibility
  labels are verified.
- The signed artifact from merged `main` is installed and exercised; a source
  preview is not release evidence.
