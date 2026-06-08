# Example Scenario APK

This folder is the public example source for the questionnaire builder's
`Load example APK` fallback.

Current files:

- `questionnaire-trigger-catalog.json`: the Aesthetic Chills 1 Trigger Demo
  manifest used by the hosted GUI when a user does not have their own APK yet.
  The generated questionnaire APK runs block 1 first, launches the
  Unity/stimulus APK, and Unity emits one passive `trigger_1_complete` trigger
  at the end of the running APK. The questionnaire APK owns the decision to
  resume block 2.
- `multi-trigger-demos/`: passive trigger catalog fixtures for simple Unity
  demos with 2, 3, and 4 trigger events. The hosted selector exposes the
  2-trigger fixture as "Passive 2 Trigger Demo"; the 4-trigger fixture remains
  for internal regression coverage rather than the current public demo picker.
- `unity-project/three-circle-trigger-demo/`: a minimal Unity source project
  with three scenes: big green circle, big blue circle, and big red circle. It
  emits `trigger_1_complete`, `trigger_2_complete`, and `trigger_3_complete`
  as passive events and is available as "Three Circle 3 Trigger Demo" in the
  hosted builder.
- `apk/`: generated local example scenario APKs. Recreate them with
  `MyQuestionnaireVR-2D/tools/build-example-scenario-apks.ps1`; the builder
  scans these APKs from disk and reads their embedded trigger manifests.
- `unity-project/`: place the matching Unity project or exported Unity build
  folder here when available.

The hosted builder currently offers three selectable demo preloads: Aesthetic
Chills 1 Trigger Demo, Passive 2 Trigger Demo, and Three Circle 3 Trigger Demo.
Each preload creates one configurable Block 1 plus exactly one return block for
each passive trigger in the selected catalog.

From a source checkout, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ..\MyQuestionnaireVR-2D\tools\build-example-scenario-apks.ps1
```

The local companion also attempts this build once when a preloaded demo is
selected and the expected APK files are absent. Trigger counts still come from
the APK's embedded `assets/mq/questionnaire-trigger-catalog.json`; the catalog
object in the GUI is only a display fallback.

For a rebuildable Unity project, copy the bridge scripts from
`MyQuestionnaireVR-2D/tools/unity/`. `QuestQuestionnairePassiveTriggerDemo.cs`
is the neutral demo component for the 2/3/4-trigger fixtures: configure its
`triggers` list with `trigger_1_complete`, `trigger_2_complete`, and so on.
The script emits only passive `mq.triggerId` events. It must not encode
questionnaire order, questionnaire type, scoring, or block routing.
