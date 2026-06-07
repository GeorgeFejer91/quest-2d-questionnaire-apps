# Handoff Implementation Lessons

This note records reusable problem-solution lessons from implementing the
universal XR-to-2D-panel handoff.

## PendingIntent First, Component Return Second

Problem: returning from a reusable 2D panel to the exact foreground XR Activity
is brittle when only `mq.callerPackage` and `mq.callerActivity` are passed.

Solution: the XR app should create a `PendingIntent.getActivity()` return token
targeting its own `singleTop` Activity and pass it as `mq.returnPendingIntent`.
The panel saves exports, sends that token with result extras, and uses
caller-package return only as compatibility fallback.

Generalizable rule: for cross-package app handoffs, prefer a caller-created
return token over reconstructing the caller component inside the callee.

## Trigger Completion Is Not Sequence Advancement

Problem: when ChainLink routes by `mq.triggerId`, treating panel completion as
`nextBlock` can accidentally launch the next trigger's questionnaire before the
XR app emits that trigger.

Solution: trigger-routed blocks return to ChainLink with a distinct
`triggerComplete` command. ChainLink records the result, returns to the source
XR app, and waits for the next real trigger.

Generalizable rule: sequence plans and event-routed plans need different
completion semantics even if both launch the same APKs.

## Demo Modes Must Be Runtime Modes

Problem: a GUI label such as "Demographics" is misleading if Android runtime
mode `baseline` still runs demographics plus MAIA-2.

Solution: add `demographics` as a real questionnaire mode, export it as such,
and stop after the participant form.

Generalizable rule: block-builder labels must map to actual runtime behavior,
not just study-design intent.

## Local Renderers Are First-Class Stress Gates

Problem: headset screenshots are slow and can conflate rendering, focus, and
capture-route issues.

Solution: use local Android render preview gates for the questionnaire and
temporal tracer before any Quest install loop, and use the Unity video render
gate before trusting headset screenshots.

Generalizable rule: use local renderers to catch visual and layout regressions
before device-facing evidence collection.

## Render Summaries Must Verify Image Artifacts

Problem: a validation matrix can claim "local render pass" from the existence
of a `render-summary.json` even when the referenced PNG files are missing,
empty, stale, corrupt, or dimensionally inconsistent with the screen size under
test. That weakens the workflow because local renderers are supposed to be the
fast visual evidence before headset screenshots.

Solution: the builder-to-Quest matrix now inspects every referenced
questionnaire and temporal tracer PNG. It records file existence, byte count,
SHA-256, PNG header dimensions, dimension mismatches, hash mismatches, and a
compact sample of image evidence. The render requirement passes only when the
summary exists, every render row is non-failing, and all PNG artifacts pass the
artifact gate.

Generalizable rule: whenever a summary points at evidence files, validate the
files at the matrix level. Treat summary JSON as an index, not as the visual
artifact itself.

## Companion APIs Need Real HTTP Stress Tests

Problem: a builder smoke test can prove that browser JavaScript emits the right
JSON, while still missing failures in the local companion path used by the
hosted GUI.

Solution: add a validator that starts the companion, checks pairing-token
authorization, saves the generated handoff config through `/api/save-config`,
validates it through `/api/validate-config`, and generates/render-previews it
through `/api/generate-apk`.

Generalizable rule: when a static web GUI delegates work to local software,
stress the HTTP boundary itself, including auth failures and long-running
commands.

## Companion Generate Needs Artifact Receipts

Problem: a local companion endpoint can return `status=ok` for APK generation
while the top-level workflow summary only records a nested summary path. That
is too indirect for the user-facing promise "the website tells the PC software
to create an APK"; reviewers should not have to open multiple nested JSON files
to know whether an APK and render pack actually exist.

Solution: `/api/generate-apk` now returns a compact `generationReceipt` beside
the raw generator summary. The receipt proves the generated APK exists, records
bytes and SHA-256, checks the summary hash, and promotes the local render PNG
artifact gate when previews are requested. The companion workflow validator
also reads the generator summary immediately, verifies the generated APK exists
and matches the recorded SHA-256 when a build is requested, verifies the
endpoint's render-preview PNG artifact gate when previews are requested, and
promotes those facts as `apkEvidence`, `renderEvidence`, and
`generationReceipt`.

