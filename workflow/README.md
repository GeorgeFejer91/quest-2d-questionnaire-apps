# Quest 2D Questionnaire Workflow

This folder is the reusable playbook for making Quest questionnaire apps as
native Android 2D panel apps.

Read in this order:

1. `01-architecture.md`: what a Quest 2D panel app is and why we use it.
2. `02-build-and-packaging.md`: project layout, toolchain, APK outputs, and
   release hygiene.
3. `03-questionnaires-and-exports.md`: questionnaire config, temporal tracer
   rules, data safety, and export contracts.
4. `04-chaining-and-validation.md`: ChainLink, orchestrator, wrapper/source
   hooks, ADB validation, and evidence levels.
5. `05-release-checklist.md`: the final checklist before putting an APK on a
   headset for a study.

The short version: keep questionnaires as ordinary Android 2D panels, make the
questionnaire app own its data, pass experiment context through explicit intent
extras, validate locally before using the headset, and only treat a chain as
experiment-ready when the active immersive app can provide a real completion
signal or a human gate witnesses that completion.

