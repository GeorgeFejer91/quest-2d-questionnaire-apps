# Agent Operating Rules

These are repeated instructions for AI agents working in this repository.

## Start Of Work

- Read `AGENTS.md`, then `For-AI/START_HERE.md`.
- Run `git status -sb` before editing.
- Preserve unrelated user changes, including untracked folders and modified
  files outside the task.
- Search before changing. The repo already has detailed workflow and app docs.

## During Work

- Keep edits scoped to the requested behavior and nearby documentation.
- Prefer existing scripts, launchers, validation commands, and terminology.
- For questionnaire builder changes, update the source GUI under
  `MyQuestionnaireVR-2D/tools/questionnaire-config-editor/` and regenerate the
  staged `questionnaire-builder/` copy through the publish script.
- Do not manually change only the staged GitHub Pages copy unless the task is
  explicitly about staged static files.
- Keep online and offline builder behavior aligned.
- Keep the browser/dashboard boundary clear: the browser controls and previews;
  the local companion and Quest APKs do trusted local and experiment work.
- After GUI or website edits, open the resulting website URL before finishing.
  For hosted builder changes, regenerate the Pages copy, commit, push, and
  verify the public URL so the change is actually online.

## Validation

- Run the narrowest relevant validation for the changed area.
- Documentation-only edits should at least check links, stale references, and
  `git status -sb`.
- Builder edits usually need
  `MyQuestionnaireVR-2D/tools/validate-questionnaire-builder.ps1`.
- Generated APK or Quest behavior changes need the appropriate local build,
  render, replay/export, foreground, and manual hardware gates described in
  `workflow/`.

## Documentation And Change Notes

- Update docs when changing architecture, launch behavior, data/export
  contracts, validation evidence, or user-facing workflows.
- Add a short entry to `For-AI/CHANGELOG.md` when a change creates a future
  agent constraint or changes the agent operating model.
- Summarize what changed and what validation ran in the final handoff.

## GitHub Hygiene

- After large coherent changes, validate, update documentation/change notes,
  commit, and push to GitHub when credentials and permissions are available.
- If commit or push is not possible, clearly report what remains local and why.
- Run `git status -sb` before committing and inspect the staged list.
- Run `git log --stat -1` after committing to confirm the intended files
  landed.
- Do not commit generated state, transient evidence, local machine config, or
  large APKs outside the curated `apks/` policy.
