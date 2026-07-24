# Interview Arc Voice Design Agent Contract

This file is the entry point for every agent that changes visible Voice UI.
It exists to keep separately implemented features inside one coherent product.

## Required reading order

1. Read this file.
2. Read `interview-arc-voice/MASTER.md`.
3. Read the matching contract under `pages/`.
4. Inspect the current signed application before proposing a redesign.

The most specific contract wins:

```text
page contract > Voice design master > personal preference
```

If the current implementation and the written contract disagree, stop and
identify which one represents the user's most recently approved design. Update
the contract in the same change; do not silently create a third visual system.

## Approved direction

Interview Arc Voice is a compact professional instrument, not a generic
dashboard. Its visual language is:

- frosted, translucent surfaces;
- restrained cool teal instrumentation;
- deep blue-gray text;
- fine cool-gray structural borders;
- soft, silhouette-aware depth;
- dense but calm information;
- one clearly elevated primary control;
- native macOS typography and behavior.

The floating microphone control is the signature component. Other Voice
surfaces should feel related to it without copying its exact capsule geometry
everywhere.

## Rules for changing the interface

### Preserve hierarchy

- Keep the primary action visually dominant.
- Use supporting controls as quiet, consistent icon buttons.
- Reveal secondary information progressively instead of making the resting
  interface larger.
- Do not replace state-specific information with generic copy such as “Needs
  attention.”

### Preserve component families

- Use one hollow, rounded icon family with consistent stroke weight.
- Equivalent controls must share shape, size, border, hover, press, focus, and
  disabled behavior across the widget, menu, settings, and recovery UI.
- Reuse palette and geometry tokens rather than introducing close-looking
  one-off colors or radii.
- Do not use emoji, filled clip-art symbols, or mismatched icon libraries.

### Preserve material integrity

- Transparent windows must be structurally transparent at the `NSPanel`,
  hosting-view, blur, and SwiftUI-root levels.
- Blur, clipping, and shadows must follow the visible silhouette. A faint
  rectangular host footprint is a release-blocking defect.
- Never enable the native rectangular window shadow for a shaped floating
  surface.
- Avoid nested borders and shadows that make the UI look embossed or muddy.

### Preserve motion quality

- Hover feedback may brighten or lift a control by at most one point.
- Press feedback may compress a control by roughly three percent.
- State and width transitions use 200–260 ms ease-in-out.
- Motion must never delay recording, insertion, or error recovery.
- Respect Reduce Motion with opacity-based state changes.

### Preserve information density

- Keep the menu-bar panel at 260 points unless a page contract explicitly
  changes it.
- Keep recovery popovers narrower than the resting floating widget.
- Truncate long titles on one line and expose the full value through a tooltip
  or accessible label.
- Do not solve overflow by widening every surface or adding explanatory prose.

## Mandatory workflow

1. Capture the current state and reproduce the visual or interaction problem.
2. State which design rule is changing and why.
3. Add or update the relevant page contract before implementation.
4. Reuse existing components and tokens where possible.
5. Test every affected state, not only the default state.
6. Run the Swift test suite and the fast parser check.
7. Merge through the repository workflow.
8. Install the exact artifact produced from merged `main`.
9. Test the signed app on pure-white and near-black backgrounds.
10. Verify hover, press, keyboard focus, accessibility labels, Reduce Motion,
    link states, recording, processing, playback, and recovery as applicable.

## State matrix

Every affected surface must be reviewed in the relevant states:

| State | Required visual behavior |
| --- | --- |
| Link off | Hollow dark-blue broken chain; general dictation remains usable |
| Link on, no activity | Intact quiet-teal chain; “No focused activity” |
| Linked activity | Intact teal chain and current activity title |
| Recording | Live signal and elapsed time; stop control is unmistakable |
| Processing | Compact delayed progress indication; no stale busy state |
| Playback | Transport controls expand inside the existing surface |
| Recoverable failure | Specific cause and only useful recovery actions |
| No previous capture | Playback, copy, and save controls are absent |

## Release blockers

Do not declare a UI change complete when any of the following is true:

- the signed application was not tested;
- a host rectangle is visible around a shaped panel;
- equivalent icons use different geometry or fill treatment;
- a clickable control has no hover, focus, tooltip, or accessibility label;
- text clips or controls collide at the supported window size;
- a transition jitters, flashes, leaves a ghost image, or blocks interaction;
- the design works only on a wallpaper that hides its defects;
- a new feature introduces a second competing palette or component family.

When uncertain, preserve the current approved design and propose a mockup before
making a large aesthetic change.
