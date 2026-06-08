# For-AI Changelog

Record changes that affect future AI-agent behavior or project constraints.
Use absolute dates.

## 2026-06-08

- Updated the V2 builder rule: Block 1 is configurable and demographics is only
  a suggested CSV-backed preload/template. Hosted/product mode may preselect
  demographics for the demo path, but future agents must preserve user control
  over Block 1 and must not convert Unity trigger metadata into questionnaire
  routing decisions.
- Updated the questionnaire block builder toward a Qualtrics-like CSV workflow:
  scanned Unity triggers create later return-block slots; users add vertical
  questionnaire elements per block, download type templates/preloads, upload
  completed CSV/ZIP files, and map triggers from the 2D questionnaire protocol.
- Added multi-trigger GUI regression coverage and public passive catalog
  fixtures for 2, 3, and 4-trigger Unity/stimulus demos. Future builder changes
  must preserve the rule that rendered block segments equal one configurable
  Block 1 plus exactly one later return block per scanned passive trigger.
- Added the source-level three-circle Unity demo as a hosted-builder preload:
  green circle -> trigger 1, blue circle -> trigger 2, red circle -> trigger 3.
  The demo remains passive and product-branded; the builder preload must create
  Block 1 plus three return blocks without Unity-side questionnaire decisions.
- Renamed the current one-trigger preload to "Aesthetic Chills 1 Trigger Demo"
  and fixed the hosted demo picker to exactly three visible choices for now:
  Aesthetic Chills 1 Trigger Demo, Passive 2 Trigger Demo, and Three Circle 3
  Trigger Demo. Keep the 4-trigger fixture available for internal regression
  coverage, not as a public picker option unless the product workflow changes.

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

- Renamed the project-facing brand and technical defaults for open-source
  release readiness: use "Quest 2D Questionnaire Apps" / "Quest Questionnaire
  Builder", `org.questquestionnaire.*` package namespaces,
  `quest-questionnaire-*` questionnaire IDs, `questquestionnaire.*` schema
  tags, `custom_slider` slider blocks, and neutral
  `org.questquestionnaire.stimulusdemo` placeholders. Future agents should not
  reintroduce legacy project, organization, personal, lab, or unrelated
  Unity-study names into source, docs, generated defaults, or staged hosted UI.
- Added the study-logic ownership directive: the generated 2D questionnaire APK
  owns questionnaire order, trigger interpretation, participant/session state,
  block progression, scoring, and exports. Unity/stimulus APKs are passive
  trigger emitters and should send `mq.triggerId` only, with `mq.blockId`,
  `mq.blockNumber`, and `mq.questionnaireMode` treated as legacy/developer
  fallbacks rather than the product decision surface.
- Added builder and companion validation warnings for Unity trigger catalogs
  that contain questionnaire-routing hints such as `recommendedMode` or
  `questionnaireMode`, preserving legacy behavior while steering V2 toward
  questionnaire-owned protocol logic.
- Added hosted-visible questionnaire CSV template controls and builder stress
  coverage for type-oriented templates. Treat MAIA-2 as a preloaded named
  questionnaire; generic CSV templates should describe question types such as
  slider/VAS, Likert, multiple choice, text entry, and temporal tracer
  dimensions. The current APK runtime supports uploaded slider/VAS items end
  to end, while unsupported uploaded types must fail loudly until implemented.
- Added Unity Quest video validation lessons covering real `VideoPlayer`
  markers, APK-internal video diagnostics, Unity batchmode pitfalls, APK
  manifest inspection, XR Simulation generated-file cleanup, and Horizon OS
  controller-required launch gate classification.
- Added `MyQuestionnaireVR-2D/tools/validate-hosted-questionnaire-builder.ps1`
  so hosted GUI changes can prove source/staged/live GitHub Pages parity and
  required runner controls/endpoints after publication. The companion workflow
  validator now includes this hosted publication gate in its end-to-end
  receipt unless explicitly skipped.
