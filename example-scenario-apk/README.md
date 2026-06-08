# Example Scenario APK

This folder is the public example source for the questionnaire builder's
`Load example APK` fallback.

Current files:

- `questionnaire-trigger-catalog.json`: small trigger manifest used by the
  hosted GUI when a user does not have their own APK yet. The catalog mirrors
  the V2 stimulus demo: the generated questionnaire APK runs block 1 first,
  launches the Unity/stimulus APK, and Unity emits one passive
  `trigger_1_complete` trigger at the end of the running APK. The
  questionnaire APK owns the decision to
  resume block 2.
- `multi-trigger-demos/`: passive trigger catalog fixtures for simple Unity
  demos with 2, 3, and 4 trigger events. They are intentionally catalog-only
  examples so the builder can prove `Block 1 + scanned triggers` behavior
  without committing Unity APK build artifacts.
- `apk/`: place the finished example scenario APK here when available.
- `unity-project/`: place the matching Unity project or exported Unity build
  folder here when available.

The hosted builder reads the trigger catalog from this folder. The APK and
Unity project are intentionally placeholders until the example assets are
provided.

For a rebuildable Unity project, copy the bridge scripts from
`MyQuestionnaireVR-2D/tools/unity/`. `QuestQuestionnairePassiveTriggerDemo.cs`
is the neutral demo component for the 2/3/4-trigger fixtures: configure its
`triggers` list with `trigger_1_complete`, `trigger_2_complete`, and so on.
The script emits only passive `mq.triggerId` events. It must not encode
questionnaire order, questionnaire type, scoring, or block routing.
