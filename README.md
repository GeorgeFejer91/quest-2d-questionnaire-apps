# Quest 2D Questionnaire Apps

This repository collects the native Android 2D panel apps used for Quest / Meta
Horizon OS questionnaire work:

- `MyQuestionnaireVR-2D`: demographic, MAIA-2, pictographic, slider, builder,
  ChainLink, orchestrator, hook-wrapper, and source-hook helper project.
- `TemporalExperienceTracerVR-2D`: temporal experience tracer 2D panel app with
  loss-safe SVG/CSV/JSON trace exports.
- `apks`: curated APK copies for installing the demographic questionnaire and
  temporal experience tracer questionnaire.
- `workflow`: the reusable Quest 2D questionnaire app workflow notes learned
  while building, chaining, validating, and packaging these apps.
- `For-AI`: documentation-only project memory and first-read instructions for
  AI agents working on this repository.

The repo intentionally excludes generated Gradle state, build outputs, and
large validation evidence folders. The requested installable questionnaire APKs
are kept in `apks/`.

## AI Agent Notes

Before changing this repository, AI agents must read [AGENTS.md](AGENTS.md),
then [For-AI/START_HERE.md](For-AI/START_HERE.md). The `For-AI` folder records
evolving project constraints, repeated operating rules, GitHub hygiene, and the
requirement that the questionnaire builder keep both online and offline GUI
paths available.

## Online Questionnaire Builder

Hosted GUI:

```text
https://georgefejer91.github.io/quest-2d-questionnaire-apps/questionnaire-builder/
```

The online page is a static browser GUI. For local file writes, dependency
checks, validation, and APK generation, start the local companion from
`MyQuestionnaireVR-2D\Start-QuestionnaireBuilderOnlineConnector.cmd` and enter
the printed pairing token in the page.

## Big Red Button Questionnaire Change Audio

Two MP3 notes for the Big Red Button questionnaire change request are published
under `docs/big-red-button-questionnaire-change-audio/`:

- [Playable GitHub Pages audio page](https://georgefejer91.github.io/quest-2d-questionnaire-apps/docs/big-red-button-questionnaire-change-audio/)
- [First questionnaire change](docs/big-red-button-questionnaire-change-audio/questionnaire-change-1-first-questionnaire-change.mp3)
- [Second questionnaire change excuse](docs/big-red-button-questionnaire-change-audio/questionnaire-change-2-second-questionnaire-change-excuse.mp3)

## XR Handoff Contract

The preferred product path is:

```text
foreground XR app -> 2D questionnaire/tracer panel -> same XR app
```

Use `mq.handoff.v1` trigger metadata plus a return `PendingIntent` for direct
return to the same Unity/XR activity. ChainLink remains the trigger plan
compiler, validator, and fallback router. See
`docs\xr-questionnaire-panel-handoff.md` and
`examples\session-recipe.xr-questionnaire-panel-handoff.json`.

## Current APKs

| App | APK | Package | Launch action |
| --- | --- | --- | --- |
| Demographic questionnaire | `apks/demographic-questionnaire/MyQuestionnaireVR-2D.apk` | `org.questquestionnaire.questionnaires2d` | `org.questquestionnaire.questionnaires2d.RUN` |
| Temporal experience tracer | `apks/temporal-experience-tracer/TemporalExperienceTracerVR-2D.apk` | `org.questquestionnaire.temporaltracer2d` | `org.questquestionnaire.temporaltracer2d.RUN` |

Install with ADB:

```powershell
adb -s <serial> install -r -d apks\demographic-questionnaire\MyQuestionnaireVR-2D.apk
adb -s <serial> install -r -d apks\temporal-experience-tracer\TemporalExperienceTracerVR-2D.apk
```

## Build From Source

Both projects are native Android projects. The local build scripts default to
the Unity 6000.2.7f2 bundled Android SDK, OpenJDK, and Gradle launcher because
that toolchain was already known to work on the Quest development machine.

Demographic questionnaire:

```powershell
cd MyQuestionnaireVR-2D
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-apk.ps1
```

Temporal experience tracer:

```powershell
cd TemporalExperienceTracerVR-2D
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-apk.ps1
```

Build outputs are written to each project's local `Builds\` folder, which is
ignored by git. Copy intentional release artifacts into `apks\` and update
`apks\checksums.sha256`.

## Workflow Notes

Start at `workflow\START_HERE.md` for the linear walkthrough from blank app to
validated Quest study APK. Then use `workflow\README.md` for the durable lesson
index:

- how Quest 2D panel apps differ from Unity/OpenXR apps,
- how to structure manifests, launch extras, and exports,
- how to validate with render previews, command replay, and ADB,
- how ChainLink/orchestrator/source-hook/wrapper chaining fits together,
- what to check before treating an APK as ready for an experiment.
