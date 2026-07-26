# Recovery popover geometry regression

## Summary

After a no-speech or transcription failure, choosing **Play** or **Record
again** from the recovery popover could briefly crop the floating widget before
the playback or recording layout appeared. A previous repair deferred playback
until the popover view disappeared, but the native popover window was still
animating when the widget began its own geometry transition.

## Root cause

SwiftUI's popover content `onDisappear` marks the end of the content view's
lifetime, not the end of AppKit's native popover dismissal animation. Starting
a floating-window resize at that boundary caused two independent windows to
animate simultaneously:

1. the recovery popover began dismissing;
2. the floating widget immediately changed width for playback or recording;
3. AppKit briefly applied the old host geometry during the overlap;
4. the leading portion of the widget appeared clipped.

The first repair covered only **Play** and did not include **Record again**.
It also treated `onDisappear` as a fully settled window boundary.

## Repair

- Classify both playback and recording recovery actions as geometry-changing.
- Dismiss the recovery popover before executing either action.
- Wait one bounded 260 ms native-settle interval after `onDisappear`.
- Only then start the floating widget's normal playback or recording
  transition.
- Keep actions that do not resize the widget immediate.

## Release gate

Verify the installed packaged app for both a no-speech failure and a
transcription failure:

1. open the recovery popover;
2. choose **Play** and confirm the widget remains whole during expansion;
3. return to the failure state;
4. choose **Record again** and confirm the widget remains whole during
   expansion;
5. repeat from both compact and expanded starting states.

Parser, unit, and policy tests remain necessary, but visual verification of the
installed AppKit window is the acceptance test for this class of regression.
