# Floating-widget upper-surface motion regression

- Date: 2026-08-03
- Status: Repair in verification
- Issue: #37

## Summary

Compact-to-Focus remained smooth, but Plan Today to Focus, Focus to Plan Today,
and Record-triggered collapse visibly hitched. Record could expose two distinct
collapse stages. The same installed build and machine rendered the reference
transition smoothly, which isolated the defect to path-specific application
work rather than hardware capacity.

## Impact

The widget reached the correct final surfaces, but several common transitions
missed display frames or exposed an intermediate presentation. Timer state,
transcripts, recordings, and Interview Arc practice data were not changed by
the motion defect.

## Detection

The regression was reported after PR #168 had been installed and issue #37 had
been closed. Endpoint reproduction confirmed each control reached the intended
surface. Comparing the source paths showed that only the failing transitions
performed additional observable-state and main-actor work during geometry
animation.

## Root cause

Three conditions combined:

1. The panel controller animated geometry with a `Task` that woke the main
   actor at a nominal 60 Hz, calculated an intermediate frame, called
   `setFrame(display:)`, and slept again. Removing forced subtree layout in the
   previous repair reduced work but left frame scheduling in application code.
2. Focus, Plan Today, and dynamic Record were represented by separate
   `@Published` booleans. One user action could therefore invalidate the
   SwiftUI tree multiple times and briefly expose an intermediate surface.
3. Planner application activation was asymmetric. Opening Plan Today deferred
   key-window/text-entry work, but closing it immediately reactivated the
   previous application on the same run-loop turn as the native shrink. That
   focus handoff let AppKit commit Plan Today-to-Focus at the destination frame
   without presenting the intermediate frames.

The smooth compact-to-Focus path avoided the planner work and most of the
multi-property transition cost, which is why it remained a reliable reference.

## Why prior verification missed it

PR #168 verified settled window endpoints and removed the largest synchronous
layout call. Those checks did not measure presentation cadence, compare every
direction against compact-to-Focus, or cover Record's combined presentation
change. Closing the recurrence after endpoint verification overstated what had
actually been proven.

## Repair

- AppKit now owns each resize through one native `NSAnimationContext`
  transaction with a shared 0.30-second ease-in-out curve.
- The destination Focus, Plan Today, or Record surface is published as one
  atomic presentation state.
- Planner refresh, text-entry activation, and the return of application focus
  are deferred until the geometry transaction has finished.
- Policy coverage requires every direction to use the native backend and
  verifies Focus/Planner/Record state transitions as indivisible values.

## Regression prevention

Compact-to-Focus is now the named motion reference in the design contract.
Future acceptance must exercise compact-to-Focus, Focus-to-compact,
Focus-to-Plan Today, Plan Today-to-Focus, and Record-triggered collapse from the
exact packaged artifact. Correct settled geometry alone is insufficient.

## Verification

Local parser and repository checks are pending completion. The canonical macOS
build, exact packaged-artifact comparison, and installed transition pass must
all succeed before issue #37 is closed again.

## Glossary

- **Display deadline:** the time by which a frame must be ready for the next
  screen refresh; missing it is perceived as a hitch.
- **Atomic presentation state:** one observable value containing all flags
  needed to choose the surface, so a transition cannot publish a half-updated
  combination.
