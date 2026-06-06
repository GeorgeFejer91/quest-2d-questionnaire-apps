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

The repo intentionally excludes generated Gradle state, build outputs, and
large validation evidence folders. The requested installable questionnaire APKs
are kept in `apks/`.

## Current APKs

| App | APK | Package | Launch action |
| --- | --- | --- | --- |
| Demographic questionnaire | `apks/demographic-questionnaire/MyQuestionnaireVR-2D.apk` | `org.mesmerprism.viscereality.questionnaires2d` | `org.mesmerprism.viscereality.questionnaires2d.RUN` |
| Temporal experience tracer | `apks/temporal-experience-tracer/TemporalExperienceTracerVR-2D.apk` | `org.mesmerprism.viscereality.temporaltracer2d` | `org.mesmerprism.viscereality.temporaltracer2d.RUN` |

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

Start at `workflow\README.md` for the durable lessons:

- how Quest 2D panel apps differ from Unity/OpenXR apps,
- how to structure manifests, launch extras, and exports,
- how to validate with render previews, command replay, and ADB,
- how ChainLink/orchestrator/source-hook/wrapper chaining fits together,
- what to check before treating an APK as ready for an experiment.