- Added `MyQuestionnaireVR-2D/tools/audit-universal-handoff-readiness.ps1` to
  summarize the original Universal Quest Handoff requirements from current
  receipts and distinguish offline proof from the remaining physical Quest
  gates. The audit now promotes the demo Unity APK and public example trigger
  catalog as their own evidence row.
- Added `MyQuestionnaireVR-2D/tools/new-direct-handoff-manual-signoff.ps1` and
  wired the readiness audit to consume structured manual headset signoff
  summaries. Future agents should not close the direct handoff manual gate from
  a loose note; the signoff must reference a real non-dry-run product-path
  summary and confirm the observed headset sequence.
- Recorded the Quest Unity input-modality rule: generic demo/stimulus APKs
  should support both hands and controllers, advertise optional hand tracking,
  and treat Horizon controller-required launch dialogs as build/preflight
  issues unless controller-only input is an explicit study constraint.
- Added builder/runtime support for 2D-first launcher mode: a generated
  questionnaire APK can default to demographics from Meta Home and then open
  the Unity APK with `finishBehavior=openNext`, while later Unity-triggered
  blocks still use `resumeCaller`.
- Added V2 block-sequence support: the builder can configure a block 1
  questionnaire sequence and a Unity-return sequence, serialize
  `questionnaireSequence`, and keep Unity restricted to passive `mq.triggerId`
  emission while the 2D APK chooses the next block from protocol state.
- Added the template/metafile customization rule for the builder and the first
  pictographic ZIP path: users can download placeholder PNGs plus a manifest,
  replace them locally, reupload the ZIP, and generate config assets without a
  bespoke pictographic UI.
- Added `QuestionnaireConfigs/examples/quest-questionnaire-stimulus-2d-first-demo.config.json`
  and hardened Android tests so generated custom configs can run the full
  unit-test/APK/render/direct-handoff-preflight spine after assets are applied.
- Updated the Universal Quest Handoff readiness audit to promote the latest
  questionnaire-first builder-to-Quest receipt as a first-class 2D-first
  launcher evidence row, leaving only the real headset trial/signoff gates
  pending when offline APK, render, and dry-run preflight proof is present.
- Added `quest-2d-first-launcher-validate.ps1` and taught the readiness audit
  to track the participant-facing 2D-first front door as its own physical gate:
  dry-run APK/config preflight can pass offline, but a real Quest trial must
  still prove questionnaire-first launch, demographics export, and Unity focus.
- Preserved `chainDefaults.startMode` in the packaged runtime config so
  generated questionnaire APKs remain self-describing evidence for
  `questionnaireFirst` launcher mode.
- Exposed the 2D-first launcher gate in the questionnaire builder companion and
  GUI as `/api/2d-first-launcher`, `/api/2d-first-launcher-job`, and `Run
  2D-first launch`. The one-button headset sequence now runs this front-door
  gate before direct handoff so the GUI checks the participant-facing
  questionnaire-first path as well as the Unity-triggered return path.
- Exposed the Universal Handoff readiness audit through the companion and GUI
  as `/api/handoff-readiness-audit` and `Audit readiness`, returning an
  `auditReceipt` so the website can show proven offline requirements and the
  exact physical Quest gates still pending.
- Promoted 2D-first launcher mode from an allowed variant to the recommended
  default front door for demographics-before-stimulus participant studies. A
  generated questionnaire APK may be pinned to one Unity package/activity via
  builder config, but reusable Android source should not hard-code a single
  Unity target.
- Exposed the structured manual headset signoff helper through the local
  companion and GUI as `/api/direct-handoff-manual-signoff` and `Prepare
  manual signoff`, returning a `manualSignoffReceipt`. The companion stress
  validator now checks auth and template generation while keeping the actual
  physical signoff pending until a filled operator JSON is validated.
