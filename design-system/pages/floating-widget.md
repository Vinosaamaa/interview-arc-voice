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
- Every theme preserves Standard's 250-by-40 resting capsule, Mini's
  40-point circular microphone surface inside a transparent 48-point host and
  108-by-40 single-timer capsule and 177-by-40 dual-timer capsule, host
  transparency, spacing,
  typography roles, icon family, microphone elevation, timer layout, playback
  width, and motion timing.
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

1. Standard rests as a 250-by-40-point capsule. Mini rests as either one
   40-point microphone circle inside a transparent 48-by-40 host or a
   108-by-40 single-timer capsule or 177-by-40 dual-timer capsule.
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
identity, previous-capture actions, and microphone. Timer-free resting Standard
reserves three stable trailing actions—Play, Insert, and Plan Today. A collapsed
timer capsule keeps its title and authoritative clock cluster instead. An
expanded upper surface adds context-aware Copy and Save between Insert and Plan Today. Memo
actions remain visible but disabled when their transcript or audio prerequisite
is unavailable, so their slots never reflow the title viewport. When an open D1 timer
instrument exists, the activity title includes a quiet disclosure chevron.
Linked recording and playback may widen to reveal timing or transport
controls. Long activity names scroll on one line when motion is allowed.
The compact timer cluster is deliberately dense: activity and session clocks
share at most 84 points, use no decorative stopwatch badge, and preserve at
least 58 points for the activity title.

### Mini presentation

- Mini is an optional persistent presentation selected in Settings →
  Appearance or with its configurable global shortcut. It changes presentation,
  never capture routing, timer authority, recording evidence, or recovery
  state.
- With no linked timer, Mini contains exactly one circular microphone surface
  with no surrounding frosted capsule rim and no visible link button, title,
  waveform, memo action, or disclosure.
- Link state remains legible without expanding the capsule: unlinked uses the
  theme's `linkOff` microphone treatment; linked uses the active link color and
  an integrated chain badge. Link/unlink remains available through the global
  link shortcut and the menu-bar panel.
- When linked and an activity timer exists, Mini shows that elapsed timer.
  Otherwise it shows the linked session countdown/overtime timer. A paused
  timer remains visible at its frozen value.
- When both timers exist, tapping the activity-timer region prepends one
  equal-width session-timer cell on the left. The activity cell and microphone
  remain anchored. Divider spacing is symmetric, and tapping again collapses
  the session cell. A session-only timer has no disclosure.
- Starting or preparing a recording shrinks any Mini timer capsule into the
  same one-circle recording state. Stop restores the exact single- or
  dual-timer disclosure. Recording keeps the 32-point circular face fixed and
  replaces the microphone with an expanding red Stop mark driven by the
  recorder's smoothed local power meter. Silence is a four-point dot. Speech
  grows it continuously into a rounded square, and loud speech approaches but
  never exceeds 28 points inside the face. Attack is deliberately faster than
  release so ordinary speech—not only shouting—produces an obvious response
  without flicker. The feedback never moves the outer control or adds
  network/transcription work. The transparent 48-point host contains no meter
  ring, glow, backing fill, or rectangular alpha; any visible outer square is a
  release-blocking defect on every desktop background.
- A click toggles recording. Movement beyond the five-point drag threshold
  moves the panel exactly one-for-one in macOS screen coordinates and cancels
  the click, whether Mini is idle, recording, or showing timers. Mini has one
  movement owner; AppKit background dragging and SwiftUI dragging must never
  run simultaneously. Dragging the timer region must not toggle its
  single-/dual-timer disclosure.
- Previous-capture, playback, failure, recovery, picker, and finish controls
  remain available in the menu-bar popover. Returning to Standard renders the
  current authoritative state rather than a stale hidden drawer.

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

## Today planner

- Plan Today reuses the expanded instrument's one frosted upper surface. When
  timers exist, `Focus` and `Plan today` are mutually exclusive tabs in that
  surface; they never stack and switching never mutates either timer.
- Standard idle may expose one quiet calendar-plus entry after existing
  previous-capture actions only when the title remains readable. Standard with
  timers keeps the compact capsule free of a Plan icon. Mini has no visible
  Plan control; its configurable shortcut and the menu-bar command open the
  same upper surface.
- Standard expanded memo state has no More/Back shelf. It shows every applicable
  action in one row—Play, Insert, Copy, Save, and Plan Today—while preserving
  the reserved title width and far-right microphone anchor.
