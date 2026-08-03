# Postmortem: Codex CLI captures silently lost Voice v2 envelopes

**Date:** 2026-08-02  
**Status:** In progress  
**Severity:** P0 reliability  
**Issue:** [#60](https://github.com/Vinosaamaa/interview-arc-voice/issues/60)

## Summary

Interview Arc Voice displayed a running LeetCode activity as linked while
recordings inserted into Codex CLI were silently processed as General
Dictation. The transcript remained visible to the user, but Voice created no
stable capture/turn identifiers, local pending lifecycle, or protocol-v2
envelope. The specialist therefore had no reliable way to classify or persist
the answer.

The original destination safety gate recognized only the desktop Codex bundle.
It had never been extended or tested for Codex CLI hosted by terminal
applications. A separate presentation path rendered the cached activity
without checking the destination gate, creating a split-brain UI.

## Impact

- Eleven consecutive recordings made after a real coding activity started were
  stored as General Dictation.
- None created a Voice intent, pending lifecycle, or v2 envelope.
- Transcript text was still inserted, so the data-routing loss was not visible
  until the user inspected the missing envelope.
- No unrelated transcript or recording was uploaded to D1 or R2.
- The local transcript/audio retention path remained available; the incident
  affected durable practice attribution and delivery, not the original M4A.

## Detection

The user noticed that the expected envelope was absent while the widget and
timer showed an active LeetCode problem. There was no built-in warning because
the app treated the downgrade as ordinary General Dictation and did not record
a route-reason diagnostic.

## Timeline

All times are Pacific Daylight Time on 2026-08-02.

| Time | Event |
| --- | --- |
| 16:45 | The coding activity and its timers began. |
| 16:48–16:59 | Eleven recordings were persisted without activity identity, capture identity, lifecycle state, or v2 envelope. |
| 17:03 | Investigation confirmed the installed widget showed the activity as linked while local history showed General Dictation metadata. |
| 17:06 | Source inspection isolated the hard-coded desktop-only destination gate. |
| 17:08 | A dedicated Reliability worktree was created for regression coverage and repair. |
| 17:29 | The first complete macOS CI run passed and produced a tree-addressed artifact. |
| 17:34 | Staging found that the old installed process had not exited, so it was terminated before repeating the artifact test. |
| 17:41 | The exact staged artifact exposed a second boundary defect: cmux still failed closed even though separate process inspection proved live `codex` descendants. The first diagnostic did not preserve the exact target-decision reason. |
| 2026-08-03 02:00 | Process-topology inspection confirmed that tmux detaches pane shells and Codex from the focused terminal application's descendant tree. |
| 2026-08-03 02:14 | The user explicitly approved the bounded fallback: Link enabled, fresh focused activity, supported cmux/Warp host, and Interview Arc/Codex top-level window title. |

## Architecture and failure sequence

```text
Active D1 activity + Link enabled
              |
              +--> Widget presentation checks cached activity --------> "Linked"
              |
              +--> Capture routing checks target bundle
                         |
                         +--> desktop Codex bundle: linked flow
                         |
                         +--> cmux/Warp bundle: General Dictation
                                      |
                                      +--> no captureId / turnId / envelope
```

## Root cause

`CaptureTargetApplicationPolicy` equated “Codex destination” with one desktop
application bundle identifier. Codex CLI inherits the bundle identifier of its
terminal host, so the capture-start policy set its target eligibility to false.
`prepareAndStartRecording` then selected General Dictation even though link mode
and the focused activity were both valid.

The widget's linked presentation depended only on the cached focused activity.
It did not consume the same target decision as recording. This allowed the UI
to promise linked behavior that the capture path would not perform.

## Contributing factors

1. The original installed verification covered desktop Codex and non-Codex
   applications, but not Codex CLI terminals.
2. The policy API accepted only a bundle identifier, so it could not safely
   distinguish a Codex CLI workspace from an arbitrary terminal.
3. A stale-context fallback could also silently choose General Dictation. Its
   late-binding repair was guarded by the same desktop-only target decision.
4. Diagnostics captured transcription timing but not the target kind or capture
   route reason.
5. The first CLI repair depended only on the Accessibility focused-window-title
   attribute and recorded only the coarse target kind. A background menu-bar
   application cannot rely on every supported terminal exposing that attribute
   consistently, and the missing decision reason made the installed failure
   unnecessarily ambiguous.
6. The second CLI repair required Codex to be a descendant of the focused
   terminal application. That assumption is false under tmux: the pane shell
   and Codex are descendants of the long-lived tmux server, not the focused
   Warp/cmux process.

## Resolution design

1. Resolve a privacy-safe target descriptor at recording start.
2. Keep desktop Codex intrinsically eligible.
3. Admit a CLI terminal when all four user-approved signals agree:
   - Link mode is explicitly enabled;
   - the focused activity context is fresh;
   - the host is an explicitly supported terminal application;
   - the focused top-level window identifies an Interview Arc/Codex workspace.
4. Do not make process ancestry a requirement. tmux intentionally breaks that
   ancestry, and a global “any Codex process exists” fallback cannot identify
   the focused pane.
5. Do not inspect terminal text, arguments, environment variables, tmux pane
   contents, or private paths.
6. Feed the same target decision into widget presentation and capture routing.
7. Preserve stale-context late binding only for a verified specialist target
   and an activity already running at recording start.
8. Persist the locally observed host bundle, top-level window title, bounded
   target kind, decision reason, and route reason in local diagnostics.
9. Prefer the Accessibility focused-window title, then fall back to the visible
   layer-zero window title metadata for the same terminal PID. The fallback
   captures no pixels and reads no terminal content.
10. Ship a privacy-safe `--capture-target-status <pid>` package verifier that
   reports only target-kind and decision enums for installed-artifact testing.

## Regression prevention

- Core tests cover desktop Codex, tmux-detached cmux/Warp Interview Arc
  workspaces, arbitrary terminal windows, spoofed non-terminal titles, stale
  context, and explicit downgrade reasons.
- Packaged-app verification must exercise the exact signed installed app in a
  real active coding activity and verify one envelope/local pending record per
  recording.
- A browser and an arbitrary terminal window must still create no Voice intent.
- Installed verification must compare the widget's visible state with the
  actual local route metadata.

## Verification status

PR #156 passed its first complete macOS CI run, but exact-artifact staging
correctly kept the issue open after exposing the Accessibility-only title
lookup defect. A hardened artifact and signed installed-app verification are
still in progress. This document will be finalized with the final PR head,
merge commit, packaged artifact, and exact test evidence before issue closure.

## Glossary

- **Voice v2 envelope:** Invisible Markdown metadata containing the stable
  capture, activity, and turn identities supplied to the specialist.
- **General Dictation:** Local insertion that intentionally does not touch
  Interview Arc, D1, R2, or specialist intent state.
- **Late binding:** A safe correction that links a recording after a fresh
  context response proves the activity was already running at capture start.
