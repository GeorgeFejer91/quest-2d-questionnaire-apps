# Quest 2D App Study Workflow

This is the linear path from a blank native Android app idea to a validated
Quest study APK. Use it as the first stop before diving into the deeper project
READMEs.

## What This Repo Is

This repo contains native Android 2D panel apps for Meta Horizon OS. These are
not Unity, Unreal, OpenXR, or immersive XR apps. Horizon OS launches them as
flat, resizable panels in Meta Home, and Quest controller or hand interactions
arrive as ordinary Android panel input.

The two main app families are:

- `MyQuestionnaireVR-2D`: demographic, MAIA-2, pictographic, slider, ChainLink,
  orchestrator, wrapper, and Unity source-hook tooling.
- `TemporalExperienceTracerVR-2D`: temporal experience tracer with forced
  left-to-right tracing, audio prompts, SVG/CSV/JSON exports, and Quest replay
  validation.

## Make A 2D Questionnaire App

Start with a native Android project using ordinary Android Views. The manifest
should use `MAIN`/`LAUNCHER`, avoid `com.oculus.intent.category.VR`, avoid
OpenXR permissions, and set the activity as resizable. For a Quest panel, add a
manifest `<layout>` block such as `1280dp` by `800dp`, with sane minimum panel
dimensions.

Expose an explicit launch contract so Unity apps, ChainLink, or ADB can start
the questionnaire deterministically:

- package/activity, for example
  `org.viscereality.questionnaires2d/.MainActivity`
- action, for example
  `org.viscereality.questionnaires2d.RUN`
- `launchMode="singleTop"` plus `onNewIntent()` so repeated invocations reset
  cleanly.

Pass experiment metadata through launch extras:

- `mq.sessionId`, `mq.invocationId`, `mq.experimentId`
- `mq.scenarioId`, `mq.trialId`, `mq.blockId`, `mq.blockNumber`
- `mq.participantId`, `mq.participantName`, `mq.language`
- `mq.finishBehavior`, `mq.callerPackage`, `mq.nextPackage`

Every app should write exports into `getExternalFilesDir(null)`, keep draft
state while the run is in progress, and save before launching or resuming any
other APK.

Build from each app folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-apk.ps1
```

## Make A Questionnaire

Use `MyQuestionnaireVR-2D\tools\questionnaire-config-editor\index.html` to edit
or generate questionnaire config. Then apply and validate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-questionnaire-config.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-questionnaire-assets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-apk.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\render-questionnaire-visuals.ps1
```

For device validation, install the APK, run command replay, pull exports, and
verify counts. The default Viscereality contract expects demographics, 37
MAIA-2 answers, 8 MAIA-2 scores, 3 pictographic choices, and 42 slider answers
when the full questionnaire mode is used. Chained modes may intentionally run
only baseline or pictographic blocks, but they must still include timestamps,
block metadata, unique run ids, and CSV/JSON exports.

## Make A Temporal Experience Tracer

Edit `TemporalExperienceTracerVR-2D\app\src\main\assets\tracer\TemporalTracerConfig.json`
or use `TemporalExperienceTracerVR-2D\tools\tracer-config-editor\index.html`.
Control the axis labels, elapsed-time units, SVG viewBox dimensions, y-axis
labels, start/end gate strictness, item labels, and item descriptions.

The tracer enforces a left-to-right gesture:

- the participant must start just outside the 0 vertical axis in the blue start
  area,
- pre-axis movement after the first anchor point is ignored,
- x backtracking is ignored,
- saving is disabled until the trace reaches the right end band,
- exported x coordinates are clamped to the final axis range.

The app shows the dimension label, such as `Anxiety`, and the full item
description above the coordinate system. At trace start, it plays the matching
Kokoro-generated audio asset when available. English audio files live under
`app\src\main\assets\tracer\audio\English\`; other languages can fall back to
the English cue while keeping localized text.

Validate, build, and inspect:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-temporal-tracer-assets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\render-temporal-tracer-visuals.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-apk.ps1
```

Each completed trace writes SVG, CSV, JSON, `session-index.jsonl`, and a session
summary CSV. The SVG is resolution-independent: it contains a visible
`trace-smooth-vector` path built from raw captured points, plus hidden raw and
normalized vector point polylines for audit and analysis. JSON stores raw
points and normalized analysis points; CSV stores the normalized point series.

## Chain Unity APKs And 2D Apps

ChainLink or the orchestrator owns experiment order, block numbers, app
switching, and metadata propagation. The questionnaire owns questionnaire
state and loss-safe data export.

Use the simplest reliable hook for each target APK:

- Orchestrator ownership: ChainLink starts each package/activity with explicit
  launch extras and records the current block.
- Questionnaire broker fallback: when the questionnaire is already installed,
  a broker-style activity can accept commands and launch the right block.
- Wrapper hook for closed APKs: if the Unity APK cannot be rebuilt, wrap the
  launch with a helper APK and use a manual or time gate when scenario
  completion cannot be proven.
- Source hook for rebuildable Unity APKs: add a small Unity Android bridge that
  detects the unused controller button inside the foreground Unity XR app and
  emits the same ChainLink command that synthetic validation uses.
- 2D-first launcher mode: for participant-facing studies, the packaged
  questionnaire APK may run demographics from a normal Meta Home launch and
  then open Unity with `finishBehavior=openNext`. Keep this builder/config
  driven, and keep later raw input and triggers inside Unity.
- Manual gate: when a closed scenario cannot emit a real completion event, log
  that a human operator witnessed the transition before accepting the chain.

Do not expect a background Android 2D app to receive raw Quest controller
events while a foreground immersive Unity app owns the XR session. Keep raw
controller input in Unity; use Android intents for app switching.

## Validation Ladder

Use this order and do not skip a rung when claiming a higher-level pass:

1. Local validation: schema, assets, item counts, export columns, scoring, and
   unit tests.
2. APK build: Gradle build succeeds and produces the expected APK path.
3. Quest install: explicit serial, `adb install -r -d`, package present.
4. Foreground launch: package/activity appears in `dumpsys window` focus state.
5. Replay/export pull: command replay pass marker, exports pulled from the
   app-specific external directory, counts and metadata verified.
6. Manual input gate: controller ray, trigger, hand pinch, text entry, and
   Unity source-hook button only when those physical inputs are in scope.
7. Chain validation: ChainLink plan, repeated blocks, no overwrites, block
   timestamps, foreground app handoff, and final state.

Routine visual iteration should use local Android render previews first. Use
headset screenshots only for final evidence, capture-route debugging, or
suspected compositor/panel mismatches.

## Where To Go Next

Read the workflow docs in this order:

- [01-architecture.md](01-architecture.md)
- [02-build-and-packaging.md](02-build-and-packaging.md)
- [03-questionnaires-and-exports.md](03-questionnaires-and-exports.md)
- [04-chaining-and-validation.md](04-chaining-and-validation.md)
- [05-release-checklist.md](05-release-checklist.md)

Then use the project-specific READMEs:

- [../MyQuestionnaireVR-2D/README.md](../MyQuestionnaireVR-2D/README.md)
- [../TemporalExperienceTracerVR-2D/README.md](../TemporalExperienceTracerVR-2D/README.md)
- [../TemporalExperienceTracerVR-2D/docs/temporal-tracer-2d-workflow.md](../TemporalExperienceTracerVR-2D/docs/temporal-tracer-2d-workflow.md)
- [../MyQuestionnaireVR-2D/docs/experiment-chain-workflow.md](../MyQuestionnaireVR-2D/docs/experiment-chain-workflow.md)
