# Example Scenario APK

This folder is the public example source for the questionnaire builder's
`Load example APK` fallback.

Current files:

- `questionnaire-trigger-catalog.json`: small trigger manifest used by the
  hosted GUI when a user does not have their own APK yet. The current catalog
  mirrors the Chaplin/Awe demo: trigger 1 starts demographics before video
  playback, and trigger 2 starts the temporal awe tracer after video
  completion.
- `apk/`: place the finished example scenario APK here when available.
- `unity-project/`: place the matching Unity project or exported Unity build
  folder here when available.

The hosted builder reads the trigger catalog from this folder. The APK and
Unity project are intentionally placeholders until the example assets are
provided.