- The recorder remains the bottom-right anchor. Planner expansion grows left
  and upward, preserves the real ten-point transparent gap, and never moves
  the microphone. The native panel is the only geometry animator. Compact,
  Focus, and Plan Today never render two successor surfaces together. A Focus
  ↔ Plan Today switch renders only its destination while the native frame
  resizes. A true collapse to compact retains exactly one outgoing surface for
  the bounded native resize so the host clips it away continuously, then
  releases it. Reduce Motion applies the destination and geometry immediately.
- The planner uses native system typography, theme palette tokens, compact
  cards, and one persistent review tray. Selected cards use a tinted border
  and fill; they do not add a checkbox before the title or copy their title
  into search.
- The review tray gives its full-width top row to the selected-chip rail. The
  Standalone, One session, and Add activities controls share one fixed bottom
  row aligned with the other planner surfaces' primary actions. Empty state
  copy stays inside the rail instead of adding a separate summary label. The
  rail clips at its own rounded boundary. Trackpad scrolling, vertical
  mouse-wheel scrolling,
  and click-dragging all pan the rail horizontally. A stationary click
  deselects a chip; crossing the native drag threshold must never deselect it.
  The entire tray is bottom-pinned at the same vertical position for every
  specialty, regardless of the category content height above it.
- Coding, System design, and Behavioral each own independent search, favorite,
  difficulty, and sort state. Career contains the Job applications focus block
  inside Activities, never inside Full session.
- The surface tabs and specialty chips are top-anchored. Switching among
  Coding, System design, Behavioral, and Career preserves the exact vertical
  gap between those two control families even when their content heights differ.
- Favorite, Filter, and Sort are full hit-target controls with consistent hover
  and press feedback. Filter and Sort popover footer actions are surfaced
  buttons, not bare text; Clear, Reset, and Done expose the same feedback.
- Standalone, One session, and Add activities use the same planner hover and
  press language. Destination buttons expose an unmistakable selected state;
  Add activities exposes distinct enabled and disabled states without moving.
- Custom activity expands as a surfaced form with genuinely focusable title,
  URL, prompt, and minutes inputs. Duration is labeled in minutes rather than
  shown as an unexplained number. Cancel and Add to selection use the planner's
  surfaced hover, press, enabled, and disabled states.
- Today renders each session as a distinct parent card. Its activities live in
  an inset child stack with a visible hierarchy rail and their own quiet row
  surfaces; standalone work stays outside beneath its own heading. Parent and
  child rows must never share one visually flat list treatment.
- Start fresh today is one surfaced footer button containing its action label
  and eligibility message. It exposes hover, press, and disabled feedback and
  uses a sunrise icon rather than the header's refresh symbol; it must never
  render as loose footer text.
- Switching Today, Activities, and Full session never cross-composites their
  content trees. Only the selected tab and direct controls animate, preventing
  ghost images when a populated Activities view replaces Full session.
- Full session keeps its Create action directly beneath the three specialty
  cards' supporting content and anchored at the bottom of the panel. Beneath
  the cards, a high-contrast Session countdown summarizes the live specialty
  minute breakdown and total duration. The header does not repeat that total.
  A compact three-step assembly guide fills the remaining working area with
  review-first, frequency-fill, and recipe-locking rules. Cards, count controls,
  and the primary action expose consistent
  hover and press feedback; empty space must not replace useful session context.
- Voice caches selection and presentation only. Eligibility, current Today
  work, removability, mutation identity, and conflict decisions come from the
  authenticated Worker. Exact retries reuse one mutation ID; changed work
  receives a new ID.
- Starting a recording hides the planner without clearing selection, filters,
  scroll state, or the remembered Focus/collapsed disclosure. Stop restores
  the exact upper surface after capture state settles.

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
- When coverage remains uncertain but Voice has inserted the best eligible
  nonempty candidate, replace the compact title/timer cluster with one quiet
  theme-aware warning line: **Best available transcript inserted · may be
  incomplete**. Use the semantic warning token plus an accessibility label;
  do not open a popover, steal focus, or retain the processing state. The next
  recording clears this transient widget notice, while Recent Transcripts
  keeps the persistent **May be incomplete** badge.
- A native recorder termination never disappears into an idle surface. Preserve
  its finalized audio, present a high-visibility recovery state, and offer
  Retry transcription, Record again, Play, and Save without submitting a
  partial linked answer automatically.
- No previous capture: the applicable three- or five-action shelf keeps its
  exact geometry while Play, Insert, Copy, and Save use the shared disabled
  treatment.
- Failure: show the concise cause in the capsule and an anchored recovery
  popover narrower than the 250-point widget.
- Provider authentication and permission failures keep automatic retry
  disabled while exposing one explicit Retry beside Settings, Play, and Save
  when protected audio exists. Retrying never discards the recording or
  guesses whether its original destination was linked or general dictation.

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
- Standard/Mini switching uses the same native bottom-right-anchored resize and
  a content crossfade. Both modes share one trailing microphone control, so its
  center must remain stationary throughout every intermediate frame. Do not
  build two independent capsules or two competing microphone layouts.