- Added a Universal Handoff physical gate packet helper and GUI action as
  `/api/physical-gate-packet` and `Prepare physical packet`. Future agents
  should use it after `pass-with-physical-pending` audits to package the
  latest audit, remaining headset gates, manual signoff template, and operator
  runbook without claiming any live Quest gate has passed.
- Hardened manual signoff and physical gate packet artifact writers for
  Windows long paths after the companion stress ladder exposed missing-summary
  false negatives at the 260-character boundary.
- Updated `Prepare physical packet` so it passes the currently visible
  readiness audit path when available, keeping operator packets tied to the
  evidence displayed in the GUI rather than silently rediscovering the latest
  artifact on disk.
- Extended `Run headset sequence` so the one-button path finishes by running
  the readiness audit and preparing the physical gate packet from that audit.
  Future sequence buttons should end with an auditable completion/packet
  boundary, not just the last launch or preflight job.
- Clarified the recommended demographics-before-video flow:
  `2D demographics -> Unity Start experiment gate -> Unity video/stimulus`.
  Future agents should not make the first demographics block depend on
  launching a panel over an already-playing Unity video when the study can
  start cleanly from the 2D questionnaire APK.
- Hardened the questionnaire builder smoke test so `Run headset sequence`
  proves its ordered companion-endpoint spine and verifies the physical packet
  payload prefers the visible readiness audit before falling back to companion
  summary discovery.
- Added stop-condition guardrails to the physical gate packet and manual
  signoff template: no controller-required launch dialog for generic
  demo/stimulus APKs, no Meta menu or ADB foreground recovery, and frozen Unity
  video after panel return is a Unity panel-focus/media-resume failure.
- Hardened the companion workflow validator so manual signoff prep must emit
  the controller-dialog, Unity Start experiment, frozen-video, Meta menu, and
  ADB foreground-switching guardrails before the offline stress ladder can
  pass.
- Exposed manual signoff and physical packet stop-condition guardrail checks in
  companion receipts and GUI receipt text, with builder smoke coverage so the
  website keeps showing the 2D-first/start-gate, controller-dialog,
  frozen-video/video-resume, and no Meta/ADB recovery rules.
- Made hosted final-product builder loads automatically default generated APKs
  to a demographics-first front door: `questionnaireFirst`, demographics,
  `openNext` into the scanned Unity package/activity. Manifest trigger
  assignments remain for later Unity-triggered blocks; when no demographics
  manifest trigger exists, the front door uses the stable
  `study_start_demographics` id.
- Added participant-facing generated APK naming for questionnaire-first
  builds: the builder/runtime config now carries `appDisplayName`, the APK
  generator stamps Android `app_name`, and the first panel heading reads
  `Start Experiment | <target APK label>`.
- Added `operator-guardrail-receipts` to the local companion capability
  contract and hosted builder validator so the online GUI can detect older
  companions that do not expose checked operator guardrail receipt fields.
- Hardened physical packet portability: the companion stress validator now
  downloads the physical gate packet as an evidence bundle and requires the
  packet summary, operator runbook, manual signoff template, and manual signoff
  summary to be present in the zip. The builder smoke test verifies that the
  GUI download target can use a visible physical packet summary.
- Tightened the portable physical packet bundle check to require the linked
  Universal Handoff readiness audit summary as well, so the operator zip
  carries both the runbook/signoff artifacts and the requirement matrix it was
  prepared from.

## 2026-06-07

- Added the `mq.handoff.v1` Quest handoff contract: XR apps launch 2D
  questionnaire/tracer panels with trigger metadata and a preferred
  `mq.returnPendingIntent`, falling back to caller package/activity only for
  compatibility.
- Updated ChainLink's intended role: plan compiler, trigger-mapping validator,
  and fallback router. Direct XR -> 2D panel -> same XR `PendingIntent`
  handoff is the preferred strategy until headset trials disprove it.
