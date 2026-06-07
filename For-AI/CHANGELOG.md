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
- Updated the direct Quest handoff validator with a pre-launch readiness gate:
  use `-WaitForReadySeconds 30` for supervised runs. If the headset is asleep
  or Horizon is already focused on the controller-required launch dialog, the
  trial is `blocked` with `initialUnityLaunchAttempted=false` and Unity is not
  launched.
- Added `MyQuestionnaireVR-2D/tools/validate-builder-to-quest-workflow.ps1`,
  a builder-to-Quest requirement matrix covering GUI/companion invocation,
  config validation, APK generation, local questionnaire/tracer render packs,
  Unity PendingIntent bridge static checks, direct handoff APK preflight, and
  explicit pending/blocked Quest trial gates.
- Enriched that matrix with compact evidence facts: APK byte counts and
  SHA-256 hashes, render counts/stages/sizes, direct handoff preflight package
  and trigger counts, Quest model/ADB readiness, and direct-trial decision gate
  counts when headset trials are run.
- Added companion endpoint `/api/validate-workflow` and a builder `Validate
  workflow` button so the hosted/offline GUI can trigger that matrix through
  trusted local PC software.
- Rebuilt the local `AweGreatDictatorUnity` demo APK after fixing the custom
  Android manifest path; the earlier APK launched Unity's stock Activity even
  though the trigger catalog named the custom return Activity.
- Converted companion workflow validation to a background job contract:
  `/api/validate-workflow` returns a `runId`/`jobId`, `/api/workflow-job`
  exposes status/log tails/summary paths, and the builder polls instead of
  blocking the page during long validation.
- Added a paired `Detect Quest` runner-panel action and `/api/quest-readiness`
  companion endpoint that performs a read-only ADB readiness probe and fills the
  Quest serial field before install/launch/direct-handoff gates.
- Added an explicit generated-APK install path: `Install APK on Quest` in the
  builder, `/api/install-apk` plus `/api/install-apk-job` in the companion, and
  `tools/install-questionnaire-apk-on-quest.ps1` for the reusable install gate.
- Added an explicit Quest command replay/export path: `Run replay/export` in
  the builder, `/api/quest-replay` plus `/api/quest-replay-job` in the
  companion, and `tools/run-questionnaire-replay-on-quest.ps1` as the wrapper
  around `quest-validate.ps1`.
- Split Quest readiness into ADB transport readiness and product-path launch
  readiness. `quest-adb-readiness.ps1` now records `productPathStatus`,
  blocked reasons, power/window evidence, and focus lines; the GUI warns when
  direct handoff or replay/export is blocked by headset sleep or Horizon launch
  dialogs.
- Added an explicit direct PendingIntent handoff runner: `Run direct handoff`
  in the builder, `/api/direct-handoff` plus `/api/direct-handoff-job` in the
  companion, and dry-run coverage in
  `tools/validate-builder-companion-workflow.ps1` using the real questionnaire,
  tracer, and Unity APKs for package/catalog preflight.
- Added a bounded `Ready wait (s)` control to the builder runner so direct
  handoff and full workflow jobs can wait longer for product-path readiness
  during supervised or unattended headset attempts without bypassing the
  asleep/headset-launch-dialog block classification.
- Updated direct handoff validation so one pre-product-path readiness block
  stops the run instead of waiting the full readiness window once per requested
  trial; GUI polling and companion job status now account for long readiness
  windows.
- Added companion stress coverage for direct handoff safety bounds: an
  out-of-range dry-run request must report backend-clamped `trialCount=10` and
  `waitForReadySeconds=28800`.
- Added `dryRunQuestDirectHandoff` for the aggregate `/api/validate-workflow`
  path so the companion stress ladder can prove direct-handoff trial/wait
  clamps without launching Unity or treating dry-run preflight as physical
  headset evidence.
- Added an explicit direct handoff strategy decision gate to direct dry-run,
  live-trial, and companion clamp summaries. Dry-run summaries can pass
  package/preflight checks, but they now report `candidateAStatus=dry-run-only`
  and `defaultDirectPendingIntentApproved=false` until real Quest trials and a
  manual headset pass provide product-path evidence.
- Added a dedicated trigger-catalog-to-block mapping gate to the aggregate
  builder-to-Quest matrix. Future agents should treat
  `trigger-block-mapping-contract` as the evidence row proving that the
  APK-first builder discovered triggers, created stable blocks, assigned
  questionnaire/tracer targets, and preserved `mq.handoff.v1` caller-return
  extras.
- Strengthened direct handoff preflight so it parses the Unity APK's embedded
  `questionnaire-trigger-catalog.json` and compares it against the source
  trigger catalog. Future APK-first validation should inspect packaged
  manifests, not only project-side catalog files.
- Tightened the builder-to-Quest local render evidence rows so questionnaire
  and temporal tracer render packs must reference real PNG artifacts with
  bytes, valid PNG dimensions, matching recorded hashes, and zero failed render
  rows before the matrix marks them as pass.
- Strengthened the companion workflow summary for `/api/generate-apk`: it now
  records generated APK file evidence, verifies the APK SHA-256 against the
  generator summary when builds are enabled, and records the render preview
  artifact gate produced by the same endpoint.
- Added `endToEndReceipt` to the companion workflow summary. Full runs now
  report `pass-with-physical-pending` only when GUI smoke, companion
  authorization, config save/validate, APK hash, local render artifacts,
  workflow matrix, and direct-handoff dry-run gates all pass; fast runs with
  intentionally skipped APK/render evidence report `partial-skipped-evidence`.
- Added a GUI-visible `workflowReceipt` to `/api/workflow-job`. Future
  workflow-button changes should keep the visible receipt aligned with the
  matrix artifact so users can see offline evidence readiness, failure/block
  counts, APK/render facts, and remaining physical Quest gates without opening
  nested JSON.
- Added GUI-visible `jobReceipt` objects for install, replay/export, and direct
  handoff runner jobs. Future local companion job endpoints should expose a
  compact receipt beside raw logs and summary paths so every dashboard step can
  be audited without spelunking nested artifacts.
- Added receipt API compatibility metadata to the local companion `/api/status`
  response. Future hosted/offline builder changes that depend on new companion
  response fields should advertise explicit capabilities and warn when a user
  connects an older local companion.
