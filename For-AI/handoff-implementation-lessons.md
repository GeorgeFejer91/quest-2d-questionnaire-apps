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
