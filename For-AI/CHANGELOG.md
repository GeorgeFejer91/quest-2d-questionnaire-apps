# For-AI Changelog

Record changes that affect future AI-agent behavior or project constraints.
Use absolute dates.

## 2026-06-06

- Established the root `For-AI/` folder as the canonical AI-agent documentation
  hub.
- Added first-read instructions through root `AGENTS.md` and
  `For-AI/START_HERE.md`.
- Recorded the browser/dashboard versus local companion/Quest APK boundary,
  including online/offline GUI parity and localhost companion rules.
- Recorded standing GitHub hygiene: after large coherent validated changes,
  commit and push when credentials and permissions are available.
- Made the questionnaire builder APK-first: fresh sessions must load a scenario
  APK or trigger catalog before downstream block editing, local dependency,
  validation, export, and APK-generation controls become active.
- Constrained the questionnaire builder UI to a vertically stacked one-page
  website with a fixed left navigation rail, including always-visible downloads
  for the local companion software and launchers.
- Added the `example-scenario-apk/` folder and a "Load example APK" builder
  fallback for users who do not yet have their own trigger-enabled APK.

## 2026-06-07

- Added Unity Quest video validation lessons covering real `VideoPlayer`
  markers, APK-internal video diagnostics, Unity batchmode pitfalls, APK
  manifest inspection, XR Simulation generated-file cleanup, and Horizon OS
  controller-required launch gate classification.

## 2026-06-07

- Added the `mq.handoff.v1` Quest handoff contract: XR apps launch 2D
  questionnaire/tracer panels with trigger metadata and a preferred
  `mq.returnPendingIntent`, falling back to caller package/activity only for
  compatibility.
- Updated ChainLink's intended role: plan compiler, trigger-mapping validator,
  and fallback router. Direct XR -> 2D panel -> same XR `PendingIntent`
  handoff is the preferred strategy until headset trials disprove it.
- Added the Chaplin/Awe demo stress target: trigger 1 launches a
  demographics-only questionnaire before video playback, trigger 2 launches the
  temporal experience tracer for awe after video completion.
- Added local handoff evidence files:
  `docs/xr-questionnaire-panel-handoff.md` and
  `examples/session-recipe.xr-questionnaire-panel-handoff.json`.
- Added `MyQuestionnaireVR-2D/tools/validate-universal-handoff-workflow.ps1`;
  the local no-headset pass on 2026-06-07 was
  `universal-handoff-20260607T010957Z`.
- Added `MyQuestionnaireVR-2D/tools/validate-builder-companion-workflow.ps1`;
  the full local companion pass on 2026-06-07 was
  `builder-companion-20260607T013607Z`, producing
  `Builds/viscereality-maia2-1.0.0.apk` through `/api/generate-apk`.
- Fixed the local companion for Windows PowerShell compatibility:
  pairing-token generation no longer requires `RandomNumberGenerator.Fill()`,
  and child-process stderr is captured as text before exit-code evaluation.
- Added `MyQuestionnaireVR-2D/tools/quest-direct-handoff-validate.ps1` for
  direct Quest handoff trials. It preflights APK package/activity/catalog
  agreement, launches Unity once, records focus/logcat/power/export evidence,
  and classifies asleep-headset or Horizon controller-required launch checks as
  `blocked`.
- Rebuilt the local `AweGreatDictatorUnity` demo APK after fixing the custom
  Android manifest path; the earlier APK launched Unity's stock Activity even
  though the trigger catalog named the custom return Activity.
