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
| `warning` | `#B85A32` | Compact actionable failure |

Do not introduce unrelated pink, blue, green, or amber accents in normal
states. Status colors may be used only when they communicate a real state.

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

When space permits, the order is:

```text
[link] [activity title] [activity elapsed] | [SESSION + countdown] [pause] [mic]
```

The compact state prioritizes the link state, activity/general-dictation
identity, and microphone. Linked recording and playback may widen to reveal
timing or transport controls. Long activity names truncate on one line.

## Link icon family

- All three states use the same hollow chain geometry, size, orientation,
  stroke cap, and stroke weight.
- `linked`: intact hollow teal chain.
- `waiting`: intact hollow teal chain. Context is communicated by the title and
  accessibility label rather than by drawing a different badge on the icon.
- `off`: the same chain split at its center, rendered as a hollow dark-blue
  broken chain.
- Never fake the broken state by drawing a filled slash over a chain.
- Never place a filled background inside one chain state when the other states
  are hollow.

## State behavior

- Linked activity: teal chain, activity title, and linked instrumentation.
- Link enabled with no running activity: intact quieter chain and “No focused
  activity”; recording uses general dictation.
- Link off: hollow dark-blue broken chain and “General dictation.”
- Recording: microphone halo brightens and the activity label yields to live
  audio feedback and elapsed time.
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
- Respect Reduce Motion by replacing movement with short opacity changes.
- Every icon-only control has an accessibility label and a tooltip.
- A Record press must react immediately; cached activity routing must not add a
  network wait before microphone capture.

## Release checklist

- No rectangular host background is visible around the capsule.
- Linked, waiting, and off icons are demonstrably one hollow icon family.
- The failure popover is narrower than the widget.
- Record works in link-off, link-on/no-activity, and link-on/active-activity
  routes.
- Silent input does not produce a guessed transcript.
- Previous-capture controls appear only when corresponding content exists.
- Hover, keyboard focus, press feedback, Reduce Motion, and accessibility
  labels are verified.
- The signed artifact from merged `main` is installed and exercised; a source
  preview is not release evidence.
