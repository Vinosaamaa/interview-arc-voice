# Floating-widget upper-surface motion regression

- Date: 2026-08-03
- Status: Deferred after rollback
- Issues: #37, #58
- Pull request: #169
- Restored baseline: `77cd2a6`

## Summary

Compact-to-Focus remained the accepted motion reference, but Plan Today to
Focus had no visible content transition. Several attempts made the native
window bounds animate, but did not produce an acceptable transition between
the two SwiftUI surfaces. Two attempts introduced worse intermediate states:
one visibly cropped the outgoing planner and another stretched Focus inside a
planner-sized surface.

The running test application and the pull-request motion code were restored to
`77cd2a6`. Work is intentionally deferred. Issue #37 remains unresolved; the
rollback preserves the directions that were already acceptable without
claiming that Plan Today to Focus is fixed.

## User impact

- Compact to Focus was smooth and became the reference transition.
- Focus to compact and Focus to Plan Today were acceptable on the restored
  baseline.
- Plan Today to Focus reached the correct final Focus state, but appeared to
  swap content without a transition.
- Experimental builds briefly exposed a planner cropped through its middle or
  an oversized Focus card during the native window contraction.
- Timer state, recordings, transcripts, and practice data were not changed by
  these motion experiments.

The same machine rendered compact to Focus smoothly throughout this work. The
direction-specific failures therefore do not indicate insufficient hardware.

## Detection and evidence

Settled-frame checks were insufficient because every build reached the correct
final bounds. The useful evidence was a user-supplied screen recording of the
exact Plan Today-to-Focus action. Temporary frames sampled at 16.4, 16.7,
17.0, 17.3, and 17.6 seconds showed:

1. the full planner before the click;
2. the right-anchored window contracting while the 560-point planner remained;
3. the planner's left and upper content cut away at the middle frame; and
4. Focus appearing only after the contraction.

The recording and extracted frames were not committed. Temporary derived
frames were deleted after inspection.

## Confirmed architectural conditions

The earlier repair established four useful conditions that remain in the
baseline:

1. AppKit owns panel geometry through one native `NSAnimationContext`
   transaction using a 0.30-second ease-in-out curve.
2. Focus, Plan Today, and dynamic Record presentation changes are published as
   one atomic state rather than several independently visible mutations.
3. Planner application activation and focus return are deferred until after
   the geometry transaction.
4. The root `NSHostingView` does not publish its SwiftUI fitting size back as a
   temporary AppKit minimum.

These conditions improved the previously working directions but did not, by
themselves, animate the content replacement from Plan Today to Focus.

## Attempts and outcomes

| Attempt | Commits or run | Intended mechanism | Observed result | Disposition |
| --- | --- | --- | --- | --- |
| Remove synchronous layout pressure | PR #168 and early #169 work | Stop forced SwiftUI layout from consuming animation frames | Improved the reference paths, but endpoint verification incorrectly suggested the recurrence was resolved | Kept as background learning; issue reopened |
| Atomic presentation and deferred focus handoff | Through `77cd2a6` | Prevent intermediate model states and keep activation work outside the resize transaction | Compact-to-Focus, Focus-to-Plan Today, and Focus-to-compact remained acceptable; Plan Today-to-Focus still had no visible content transition | Restored baseline |
| Direct `NSWindow.setFrame(_:display:animate:)` | `054c45c`, CI run `30866969162` | Replace the custom/native animation-context path with AppKit's smooth-resize API | Regressed compact-to-Focus, Focus-to-Plan Today, and Plan Today-to-Focus; only Focus-to-compact remained animated | Reverted |
| Retain the outgoing planner through the contraction | `6105e77`, `013aecc`, `61165a6`; CI run `30868026232` | Keep visible content present for every intermediate native window frame | Produced visible motion, but the right-anchored shrinking viewport hard-clipped the 560-point planner through its middle | Rejected and reverted |
| Render destination Focus and stretch its material to the intermediate host | `37bd15a`; CI run `30868978220` | Avoid planner clipping while making the shrinking surface visible | Removed the planner slice, but swapped content immediately and exposed an oversized Focus card; only the outer widget had a shrink animation | Rejected and rolled back |

Two intermediate hosted runs failed before packaging and did not produce test
artifacts:

- `30867633998`: compiler failure caused by a missing explicit `return` while
  editing the transition policy;
- `30867756774`: obsolete test expectations still described the behavior that
  the experiment intentionally changed.

Both failures were corrected before evaluating the corresponding experimental
artifact. They were process overhead, not evidence that the motion was good.

## What did not work in verification

- Settled width and height assertions proved final geometry, not motion
  continuity or intermediate content.
- Automated policy tests could prove which surface was selected, but could not
  prove what SwiftUI and AppKit presented together during each frame.
- Repeated still screenshots were inefficient and could miss the exact bad
  frame. They were stopped after user feedback.
- A green packaged build established compilation and regression-test health,
  but could not substitute for direct visual acceptance of motion.
- A code-level explanation was treated as stronger evidence than the user's
  visual result. That led to premature claims and repeated experimental
  launches.

## Current state

- The temporary running application uses signed baseline commit `77cd2a6`.
- Pull-request motion source and tests are restored to the `77cd2a6` behavior.
- PR #169 is not merged and the installed application is unchanged.
- Issue #37 must remain open. Plan Today to Focus is a known limitation of the
  baseline.
- No further animation experiment should be launched in this work session.

## Requirements for a future attempt

1. Define the content handoff separately from the NSWindow bounds animation.
   The window shrinking is not, by itself, a surface transition.
2. Keep the accepted compact-to-Focus implementation unchanged and verify it
   after every candidate.
3. Do not retain an opaque 560-point planner inside a narrower clipped host.
4. Do not resize the Focus material to planner height merely to make motion
   visible.
5. Prototype the Plan Today-to-Focus content handoff in an isolated harness
   with representative planner and timer surfaces before changing the live
   widget.
6. Evaluate one bounded candidate against a short recording containing all
   required directions: compact to Focus, Focus to compact, Focus to Plan
   Today, Plan Today to Focus, and Record-triggered collapse.
7. Require user visual acceptance of the exact signed artifact before merge,
   installation, issue closure, or any claim that the recurrence is fixed.

The most plausible future direction is a coordinated content transition—such
as a short outgoing fade and destination reveal—running inside the existing
native bounds transaction. This is a hypothesis, not a verified fix.

## Glossary

- **Bounds animation:** movement or resizing of the native `NSWindow` frame.
- **Content transition:** the visual handoff between the Plan Today and Focus
  SwiftUI surfaces inside that window.
- **Atomic presentation state:** one observable value containing all flags
  needed to choose a surface, preventing half-updated combinations.
- **Clipping viewport:** a container that hides pixels falling outside its
  current bounds; this caused the retained planner to be cut during shrink.
