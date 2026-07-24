# Recording start readiness regression

## Summary

The floating microphone accepted a start command, changed the model to
`isStartingRecording = true`, and then immediately rejected microphone
preparation. The rejection was incorrectly reported as a missing Groq key even
when both secure settings fields were populated and the packaged credential
diagnostic reported them as saved.

## Root cause

`canRecord` is a UI command-acceptance property. It intentionally becomes false
while a start command is already in flight so repeated clicks cannot open the
microphone twice.

The asynchronous preparation routine reused that same property after it had
already claimed the start command:

1. the command policy returned `start`;
2. the model set `isStartingRecording = true`;
3. preparation checked `canRecord`;
4. `canRecord` returned false because startup was in progress;
5. preparation reported the unrelated missing-credential error.

Command admission and admitted-command execution are different lifecycle
checks. Reusing the former for the latter made every valid start
self-canceling.

## Repair

- Keep `RecordingCommandPolicy` responsible for ignoring duplicate commands
  while startup is in flight.
- Add `RecordingPreparationPolicy`, which checks only the requirements that
  remain relevant after a start command has been admitted: a Groq credential
  and an idle processing pipeline.
- Use the preparation policy inside the asynchronous microphone-start routine.
- Cover both policies independently so a future latency or debounce change
  cannot reintroduce the self-rejection.

## Release gate

Every Voice recording change must exercise the installed packaged app:

1. click Record once and observe the recording state;
2. click Record repeatedly during startup and confirm only one capture opens;
3. stop, transcribe, and insert into a non-user test editor;
4. repeat after relaunch;
5. repeat with Interview Arc linking on and a genuinely running activity.

Passing compilation or unit tests alone is not proof that the recording
lifecycle works.
