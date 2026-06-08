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
- `apk/`: place the finished example scenario APK here when available.
- `unity-project/`: place the matching Unity project or exported Unity build
  folder here when available.

The hosted builder reads the trigger catalog from this folder. The APK and
Unity project are intentionally placeholders until the example assets are
provided.