Generalizable rule: every trusted local endpoint that produces a user-visible
artifact should return or promote a compact receipt for that artifact: path,
existence, bytes, hash, and the status of any visual preview gate.

## Native stderr Is Not Failure By Itself

Problem: Gradle can write harmless notes to stderr while exiting successfully.
Capturing child output with `2>&1` under `$ErrorActionPreference = 'Stop'` can
turn those notes into terminating PowerShell errors and make a healthy endpoint
return 500.

Solution: companion child-process wrappers should capture stderr as text under
a local `Continue` error preference, then decide success only from the child
exit code and required artifacts.

Generalizable rule: distinguish process exit status from output stream class;
stderr is evidence to record, not automatically a failure.

## Token Generators Must Match The Runtime

Problem: `RandomNumberGenerator.Fill()` is not available in the Windows
PowerShell/.NET runtime on this development machine, even though it exists in
newer .NET APIs.

Solution: use `RandomNumberGenerator.Create().GetBytes(...)` for companion
pairing tokens and validation tokens.

Generalizable rule: local Windows automation scripts should use APIs available
in the target PowerShell runtime, not only modern .NET examples.

## Direct Handoff Needs Activity And Power Preflight

Problem: a trigger catalog can name a custom Unity Activity while the built APK
still launches Unity's stock `com.unity3d.player.UnityPlayerGameActivity`. In
that state the 2D panel can save successfully, but return-to-caller evidence is
not testing the intended component.

Solution: direct handoff validation now starts with APK `aapt` inspection and
fails preflight if the package, launchable Activity, trigger catalog Activity,
or embedded trigger catalog disagree. The Unity demo must enable the custom
main Android manifest before building.

Problem: when the Quest headset is asleep/unworn, Horizon can intercept an
ADB-launched immersive app with
`LaunchCheckControllerRequiredDialogActivity` before Unity starts. No Unity,
questionnaire, or tracer logs will appear because the product path never begins.

Solution: check `dumpsys power` and `dumpsys window` before the product-path
launch. If the headset is not ready, classify the trial as `blocked`, record
`initialUnityLaunchAttempted=false`, and do not force-stop or launch the apps
for that trial. Resume the test only with an awake/worn headset or an operator
who can clear the system launch gate.

Generalizable rule: for XR-to-panel handoff trials, prove the APK contract and
headset readiness before interpreting missing panel exports as a handoff bug.

## Evidence Matrices Beat Narrative Confidence

Problem: GUI, companion, APK generation, local renderers, Unity bridge checks,
APK preflight, and Quest handoff trials can each pass in isolation, but a
summary like "the pipeline works" hides which gates were actually exercised.

Solution: keep a single workflow validator that writes a requirement matrix.
`validate-builder-to-quest-workflow.ps1` records each gate as `pass`, `warn`,
`pending`, `blocked`, `skipped`, or `fail`, and the companion exposes the same
path through `/api/validate-workflow` for the GUI's `Validate workflow` button.
The matrix should also promote compact facts such as APK bytes/hashes, render
counts, device model, preflight trigger count, and direct-trial pass/block
counts so a reviewer can audit the workflow without opening every nested JSON
file first.

Generalizable rule: for multi-tool experiment builders, make the validation
artifact line up with the user's promised workflow instead of relying on a
collection of unrelated green checks.

## Browser Controls Need Job Handles For Long Work

Problem: `/api/validate-workflow` originally ran the full builder-to-Quest
matrix inside one HTTP request. That made the GUI look stuck during local
renders, APK preparation, and Quest-readiness checks, and risked browser or
proxy timeouts while hiding partial progress.

