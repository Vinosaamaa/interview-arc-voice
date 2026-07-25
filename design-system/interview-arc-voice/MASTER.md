# Interview Arc Voice Design System

This is the global visual contract for the native macOS application.
Page-specific contracts under `../pages/` override this file.

## Product character

Interview Arc Voice should feel like a precise, quiet interview instrument:
compact, reliable, calm, and clearly native to macOS.

The default `Arctic Teal` direction combines:

- pale frosted glass;
- cool teal instrumentation;
- dark blue-gray type;
- subtle layered depth;
- dense, disciplined spacing;
- one strongly elevated primary action.

The floating widget also supports four approved alternate personalities:
`Neon Circuit`, `Aurora Night`, `Solar Ember`, and `Sakura Glass`. Each uses
the same instrument structure and component family. Avoid generic SaaS cards,
colorful consumer voice-memo styling, heavy neumorphism, and flat rectangles.

## Core palette

| Token | Value | Purpose |
| --- | --- | --- |
| `glass` | `#F4FAFA` at 88–94% | Primary translucent surface |
| `glassHighlight` | `#FFFFFF` at 65–80% | Inner rim and raised face |
| `coolBorder` | `#C8DADB` | Structural outline |
| `timerSurface` | `#E5F3F2` | Inset timing and status surface |
| `teal` | `#148E89` | Primary instrumentation |
| `tealDark` | `#087B77` | High-contrast teal symbol or value |
| `tealGlow` | `#BFEDE8` at 35–55% | Primary-control halo |
| `ink` | `#172A32` | Primary text |
| `secondaryInk` | `#587074` | Supporting labels |
| `divider` | `#BACCCD` | Quiet separator |
| `coolShadow` | `#557B7D` at 12–18% | Broad shaped shadow |
| `linkOff` | `#173A68` | Unlinked hollow-chain mark |
| `connectedIdle` | `#A65D1C` | Connected session with no running activity |
| `warning` | `#B85A32` | Actionable warning or failure |
| `recording` | `#B84E4E` | Active stop/recording state only |

These values define `Arctic Teal`. Alternate widget themes may replace
material, text, and instrumentation tokens only through the centralized theme
palette. Status colors retain their semantic meaning and must remain
distinguishable from the selected theme.

## Approved widget themes

| Theme | Character | Material and accent direction |
| --- | --- | --- |
| `Arctic Teal` | Original frosted instrument | Pearl glass, cool teal, pale aqua |
| `Neon Circuit` | Electric cyberpunk | Smoked obsidian, electric cyan, restrained magenta |
| `Aurora Night` | Calm midnight spectrum | Midnight navy, turquoise, indigo, restrained violet |
| `Solar Ember` | Warm precision instrument | Graphite glass, amber, copper, warm ivory |
| `Sakura Glass` | Soft editorial light | Pearl blush, dusty rose, dark plum |

Theme selection belongs under Settings → Appearance. It applies immediately
and persists between launches. The floating widget itself never exposes a
theme selector.

## Typography

Use native system fonts:

- activity names: SF Pro Display, medium or semibold;
- body and controls: SF Pro Text;
- compact labels: SF Pro Text, semibold, uppercase, increased tracking;
- timers: SF Mono, medium, tabular digits.

Do not load web fonts into the native application. Timer values must not shift
width while counting. Supporting copy must remain readable at compact sizes.

## Geometry

| Element | Geometry |
| --- | --- |
| Floating recorder | 250 × 40 pt resting capsule |
| Floating host | 250 × 56 pt transparent window |
| Menu-bar panel | 260 pt fixed width |
| Recovery popover | 220–236 pt target width |
| Compact icon control | 28–32 pt visual target |
| Primary microphone | Circular, layered, visually elevated |
| Standard corner radius | 8–12 pt |
| Instrument capsule radius | Half of its height |

Use four-point spacing increments whenever practical. Keep controls vertically
stable as content changes.

