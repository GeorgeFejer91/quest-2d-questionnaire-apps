# Handoff Implementation Lessons

This note records reusable problem-solution lessons from implementing the
universal XR-to-2D-panel handoff.

## PendingIntent First, Component Return Second

Problem: returning from a reusable 2D panel to the exact foreground XR Activity
is brittle when only `mq.callerPackage` and `mq.callerActivity` are passed.

Solution: the XR app should create a `PendingIntent.getActivity()` return token
targeting its own `singleTop` Activity and pass it as `mq.returnPendingIntent`.
The panel saves exports, sends that token with result extras, and uses
caller-package return only as compatibility fallback.

Generalizable rule: for cross-package app handoffs, prefer a caller-created
return token over reconstructing the caller component inside the callee.

## Trigger Completion Is Not Sequence Advancement

Problem: when ChainLink routes by `mq.triggerId`, treating panel completion as
`nextBlock` can accidentally launch the next trigger's questionnaire before the
XR app emits that trigger.

Solution: trigger-routed blocks return to ChainLink with a distinct
`triggerComplete` command. ChainLink records the result, returns to the source
XR app, and waits for the next real trigger.

Generalizable rule: sequence plans and event-routed plans need different
completion semantics even if both launch the same APKs.

## Demo Modes Must Be Runtime Modes

Problem: a GUI label such as "Demographics" is misleading if Android runtime
mode `baseline` still runs demographics plus MAIA-2.

Solution: add `demographics` as a real questionnaire mode, export it as such,
and stop after the participant form.

Generalizable rule: block-builder labels must map to actual runtime behavior,
not just study-design intent.

## Local Renderers Are First-Class Stress Gates

Problem: headset screenshots are slow and can conflate rendering, focus, and
capture-route issues.

Solution: use local Android render preview gates for the questionnaire and
temporal tracer before any Quest install loop, and use the Unity video render
gate before trusting headset screenshots.

Generalizable rule: use local renderers to catch visual and layout regressions
before device-facing evidence collection.

## Companion APIs Need Real HTTP Stress Tests

Problem: a builder smoke test can prove that browser JavaScript emits the right
JSON, while still missing failures in the local companion path used by the
hosted GUI.

Solution: add a validator that starts the companion, checks pairing-token
authorization, saves the generated handoff config through `/api/save-config`,
validates it through `/api/validate-config`, and generates/render-previews it
through `/api/generate-apk`.

Generalizable rule: when a static web GUI delegates work to local software,
stress the HTTP boundary itself, including auth failures and long-running
commands.

## Native stderr Is Not Failure By Itself

Problem: Gradle can write harmless notes to stderr while exiting successfully.
Capturing child output with `2>&1` under `$ErrorActionPreference = 'Stop'` can
turn those notes into terminating PowerShell errors and make a healthy endpoint
return 500.

Solution: companion child-process wrappers should capture stderr as text under
a local `Continue` error preference, then decide success only from the child
exit code and required artifacts.

Generalizable rule: distinguish process exit status from output stream class;
stderr is evidence to record, not automatically a failure.

## Token Generators Must Match The Runtime

Problem: `RandomNumberGenerator.Fill()` is not available in the Windows
PowerShell/.NET runtime on this development machine, even though it exists in
newer .NET APIs.

Solution: use `RandomNumberGenerator.Create().GetBytes(...)` for companion
pairing tokens and validation tokens.

Generalizable rule: local Windows automation scripts should use APIs available
in the target PowerShell runtime, not only modern .NET examples.