- Added the Quest questionnaire stimulus demo stress target: trigger 1 launches a
  demographics-only questionnaire before video playback, trigger 2 launches the
  temporal experience tracer after stimulus completion.
- Added local handoff evidence files:
  `docs/xr-questionnaire-panel-handoff.md` and
  `examples/session-recipe.xr-questionnaire-panel-handoff.json`.
- Added `MyQuestionnaireVR-2D/tools/validate-universal-handoff-workflow.ps1`;
  the local no-headset pass on 2026-06-07 was
  `universal-handoff-20260607T010957Z`.
- Added `MyQuestionnaireVR-2D/tools/validate-builder-companion-workflow.ps1`;
  the full local companion pass on 2026-06-07 was
  `builder-companion-20260607T013607Z`, producing
  `Builds/quest-questionnaire-maia2-1.0.0.apk` through `/api/generate-apk`.
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
- Rebuilt the local `QuestionnaireStimulusUnity` demo APK after fixing the custom
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
- Added GUI-visible `generationReceipt` evidence to `/api/generate-apk` so the
  hosted/offline builder can show generated APK byte/hash evidence and local
  render-preview artifact status immediately after the APK-generation step.
- Added token-protected `/api/artifact-preview` support to the local companion
  and GUI so render-preview PNGs referenced by `generationReceipt` can be
  visually inspected from the hosted/offline builder without exposing a generic
  local file server.
- Promoted questionnaire and temporal tracer sample PNGs into
  `workflowReceipt` and added the `workflow-render-previews` companion
  capability so the GUI's full workflow validation step can visually inspect
  both local render families through the same protected preview endpoint.
- Added a GUI-visible `Preflight only` mode for the dedicated direct handoff
  runner. The hosted/offline builder now calls `/api/direct-handoff` with
  `dryRun=true` and `skipInstall=true` by default for package/catalog
  preflight, and the companion advertises `direct-handoff-preflight` so stale
  local launchers can be detected.
- Wired the same `Preflight only` mode into the aggregate `Validate workflow`
  button. The GUI now sends `dryRunQuestDirectHandoff=true` and
  `skipInstall=true` to `/api/validate-workflow` by default, and the builder
  smoke test asserts the dry-run and live-trial payloads separately.
- Fixed two browser-started workflow gaps exposed by clicking the real
  `Validate workflow` button: aggregate dry-run direct handoff no longer
  requires a Quest serial, and the default companion launcher now discovers the
  legacy `MyQuestionnaireVR` reference project as a workspace sibling when it
  is not nested inside the repo.
- Updated `validate-builder-to-quest-workflow.ps1` and the companion workflow
  validator to snapshot and restore packaged questionnaire source assets around
  temporary APK-generation checks. The matrix now includes
  `workflow-preserves-source-assets`, so future workflow stress runs should not
  leave tracked Android asset files dirty.
- Added a token-protected companion evidence-bundle endpoint and GUI download
  button. Bundles are built from artifact-root JSON summaries and referenced
  JSON/TXT/LOG/CSV/PNG evidence, include a manifest, and are now covered by the
  companion workflow validator.
- Added a GUI `Run headset sequence` orchestration button that reuses the
  companion save, validate, APK generation, Quest readiness, install,
  replay/export, and direct handoff endpoints in order, with local render
  preview forced for the evidence-oriented sequence.
- Fixed Temporal Tracer launch parsing so Unity string extras such as
  `mq.autoTrace="true"` activate command replay the same way ADB boolean extras
  do.
- Recorded that Unity source apps must explicitly own panel-focus media pause:
  pause before launching panels, poll for matching trigger completions, clear
  handled result intents, and use per-trigger return callbacks rather than
  relying on Quest foreground switching as a video pause/resume contract.
- Updated direct handoff validation so final headset/display sleep after the
  product path has begun is classified as a blocked evidence window rather than
  a direct handoff failure when no fatal app logs are present.
