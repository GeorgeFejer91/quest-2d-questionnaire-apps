# TemporalExperienceTracerVR-2D

Native Android 2D panel app for Meta Horizon OS / Quest. This ports the Unity temporal experience tracer into a non-Unity Android panel app with configurable axes and loss-safe vector exports.

## App Contract

- Package: `org.questquestionnaire.temporaltracer2d`
- Activity: `.MainActivity`
- Intent action: `org.questquestionnaire.temporaltracer2d.RUN`
- Debug APK output: `Builds\TemporalExperienceTracerVR-2D.apk`
- Device exports: `/sdcard/Android/data/org.questquestionnaire.temporaltracer2d/files/TemporalTraceExports`

Launch extras mirror the questionnaire chain style: `mq.handoffSchema`,
`mq.sessionId`, `mq.triggerId`, `mq.blockId`, `mq.blockNumber`,
`mq.participantId`, `mq.participantName`, `mq.language`, `mq.experimentId`,
`mq.scenarioId`, `mq.trialId`, `mq.finishBehavior`, `mq.callerPackage`,
`mq.callerActivity`, `mq.nextPackage`, plus `mq.autoTrace=true` for
command-replay validation. For `mq.handoff.v1`, prefer
`mq.returnPendingIntent`; on completion the tracer saves SVG/CSV/JSON exports
first, then sends result extras through the return token before falling back to
the caller package/activity path.

## Trace Rules

The trace canvas enforces a left-to-right completion rule:

- drawing must begin in the blue start area just outside the 0 vertical axis,
- pre-axis movement after the first anchor point is ignored,
- x backtracking is ignored,
- saving is disabled until the trace reaches the configured right end gate,
- exported data is resampled to the configured `targetSampleCount`,
- the saved vector is anchored to exact `u=0` and `u=1`.

The screen trace is drawn as a smoothed Android path. The primary export is a
resolution-independent SVG with `viewBox` equal to the configured axis
dimensions. Its visible `trace-smooth-vector` path is built from raw captured
points, while hidden raw and normalized vector point polylines keep the capture
auditable. JSON and CSV companions include participant/session metadata,
timestamps, axis config, raw points, and resampled analysis points.

Kokoro-generated dimension audio lives under
`app\src\main\assets\tracer\audio\English\`. The app plays the resolved audio
asset when each dimension starts and records the audio file path in JSON
metadata.

## Config

Runtime config lives at:

`app\src\main\assets\tracer\TemporalTracerConfig.json`

The schema is `temporal-experience-tracer.config.v1`. Axis fields include:

- `viewBoxWidth`, `viewBoxHeight`
- `durationValue`, `durationUnit`
- `yMin`, `yMax`
- `startGatePercent`, `endGatePercent`
- `targetSampleCount`
- `topLabel`, `bottomLabel`
- `horizontalGridLabels`, `verticalGridLabels`

A simple static editor is available at:

`tools\tracer-config-editor\index.html`

## Commands

Validate config:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\validate-temporal-tracer-assets.ps1
```

Render local Android preview:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\render-temporal-tracer-visuals.ps1 -Sizes "1280x800"
```

Build APK:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-apk.ps1
```

Quest auto replay launch example:

```powershell
adb -s <serial> shell am start -n org.questquestionnaire.temporaltracer2d/org.questquestionnaire.temporaltracer2d.MainActivity `
  --ez mq.autoTrace true `
  --es mq.participantName AutoTemporal `
  --es mq.participantId AUTO001 `
  --es mq.language English `
  --es mq.sessionId temporal-smoke
```
