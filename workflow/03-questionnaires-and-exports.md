# Questionnaires And Exports

## Demographic Questionnaire App

`MyQuestionnaireVR-2D` recreates the questionnaire workflow as native Android
screens. The app supports language selection, participant details,
demographics, MAIA-2, pictographic selections, and custom slider blocks.

The questionnaire config contract lives in:

```text
MyQuestionnaireVR-2D\QuestionnaireConfigs\
```

The static browser builder lives in:

```text
MyQuestionnaireVR-2D\tools\questionnaire-config-editor\index.html
```

The builder should produce both:

- the APK input config,
- a quality report for study-design review.

Quality checks that mattered during development:

- English/Deutsch item-count parity,
- participant-burden counts,
- duplicate custom items,
- long wording,
- double-barreled wording,
- multiple negations,
- neutral punctuation and tone,
- command availability for APK/render generation.

## Temporal Experience Tracer

`TemporalExperienceTracerVR-2D` ports the Unity temporal tracer into a 2D panel.
The canvas enforces a left-to-right completion rule:

- drawing must begin inside the configured left start gate,
- x backtracking is ignored,
- save stays disabled until the line reaches the right end gate,
- exports are resampled to the configured target sample count,
- the saved vector is anchored exactly at normalized `u=0` and `u=1`.

The config lives at:

```text
TemporalExperienceTracerVR-2D\app\src\main\assets\tracer\TemporalTracerConfig.json
```

Axis fields include:

```text
viewBoxWidth, viewBoxHeight
durationValue, durationUnit
yMin, yMax
startGatePercent, endGatePercent
targetSampleCount
topLabel, bottomLabel
horizontalGridLabels, verticalGridLabels
```

## Data Safety

The questionnaire app owns questionnaire data. The orchestrator or caller can
receive result metadata, but it should not be the only place data lives.

Demographic exports:

```text
/sdcard/Android/data/org.questquestionnaire.questionnaires2d/files/QuestionnaireExports
```

Temporal tracer exports:

```text
/sdcard/Android/data/org.questquestionnaire.temporaltracer2d/files/TemporalTraceExports
```

Use unique run ids and participant/session metadata in filenames and rows so
repeated blocks do not overwrite each other.

Expected demographic export evidence:

- final JSON,
- final CSV,
- in-progress draft JSON,
- `session-index.jsonl`,
- answer counts and score counts matching the config.

Expected temporal tracer export evidence per trace:

- SVG vector with configured `viewBox`,
- point-level CSV,
- full JSON,
- `session-index.jsonl` row,
- session summary CSV row.

## Save Before Handoff

Always save before launching the next app, returning to the caller, or closing a
panel. This is the core reliability rule for headset study sessions where app
switching and system prompts can interrupt flow.

