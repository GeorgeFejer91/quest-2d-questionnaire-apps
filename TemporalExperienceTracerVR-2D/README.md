# TemporalExperienceTracerVR-2D

Native Android 2D panel app for Meta Horizon OS / Quest. This ports the Unity temporal experience tracer into a non-Unity Android panel app with configurable axes and loss-safe vector exports.

## App Contract

- Package: `org.mesmerprism.viscereality.temporaltracer2d`
- Activity: `.MainActivity`
- Intent action: `org.mesmerprism.viscereality.temporaltracer2d.RUN`
- Debug APK output: `Builds\TemporalExperienceTracerVR-2D.apk`
- Device exports: `/sdcard/Android/data/org.mesmerprism.viscereality.temporaltracer2d/files/TemporalTraceExports`

Launch extras mirror the questionnaire chain style: `mq.sessionId`, `mq.participantId`, `mq.participantName`, `mq.language`, `mq.experimentId`, `mq.scenarioId`, `mq.trialId`, `mq.finishBehavior`, `mq.callerPackage`, `mq.nextPackage`, plus `mq.autoTrace=true` for command-replay validation.

## Trace Rules

The trace canvas enforces a left-to-right completion rule:

- drawing must begin inside the configured left start gate,
- x backtracking is ignored,
- saving is disabled until the trace reaches the configured right end gate,
- exported data is resampled to the configured `targetSampleCount`,
- the saved vector is anchored to exact `u=0` and `u=1`.

The primary export is SVG with `viewBox` equal to the configured axis dimensions. JSON and CSV companions include participant/session metadata, timestamps, axis config, raw points, and resampled points.

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
adb -s <serial> shell am start -n org.mesmerprism.viscereality.temporaltracer2d/org.mesmerprism.viscereality.temporaltracer2d.MainActivity `
  --ez mq.autoTrace true `
  --es mq.participantName AutoTemporal `
  --es mq.participantId AUTO001 `
  --es mq.language English `
  --es mq.sessionId temporal-smoke
```

