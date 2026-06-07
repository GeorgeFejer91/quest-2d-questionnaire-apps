# Start Here For AI Agents

This is the first-read checklist for any AI agent working in this repository.
Read it before changing code, documentation, APKs, builder UI, or validation
scripts.

## Required Read Order

1. [PROJECT_CONSTRAINTS.md](PROJECT_CONSTRAINTS.md)
2. [AGENT_OPERATING_RULES.md](AGENT_OPERATING_RULES.md)
3. [../workflow/START_HERE.md](../workflow/START_HERE.md)
4. The relevant app README:
   - [../MyQuestionnaireVR-2D/README.md](../MyQuestionnaireVR-2D/README.md)
   - [../TemporalExperienceTracerVR-2D/README.md](../TemporalExperienceTracerVR-2D/README.md)

For questionnaire builder work, also read:

1. [published-questionnaire-builder.md](published-questionnaire-builder.md)
2. [../MyQuestionnaireVR-2D/For-AI/questionnaire-builder-gui-constraints.md](../MyQuestionnaireVR-2D/For-AI/questionnaire-builder-gui-constraints.md)

For XR app -> 2D panel handoff work, also read:

1. [handoff-implementation-lessons.md](handoff-implementation-lessons.md)
2. [../docs/xr-questionnaire-panel-handoff.md](../docs/xr-questionnaire-panel-handoff.md)

For Unity Quest video stimulus work, also read:

1. [unity-quest-video-validation-lessons.md](unity-quest-video-validation-lessons.md)

## Repo Map

- `MyQuestionnaireVR-2D/`: native Android 2D questionnaire panel app, builder,
  APK generation, orchestrator, chain hooks, and Quest validation tools.
- `TemporalExperienceTracerVR-2D/`: native Android 2D temporal tracing panel app
  with SVG/CSV/JSON exports.
- `questionnaire-builder/`: staged static GitHub Pages copy of the builder UI.
  Do not treat this as the source GUI.
- `apks/`: curated installable APK drop folder and checksums.
- `workflow/`: durable human-readable workflow notes for architecture, build,
  validation, chaining, and release hygiene.
- `For-AI/`: AI-facing project memory only.

## First Checks

- Run `git status -sb` before editing and preserve unrelated user changes.
- Search existing docs before adding new rules; prefer linking durable docs over
  duplicating long explanations.
- For GUI changes, keep the online and offline builder paths aligned.
- For Quest-facing changes, follow the validation ladder in `workflow/`.
- For large coherent changes, update docs/change notes, validate, commit, and
  push when credentials and permissions are available.