- Timer expansion changes both width and height over the same 200–260 ms
  interval, anchored to the widget’s bottom-right corner.
- Timer disclosure explicitly synchronizes the native `NSPanel` size after the
  model transaction. A disclosure label and the visible timer surface must
  never disagree because a SwiftUI observation was missed.
- The activity picker and finish-result drawer use the same 300 ms
  ease-in-out transaction in both directions. Their content fades with a
  restrained bottom-anchored scale while AppKit owns the corresponding window
  resize; opening and closing must feel symmetric.
- AppKit is the only owner of animated window geometry. The SwiftUI root fills
  every intermediate host size and pins its content bottom-trailing; it must
  not jump immediately to the final model size while the panel is still
  interpolating.
- When the wider Plan Today surface changes to Focus, the visible Focus surface
  follows every intermediate host width until it reaches the settled Focus
  width. Animating only transparent host area is a snap, not a transition.
- Record-triggered collapse begins before microphone readiness work and uses
  the same native geometry sequence as the explicit collapse control. Audio
  startup must not delay or compete with visible panel motion.
- The borderless panel must expose real intermediate frames in both directions.
  Use one cancellable 60 Hz eased frame sequence so a reversal continues from
  the current frame; do not rely on a proxy animation that can settle directly
  at the target and make collapse look disabled.
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
- Insert is available beside the other previous-capture controls and targets
  the last eligible external editor; transient menu-bar and system UI processes
  are never remembered as insertion destinations. Menu insertion waits until
  AppKit has actually dismissed the menu window before restoring the editor.
- **Recent Transcripts** retains at most 20 newest-first transcript/audio pairs
  for 24 hours in permission-0600 local storage and loads them before remote
  startup work. Position and navigation stay in the header; Copy, Play, Save,
  Delete, and Insert always act on the visible item. Clear History removes
  history-owned pairs without deleting unresolved linked evidence.
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
- Plan Today preserves a stationary microphone, independent specialty
  filters, selected work, and the exact previous Focus/collapsed disclosure
  through open, close, Mini entry, recording, and server-conflict refresh.
- The native panel background never owns the whole standard widget's mouse
  handling. Buttons keep full hit testing, while a thresholded title-region drag
  moves the widget without converting clicks into drags. Planner text fields
  make the nonactivating panel key only after the user clicks a field; the last
  eligible external editor remains the insertion destination.
- Timer-free Standard resting memo actions use one three-slot shelf—Play,
  Insert, and Plan Today—while the title viewport and trailing microphone remain
  fixed. Once an
  upper Focus or Plan Today surface has expanded and the live capsule reaches
  usable width, Copy and Save fade into two reserved slots before Plan Today,
  producing Play, Insert, Copy, Save, and Plan Today. There is no More or Back
  mode. Compact timer capsules retain their dense clock cluster; expanded Focus
  moves those authoritative clocks above and uses the five-action recorder row.
- Plan Today uses an outer Focus/Plan Today switcher and an independent inner
  Today/Activities/Full session tab row. Today is the default and highlights
  the authoritative running item with its live clock.
- Recent Transcripts uses a fixed card, preview viewport, two-line
  word-count/duration column, and five fixed action slots. Short transcripts
  must not collapse the card or leave the selected transcript body blank.
- Intermediate expansion and collapse frames visibly resize the capsule; no
  target-width snap may be hidden inside an otherwise animated native panel.
- Expand and collapse keep the capsule on one bottom baseline with no vertical
  hop, flash, or competing SwiftUI geometry animation.
- Mini recording is always the 48-point one-circle state. A linked 108-point
  single timer or 177-point dual timer shrinks to that circle and restores the
  exact prior disclosure on Stop.
- Standard ↔ Mini works from Settings and the configured global shortcut while
  idle, recording, processing, linked, unlinked, and timer-active. The
  microphone center does not move, and no clipped Standard content, ghost
  capsule, rectangular host, or one-frame flash appears.
- Mini's idle linked/unlinked treatments are visually distinct in every theme;
  microphone-only Mini has no surrounding capsule rim, recording is
  recognizable through the Stop symbol plus the persistent amber ring rather
  than color alone, and speech adds a clearly stronger bright-yellow level arc
  and volume-responsive halo without changing layout.
- Hover, keyboard focus, press feedback, Reduce Motion, and accessibility
  labels are verified.
- The signed artifact from merged `main` is installed and exercised; a source
  preview is not release evidence.