- Added an opt-in `Wake before readiness` live-trial control for direct
  handoff attempts. The GUI sends it only when `Preflight only` is cleared, the
  companion passes `-WakeBeforeReadiness`, and summaries/receipts record
  `wakeBeforeReadiness` so wake-assisted unattended attempts remain auditable.
- Captured a one-trial live Quest direct-handoff pass at
  `quest-direct-handoff\20260607T111059Z`: trigger 1 questionnaire return,
  Unity video resume/non-black frame markers, trigger 2 Temporal Tracer export,
  and final Unity completion all passed. Candidate A still requires 10 clean
  trials plus the manual headset gate before default approval.
- Updated the reusable Unity bridge template and static validators with the
  panel-focus fixes proven in the demo: source apps can clear consumed result
  intents via `ClearQuestionnaireResult()`, and return PendingIntent request
  keys include trigger, chain-step, and block identity to avoid stale callback
  reuse across panel launches.
- Strengthened direct handoff Quest summaries with ordered Unity media
  liveness evidence after panel return. Trials now record `mediaLiveness`,
  `unity-video-*` failure reasons, and a decision-gate liveness failure count
  when the panel returns but the Unity video does not emit playback plus
  frame/non-black markers afterward.
- Added the Unity start-experiment gate pattern for source stimulus APKs:
  product runs can wait for a foreground Unity `Start experiment` input before
  trigger 1, while automated direct-handoff validation bypasses that human gate
  only through explicit `mq.validationAutoStart=true` evidence markers.
- Hardened source-asset snapshot/restore helpers for Windows long paths after
  the companion stress ladder exposed a `Copy-Item` failure at 260 characters
  for nested pictographic assets under descriptive artifact run ids.
- Tightened the Universal Handoff readiness audit so the evidence-bundle
  requirement consumes portable physical-gate packet bundle proof after a packet
  has been prepared. The companion workflow validator now reruns the readiness
  audit post-packet and requires the packet summary, linked readiness audit,
  runbook, operator signoff template, and manual signoff summary to appear in
  that audit evidence.
- Reframed the hosted questionnaire builder as the final user-facing product
  instead of a development cockpit. GitHub Pages mode now hides development-only
  validation/stress/audit controls, defaults off developer unit-test and direct
  handoff options, and keeps the visible path focused on companion downloads,
  APK trigger scan, questionnaire-type assignment, APK generation, Quest
  detection, and APK install.
- Kept companion/dependency setup outside the APK gate in hosted final-product
  mode: download links, dependency status/install controls, connector URL/token
  fields, and Quest detection are available before an APK trigger catalog is
  loaded, while Generate APK and Install APK remain trigger-manifest gated.
- Added `validate-unity-input-modality.ps1` and wired it into the
  builder-to-Quest matrix as `unity-input-modality-guardrails`. Generic
  demo/stimulus Unity builds now have a no-headset gate for optional hand
  tracking, hand tracking permission/metadata, Quest controller OpenXR
  profiles, hand OpenXR profiles, and build-script preservation before live
  trials can stumble into Horizon controller-required launch dialogs.
- Promoted `unity-input-modality-guardrails` into the Universal Handoff
  readiness audit so completion summaries keep the controller-dialog prevention
  gate visible alongside APK/catalog, render, companion, and physical Quest
  gates.
- Extended the opt-in wake-before-readiness protocol from direct handoff to the
  shared `quest-adb-readiness.ps1` probe and replay/export wrapper. Offline
  verification jobs can now send one recorded `KEYCODE_WAKEUP`, re-probe
  product-path readiness, and keep blocked headset/display states auditable.
- Updated the Quest verification runbook: live replay/export, 2D-first launch,
  and direct handoff claims must use explicit headset serials, record readiness
  and wake evidence, and leave the physical gate blocked/pending when the
  headset remains asleep or Horizon launch-check dialogs are focused.
