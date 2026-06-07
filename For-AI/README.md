# For AI Agents

This folder is the canonical AI-agent documentation hub for the repository.
Read it before changing code, docs, APK packaging, the questionnaire builder,
or Quest validation workflows.

Start with:

1. `START_HERE.md`
2. `PROJECT_CONSTRAINTS.md`
3. `AGENT_OPERATING_RULES.md`

Related handoffs:

- `published-questionnaire-builder.md`: GitHub Pages and online/offline builder
  publication notes.
- `handoff-implementation-lessons.md`: PendingIntent-first Quest handoff,
  ChainLink fallback, and local validation lessons.
- `unity-quest-video-validation-lessons.md`: Unity Quest video stimulus build,
  validation, manifest, and protected launch-dialog lessons.
- `../MyQuestionnaireVR-2D/For-AI/README.md`: app-specific notes for the
  questionnaire project.

Current repository state:

- Repository: `GeorgeFejer91/quest-2d-questionnaire-apps`
- Visibility: public
- GitHub Pages source: `main` branch, repository root `/`
- Published builder URL:
  `https://georgefejer91.github.io/quest-2d-questionnaire-apps/questionnaire-builder/`
- Published builder files live under repository root `questionnaire-builder/`.
- The editable source GUI lives at
  `MyQuestionnaireVR-2D/tools/questionnaire-config-editor/index.html`.

Do not treat `questionnaire-builder/index.html` as the primary source of truth.
It is the staged static Pages copy. Update the source GUI in
`MyQuestionnaireVR-2D/tools/questionnaire-config-editor/index.html`, then run
the publish script documented in `published-questionnaire-builder.md`.

Keep this folder documentation-only. Do not store generated outputs, APKs,
experiment exports, logs, screenshots, or private participant data here.