Solution: the companion now starts workflow validation as a background
PowerShell process, returns a `runId`/`jobId`, captures stdout/stderr under
`artifacts\builder-app-jobs\`, and exposes `/api/workflow-job` for status
polling. The GUI's `Validate workflow` button starts the job and polls until
the workflow matrix reaches a terminal status.

Generalizable rule: static dashboards should launch long trusted PC actions as
observable jobs, not synchronous button calls; the useful contract is job id,
status, artifact paths, and compact log tails.

## Device Readiness Should Be A First-Class GUI Step

Problem: the builder could run the full workflow matrix with Quest readiness
enabled, but the runner panel did not give users a small, read-only way to see
which headset ADB actually detected before opting into install, launch, or
direct handoff trials.

Solution: expose the existing `quest-adb-readiness.ps1` probe through the
local companion as `/api/quest-readiness`. The GUI's `Detect Quest` button
reports readiness/recommendations and fills the serial field from the detected
target without installing, launching, force-stopping, or changing headset
settings.

Generalizable rule: make the next irreversible or physical validation gate
visible by placing a read-only readiness probe immediately before it in the
dashboard workflow.

## Device-Changing GUI Actions Need Dry-Run Coverage

Problem: the builder could generate a 2D panel APK, but there was no explicit
GUI action for the next user-facing pipeline step: loading that APK onto the
Quest. Hiding install inside larger validators made the happy path less
legible and harder to test without changing headset state.

Solution: add a narrow `install-questionnaire-apk-on-quest.ps1` helper and a
token-protected `/api/install-apk` companion job. The GUI starts the install
job only when the user clicks `Install APK on Quest`, while the companion
workflow validator exercises the same endpoint with `dryRun=true` and a
placeholder `.apk` so auth, job polling, and artifacts are tested without
performing an install.

Generalizable rule: for dashboard buttons that change device state, separate
the command contract from the live side effect. Validate the command contract
with a dry run, and reserve the real side effect for explicit operator action.

## Replay Gates Need The Same Job Boundary As Installs

Problem: command replay/export validation proves much more than installation,
but it also launches the 2D panel app, writes marker files, pulls exports, and
captures evidence. Running that synchronously from the browser or hiding it in
the full workflow matrix makes the user-facing pipeline harder to understand
and harder to test safely.

Solution: wrap `quest-validate.ps1` behind a narrow
`run-questionnaire-replay-on-quest.ps1` helper and expose it through a
token-protected `/api/quest-replay` job. The builder gets a visible
`Run replay/export` step after install, while the companion stress test uses
`dryRun=true` to cover auth, job polling, readiness, and artifacts without
launching the app.

Generalizable rule: every live device validation rung that can be clicked in a
dashboard should have a reusable CLI helper, a job endpoint, and a dry-run
contract test.

## ADB Online Is Not Product-Path Ready

Problem: `adb devices` can report a Quest as online while the headset is asleep
or Horizon is focused on `LaunchCheckControllerRequiredDialogActivity`. In
that state install/file checks may still be possible, but replay/export,
foreground render, and direct PendingIntent handoff trials cannot prove the
product path.

Solution: split readiness into two facts. `quest-adb-readiness.ps1` keeps
`readiness=online` for transport, but also writes `productPathStatus`,
`productPathReady`, power/window artifact paths, focus lines, and blocked
reasons. The builder warns when product-path launch is blocked, and live
replay/export stops as `blocked` before launching the panel.

Generalizable rule: device transport readiness and product-path readiness are
different gates. Dashboards should surface both before letting a user interpret
launch or handoff evidence.

## Decisive Handoff Gates Need Their Own Runner

Problem: the direct `PendingIntent` handoff trial is the architecture decision
gate for whether the product can use XR app -> 2D panel -> same XR app without
ChainLink in the foreground. Keeping that trial only inside the broad
builder-to-Quest matrix made the GUI sequence less obvious and made it harder
to test the endpoint contract safely.

Solution: expose `quest-direct-handoff-validate.ps1` through the companion as
`/api/direct-handoff` plus `/api/direct-handoff-job`, and add a dedicated
`Run direct handoff` button after replay/export in the builder runner stage.
The companion workflow validator now dry-runs that endpoint with real
questionnaire, temporal tracer, and Unity APKs so auth, package preflight, job
polling, and summary artifacts are covered without launching the headset.

Generalizable rule: if a validation step decides the long-term architecture,
give it a first-class GUI button, job endpoint, and dry-run contract test
instead of hiding it inside an aggregate validator.

## Panel Return Contracts Need A Static Gate

Problem: the direct handoff bridge can look ready while the reusable 2D panels
silently drift. If the questionnaire or temporal tracer stops exporting before
return, drops `mq.returnPendingIntent`, or removes caller-package fallback,
Quest trials will fail late and the bug can be mistaken for Unity or Horizon
activity behavior.

Solution: `validate-builder-to-quest-workflow.ps1` now writes
`panel-return-contracts-static-summary.json` and adds the
`panel-return-pendingintent-contract` requirement. The gate checks both panel
manifests, verifies `mq.returnPendingIntent` extraction and result extras, and
confirms that completion paths save/export before attempting the return token
and legacy caller fallback.

Generalizable rule: contract-first handoff validation must cover every owner
in the handoff, not just the foreground XR bridge. Static gates should prove
the panel export-and-return contract before physical Quest trials are treated
as architecture evidence.

## Trigger Mapping Deserves Its Own Evidence Row

Problem: a config validator can say the generated questionnaire JSON is valid
while hiding the central product promise: loading an APK/catalog creates one
clear block per trigger, routes questionnaire and temporal-tracer blocks to the
right packages/actions, and carries caller-return extras for each block.

Solution: `validate-builder-to-quest-workflow.ps1` now writes
`trigger-block-mapping-static-summary.json` and adds the
`trigger-block-mapping-contract` requirement. The gate checks mapping schema,
unique trigger ids, three-digit block numbers, stable block ids, registry block
coverage, package/action targets, `mq.handoff.v1` extras, and the repository
demo catalog's demographics then temporal-tracer assignments.

Generalizable rule: APK-first builder workflows need an auditable
catalog-to-block compiler gate. Do not let trigger discovery and block
assignment disappear inside a broader "config valid" status.

## Inspect The Packaged Trigger Manifest

Problem: source-side trigger catalogs can be correct while the built Unity APK
contains an old, missing, duplicated, or unparsable trigger manifest. In that
state the builder and config checks can pass, but the actual APK a participant
launches is not discoverable in the way the product contract requires.

Solution: direct handoff preflight now opens the Unity APK as a zip, parses the
embedded `questionnaire-trigger-catalog.json`, and compares its schema,
scenario, package/activity, trigger ids, and recommended modes against the
source catalog. The aggregate builder-to-Quest matrix surfaces this embedded
catalog evidence through the direct handoff preflight facts.

Generalizable rule: when an APK is supposed to advertise a machine-readable
contract, validate the packaged contract, not only the project file that should
have produced it.

## Physical Gates Need Operator-Controlled Wait Windows

Problem: direct handoff and replay/export trials can be validly blocked by
ordinary headset state: the Quest is online over ADB but asleep, display-off,
or stuck on Horizon's controller-required launch check. A hard-coded short wait
turns unattended or overnight trials into predictable blocked artifacts even
when the rest of the software is ready.

Solution: keep the product-path readiness gate strict, but expose the wait
window as a runner control. The builder now lets the operator set a bounded
`Ready wait (s)` value for direct handoff and full workflow validation; the
companion clamps that value to 0-28800 seconds and still refuses to launch when
readiness never clears. When readiness is blocked before the product path, the
direct validator records one blocked trial and stops instead of multiplying the
same physical blocker across all requested trials.

Generalizable rule: physical-device validation should be patient but not
reckless. Make wait windows explicit, bounded, and visible in the evidence
instead of baking in a magic sleep; never repeat identical physical blockers
just to fill a trial count.

## Stress Ladders Should Test Their Own Safety Bounds

Problem: adding an operator-controlled readiness wait made unattended Quest
proof attempts more practical, but an untested clamp is only a UI promise. A
hosted page, stale frontend, or scripted caller could still send oversized
trial or wait values if the companion contract did not prove the backend
normalizes them.

Solution: the companion workflow validator now sends an intentionally
out-of-range direct handoff dry-run request (`trialCount=999`,
`waitForReadySeconds=999999`) and asserts the job status reports the backend
clamps (`trialCount=10`, `waitForReadySeconds=28800`) while still producing a
valid preflight summary. It also sends an out-of-range `/api/validate-workflow`
request with `dryRunQuestDirectHandoff=true` so the aggregate workflow endpoint
proves the same bounds without launching Unity or claiming physical Quest
handoff success.

Generalizable rule: when a safety bound matters for physical-device
automation, cover it in the same stress ladder as the happy path. Do not rely
on frontend constraints alone.

## Dry-Run Pass Is Not Strategy Approval

Problem: direct handoff dry-runs are useful for proving package preflight, job
polling, and summary plumbing, but `status=pass` can be misread as approval to
make direct `PendingIntent` the production default. That would bypass the
project's actual decision gate: 10 clean product-path Quest trials plus a
manual headset pass.

Solution: direct handoff summaries now include
`mq.direct_handoff_strategy_decision.v1`. Dry-runs report
`candidateAStatus=dry-run-only`,
`recommendedProductionStrategy=collect-real-quest-product-path-trials`, and
`defaultDirectPendingIntentApproved=false`. Even after automated real trials
pass, approval remains false while the manual headset pass is pending.

Generalizable rule: separate automation-health evidence from architecture
decision evidence. A dry-run can approve the runner contract, but only physical
product-path evidence should approve the handoff strategy.

## One Receipt Beats Scattered Green Checks

Problem: the GUI-to-companion-to-APK stress ladder can generate many useful
artifacts: builder smoke JSON, companion auth checks, generated config paths,
APK hashes, local render summaries, workflow matrices, and direct handoff
dry-run summaries. When those facts are scattered, a reviewer can miss that a
run skipped APK generation or render previews while still seeing many green
subchecks.

Solution: the companion workflow summary now includes
`endToEndReceipt`. A full run reports `pass-with-physical-pending` only when
the GUI smoke path, token-protected companion endpoints, config save/validate,
generated APK hash, render-preview artifact gate, workflow matrix, and
non-physical direct handoff gates all pass. Fast runs that intentionally skip
APK build or render preview are classified as `partial-skipped-evidence`
instead of failure or full proof.

Generalizable rule: multi-stage builder pipelines need a single top-level
receipt that distinguishes full evidence, skipped evidence, and physical
evidence still pending. Keep detailed artifacts, but promote the audit-critical
facts into one reviewer-facing object.

## User-Facing Workflow Buttons Need Receipts Too

Problem: even when `/api/validate-workflow` wrote a strong matrix, the GUI
status line only showed a raw workflow status and summary path. That left the
main user-facing button weaker than the machine artifact because a reviewer
could miss APK bytes, render counts, failed/blocked/pending gate counts, and
the direct handoff decision boundary unless they opened JSON.

Solution: `/api/workflow-job` now derives a compact `workflowReceipt` from the
builder-to-Quest matrix, and the install/replay/direct-handoff job endpoints
derive matching `jobReceipt` objects from their summaries. The GUI renders
these receipts as a visible evidence line. The raw summary remains available
in the log, but the runner panel promotes the audit-critical facts: offline
gates inspectable, failure/block/pending counts, APK size, local render count,
install dry-run state, replay product-path readiness, direct handoff status,
and the reminder that production direct PendingIntent remains pending until
real Quest trials plus manual headset evidence pass.

Generalizable rule: if a dashboard button launches a long evidence-producing
job, its polling endpoint should return both raw artifact paths and a compact
human-readable receipt. Do not make users open nested JSON to learn whether the
button proved the promised workflow.

## Hosted GUIs Need Companion Capability Checks

Problem: the hosted builder can update before a user's locally installed
companion launcher. If the page silently assumes newer response fields such as
`workflowReceipt` or `jobReceipt`, an older companion can make the runner panel
look weaker or broken even though the connection itself succeeds.

Solution: `/api/status` now advertises `apiVersion`, `receiptSchemaVersion`,
and receipt-specific capabilities: `workflow-receipt` and
`runner-job-receipts`. The GUI warns when those capabilities are missing, and
the companion workflow validator fails fast if the current companion no longer
advertises them.

Generalizable rule: any hosted static dashboard that depends on a local
companion should treat API capabilities as part of the health check, especially
for user-visible evidence fields.

## Local Artifact Preview Is Not Local File Browsing

Problem: `generationReceipt` can name useful local render PNGs, but a hosted
static page cannot display arbitrary Windows paths directly. Serving those
paths naively through localhost would risk turning the companion into a
general local file server, and putting the pairing token in image URLs would
leave credential-shaped crumbs in browser history and logs.

Solution: the companion exposes a narrow `GET /api/artifact-preview?path=...`
route and advertises the `artifact-preview` capability. The route requires the
pairing token header, honors the same CORS boundary as other privileged local
actions, serves only PNG files, and accepts only paths under generated artifact
roots. The GUI fetches the PNG bytes with `X-MQ-Builder-Token` and renders
object URLs, while the companion validator downloads a sample PNG from
`generationReceipt` and checks that it is a valid non-empty PNG.

Generalizable rule: receipt paths are evidence references, not browser
permissions. When a local companion serves artifact bytes to a hosted GUI,
keep the endpoint typed, authenticated, path-scoped, and covered by the same
stress ladder as the receipt that produced the paths.

## Workflow Receipts Should Carry Their Preview Samples

Problem: the aggregate workflow matrix validated questionnaire and temporal
tracer render PNGs, but the compact `workflowReceipt` only exposed render
counts and summary paths. The GUI could tell the user that local renders
existed, yet still could not show representative PNGs from the full workflow
validation button.

Solution: `workflowReceipt.artifacts.questionnaireRender` and
`workflowReceipt.artifacts.temporalTracerRender` now promote `samplePngs` and
`pngFileCount`, and `/api/status` advertises `workflow-render-previews`. The
builder uses those paths with the existing token-protected
`/api/artifact-preview` endpoint, and the companion stress ladder fetches one
questionnaire and one tracer sample PNG from the workflow receipt as valid
non-empty images.

Generalizable rule: when a compact receipt claims a visual gate passed, include
enough sample artifact references for the dashboard to inspect the same
evidence. Counts alone are not enough for user-facing visual validation.

## Architecture Gates Need Visible Preflight Modes

Problem: the direct handoff endpoint could already dry-run package/activity
and trigger-catalog checks, but the dedicated GUI button looked like a live
headset action. That made the safest repeatable evidence path less visible and
encouraged users to wait for physical Quest readiness before checking the APK
contract.

Solution: keep the live direct handoff runner, but add a `Preflight only`
toggle that defaults on for the dedicated button. In that mode the GUI calls
`/api/direct-handoff` with `dryRun=true`, `skipInstall=true`,
`trialCount=1`, and `waitForReadySeconds=0`; the companion advertises
`direct-handoff-preflight` so hosted pages can warn about stale local
launchers.

Generalizable rule: architecture-decision buttons should separate safe
contract preflight from live product-path evidence. Make the dry-run mode
visible, keep it covered by the companion stress ladder, and require explicit
operator intent before launching physical-device trials.

## Aggregate Workflow Buttons Need Dry-Run Parity

Problem: the dedicated direct handoff button could run safe package/catalog
preflight, while the aggregate `Validate workflow` button still skipped direct
handoff unless live headset trials were requested. That created an awkward
split: the one-button evidence matrix omitted the same non-physical contract
gate that reviewers could run separately.

Solution: reuse the same `Preflight only` toggle for the aggregate workflow
payload. With the toggle checked, the GUI sends
`runQuestDirectHandoff=true`, `dryRunQuestDirectHandoff=true`,
`skipInstall=true`, `questTrials=1`, and `waitForReadySeconds=0` to
`/api/validate-workflow`; clearing it and checking live trials restores the
operator-supervised product-path path.

Generalizable rule: if a dashboard has both a dedicated evidence button and an
aggregate validation button, keep their dry-run safety semantics aligned. The
aggregate matrix should not silently omit a safe preflight gate just because
the live physical gate is not being run.

## Dry-Run Gates Should Not Inherit Live Device Preconditions

Problem: once the GUI started the aggregate workflow with
`dryRunQuestDirectHandoff=true`, the matrix still blocked the direct handoff
row when no Quest serial was provided. That made an offline package/catalog
preflight depend on a live-device field it never uses.

Solution: let `validate-builder-to-quest-workflow.ps1` run
`quest-direct-handoff-validate.ps1 -DryRun` without `-Serial`. Keep the serial
requirement for real product-path trials, but do not apply it to dry-run
preflight, which returns before ADB discovery.

Generalizable rule: dry-run validation should prove the contract it actually
exercises. Do not copy live-device prerequisites into non-physical preflight
unless the dry-run itself reads that device.

## Local Companions Need Workspace-Aware Defaults

Problem: launching the companion directly from the repo defaulted
`ReferenceProjectPath` to the 2D app project when `MyQuestionnaireVR` was not
inside the repo root. The browser-started workflow then saved a config whose
legacy MAIA, pictographic, and slider source paths could not be resolved.

Solution: resolve the reference project from both likely layouts:
`<repo>\MyQuestionnaireVR` and the workspace sibling
`<workspace>\MyQuestionnaireVR`, falling back to the 2D app only when neither
exists. The explicit `-ReferenceProjectPath` path still wins for validators and
custom checkouts.

Generalizable rule: desktop companions launched by humans need the same
path-resolution behavior as validators. If a workflow depends on a sibling
reference project, discover the common workspace layout instead of relying on a
validator-only parameter.

## Validators Should Restore Source Assets

Problem: the builder-to-Quest validator proves APK generation by applying a
GUI-generated config into `app/src/main/assets/questionnaire/`, but that same
temporary asset refresh can leave tracked source files dirty after a successful
stress run. The evidence is valid, yet the worktree looks like there are source
changes to review or commit.

Solution: `validate-builder-to-quest-workflow.ps1` now snapshots the packaged
questionnaire asset folder before the APK generator runs, restores that folder
immediately after the generator/render step finishes, and writes the snapshot
and restore receipts into the workflow artifact folder. The matrix includes
`workflow-preserves-source-assets` so source-tree hygiene is audited beside the
product evidence. The companion stress validator uses the same snapshot/restore
pattern around its standalone `/api/generate-apk` endpoint check.

Generalizable rule: validation scripts may build temporary runtime assets, but
they should leave source assets exactly as they found them unless the user is
explicitly running a generation command whose purpose is to rewrite those
assets.

## Evidence Bundles Need Typed Local Packaging

Problem: GUI-triggered workflows now produce compact receipts and preview
PNGs, but the evidence still lives in nested local artifact folders. A reviewer
can see the status line in the dashboard, yet still has to chase summary paths,
render summaries, job logs, and PNG references by hand to carry evidence to
another machine or another reviewer.

Solution: the local companion exposes a token-protected
`/api/evidence-bundle` route. It accepts a JSON summary path only when that
path is under known artifact roots, recursively collects referenced
JSON/TXT/LOG/CSV/PNG files under those same roots, writes a manifest, and
returns a zip. The GUI enables `Download evidence bundle` only after a
generation, runner, or workflow receipt names an inspectable summary path, and
the companion stress validator downloads and opens the zip before marking
offline evidence fully inspectable.

Generalizable rule: hosted dashboards should package local evidence through a
typed, authenticated companion endpoint. Do not expose arbitrary local paths;
bundle only known artifact-file types under known artifact roots, and include a
manifest so the zip itself is auditable.