## Material and depth

1. Use a pale translucent surface with a restrained cool border.
2. Add one fine white inner highlight where it improves material separation.
3. Use one broad, low-opacity shadow that follows the component silhouette.
4. Put the strongest halo and elevation on the primary microphone control.
5. Keep secondary buttons quiet and avoid stacking multiple heavy shadows.
6. Never allow an opaque host rectangle to sit behind a rounded or shaped
   visible surface.

## Iconography

- Use SF Symbols or a custom family derived from one rounded, stroke-led
  geometry.
- Keep optical size and stroke weight consistent.
- Equivalent states must use the same base symbol family.
- Linked and unlinked use intact and broken variants of the same hollow chain.
- Icon-only controls require a tooltip and accessibility label.
- Do not use emoji or filled decorative illustrations as controls.

## Component behavior

### Primary actions

- Use a bright translucent face, structural rim, and diffuse teal halo.
- Hover slightly brightens and lifts without moving adjacent content.
- Press compresses subtly.
- Destructive or stop states may use restrained recording red.

### Secondary icon buttons

- Share one size, hit target, border, hover, press, focus, and disabled system.
- Disabled controls are absent when their absence is meaningful; otherwise
  reduce contrast without making the symbol illegible.
- Do not mix circular and rectangular treatments for equivalent actions.

### Status and recovery

- Name the failed boundary: microphone, credentials, transcription, insertion,
  connection, or delivery.
- Keep primary explanations to one or two lines.
- Expose diagnostics progressively.
- Show only actions that can resolve the current state.

### Settings

- Group related settings with clear labels and short supporting copy.
- Secure fields must visibly confirm saved state without exposing secrets.
- Keep advanced or diagnostic configuration subordinate to the normal flow.
- Do not make the settings surface look like a separate product.

## Motion

- Standard transition: 200–260 ms ease-in-out.
- Hover lift: at most one point.
- Press scale: approximately 0.97.
- Width expansion anchors to the stable edge defined by the page contract.
- No overshoot or spring animation on dense status interfaces.
- Reduce Motion replaces translation and scaling with short opacity changes.

Motion supports continuity; it must never delay microphone capture, text
insertion, or failure recovery.

## Accessibility

- Maintain at least 4.5:1 contrast for ordinary text.
- Provide visible keyboard focus.
- Give every icon-only control an accessibility label and tooltip.
- Do not communicate state by color alone.
- Keep click targets usable even when their visual symbol is compact.
- Verify VoiceOver reading order after restructuring a control group.

## Responsive native behavior

The Voice application uses fixed compact surfaces rather than web breakpoints.
When content exceeds available width:

1. preserve the primary action;
2. preserve current state;
3. truncate the activity title;
4. reveal secondary actions progressively;
5. widen only within the page contract;
6. never clip, overlap, or add horizontal scrolling.

## Global anti-patterns

- Opaque rectangular hosts behind rounded panels.
- Native window shadows on non-rectangular floating surfaces.
- Multiple palettes visible in one widget or colors outside the approved
  centralized theme tokens.
- Generic Material, marketplace, or dashboard templates.
- Web fonts inside the macOS application.
- Mismatched link-state icons.
- Decorative gradients unrelated to surface material.
- Disabled buttons displayed when they should be absent.
- Instant state changes, jitter, flashing, or ghost imagery.
- Large recovery dialogs for a small actionable failure.
- Help text that remains after the action has already completed.

## Global release checklist

- Read `design-system/AGENTS.md` and the applicable page contract.
- Compare the result with the current signed app.
- Verify all relevant states, not only the resting state.
- Test pure-white and near-black backgrounds.
- Verify the host bounds cannot be detected outside the visible silhouette.
- Verify hover, press, focus, tooltip, accessibility, and Reduce Motion.
- Run tests and parser validation.
- Install and exercise the artifact produced from merged `main`.
