# Menu-bar popover sizing regression

- Incident issue: [#138](https://github.com/Vinosaamaa/interview-arc-voice/issues/138)
- Status: recurrence repair in progress; exact packaged-app verification required
- Affected surface: macOS menu-bar popover
- Severity: repeated loss of the primary detailed-control surface

## Summary and impact

The menu-bar popover first retained a tall translucent window after its content
became shorter. A root `ScrollView` bounded that height but advertised the bound
as its intrinsic window size, creating empty material. A follow-up replaced it
with `ViewThatFits`; inside the `.window`-style `MenuBarExtra`, the first
vertical proposal could instead select a zero-content result. The installed
popover then opened without its expected controls.

## Root cause

Both repairs delegated the native window's initial intrinsic height to a
SwiftUI container whose vertical ideal size is ambiguous. A menu-bar extra is a
content-sized AppKit window. Root scroll views and first-pass fitting probes do
not provide stable intrinsic height evidence in that host.

Automated policy tests covered the numerical screen cap, but no regression
proved that the first installed menu frame contained real content. CI and an
accessibility smoke of the floating widget were therefore insufficient release
evidence for the menu surface.

## Resolution

The menu now renders the real fixed-width content stack intrinsically on its
first frame and measures that rendered height through a SwiftUI preference. If
the measured height fits the current screen allowance, that intrinsic stack
continues to own the window. Only measured overflow switches the same stack to
a fixed-height vertical scroller. The full content remains measurable inside
the scroller, avoiding state-change oscillation.

## Regression prevention and verification

- Policy tests require zero/unmeasured and fitting content to use intrinsic
  presentation, and overflowing content to use the explicit screen cap.
- Parser, diff, package, signing, and CI checks remain required.
- Closure requires opening the exact signed staged artifact and installed app,
  confirming ordinary content is visible, short states have no empty material,
  and a deliberately tall failure/recovery state scrolls without clipping.
- Future menu-sizing changes must test the actual `MenuBarExtra` host; a preview
  or floating-widget accessibility tree is not equivalent evidence.

## Rollback

Revert the measured presentation to the last intrinsic `VStack` implementation.
That may allow tall content to exceed the screen, but it preserves access to the
controls while a bounded-scrolling repair is prepared.
