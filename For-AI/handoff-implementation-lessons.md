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

## Completion Audits Should Be Requirement-First

Problem: once the workflow has many receipts, a future agent can confuse
strong offline evidence with actual goal completion, or miss that only the
physical Quest gates remain. Narrative summaries are especially risky because
the requested end state includes both website/companion/APK generation and
real Quest behavior.

Solution: add `audit-universal-handoff-readiness.ps1`. It reads the latest
full companion receipt and real direct-handoff summaries, then emits a
requirement-by-requirement matrix for the original product promise: hosted GUI,
local companion contract, demo Unity APK/trigger catalog, APK generation,
local renders, evidence bundle, direct PendingIntent preflight, at least one
real product-path trial, 10 clean Quest product-path trials, and manual
headset pass. It exits cleanly for
`pass-with-physical-pending` when the only missing items are physical gates,
and `-RequireComplete` turns that same state into a failure.

Generalizable rule: long-running goal threads need a machine-readable
completion audit that preserves the original scope. Make the audit prove
completion or name exactly which requirement remains, instead of letting green
subchecks redefine success.

## Manual Gates Need Structured Signoff Artifacts

Problem: the direct handoff validator can prove app-owned focus, logs, exports,
and media liveness, but a human headset observation can still disappear into a
chat note. That makes the final production gate fragile: future agents may
remember that somebody was physically at the headset while the audit still has
no durable artifact to consume.

Solution: add a direct-handoff manual signoff helper that creates operator
instructions, a JSON template, and a validation summary. A pass must reference
a real non-dry-run direct handoff summary, confirm the full Unity ->
questionnaire -> Unity video resumed -> tracer -> Unity completion sequence,
and record that no Meta menu navigation or ADB foreground switching occurred
after the initial Unity launch. The readiness audit consumes the signoff
summary, while keeping the direct validator's automated decision-gate status
visible as secondary evidence.

Generalizable rule: manual physical gates need their own typed artifacts.
Human observation can close a gate only when it is tied to the machine evidence
that was observed and can be rechecked by the next agent.

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

## Wake Assistance Must Be Explicit Evidence

Problem: long or unattended Quest handoff runs can stall before the product
path when the headset display falls asleep. Sending a blind wake key inside
every validator would make overnight attempts more likely to start, but it
would also blur the evidence boundary: reviewers could no longer tell whether
the trial began naturally from an already-ready headset or because the host
assisted device state immediately before readiness sampling.

Solution: make wake assistance an explicit, opt-in control. The builder exposes
`Wake before readiness` only for live direct-handoff attempts, the companion
passes `-WakeBeforeReadiness`, and the direct validator records
`wakeBeforeReadiness` plus `wakeBeforeReadinessCount` in the run evidence. The
readiness gate, product-path blocked classification, 10 clean trials, and
manual headset pass remain unchanged.

Generalizable rule: device-state assistance can be useful developer tooling,
but it must be named, bounded, and recorded as part of the evidence. Never hide
power/proximity/wake actions inside a validator that is supposed to prove user
product behavior.

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

## Hosted Publication Needs A Live Parity Gate

Problem: source/staged GUI parity can pass locally while the public GitHub
Pages site is still stale, unreachable, or missing the newest workflow buttons.
For this project, that would weaken the website-based GUI claim even if the
local companion and APK generator are healthy.

Solution: add `validate-hosted-questionnaire-builder.ps1`. The validator
normalizes and hashes the editable builder HTML, the staged
`questionnaire-builder/index.html`, and the live hosted URL, then checks for
the expected runner controls and companion endpoints such as `Run headset
sequence`, `Preflight only`, `Wake before readiness`, `Download evidence
bundle`, `/api/generate-apk`, `/api/direct-handoff`, and
`X-MQ-Builder-Token`. The companion workflow stress ladder includes that
publication gate in its end-to-end receipt unless explicitly skipped.

Generalizable rule: hosted dashboards need a publication gate that checks the
actual URL users open, not only the local source tree. Treat hosted parity as a
separate proof from local browser smoke tests and companion API stress tests.

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

## Snapshot Helpers Need Long-Path-Safe Copy

Problem: source-asset snapshots can fail on Windows even when the source files
are valid and the destination parent directory exists. A descriptive workflow
run id plus nested questionnaire assets such as `PictographicScales/*.png` can
hit the classic 260-character path boundary, causing `Copy-Item` to throw
`DirectoryNotFoundException` and abort the companion stress ladder before the
local companion, APK generation, and render gates run.

Solution: use long-path-aware file helpers inside snapshot/restore code:
normalize paths, add the `\\?\` prefix on Windows, create directories through
`System.IO.Directory`, and copy/delete files through `System.IO.File`. Then
stress the helper with the same long artifact path shape that exposed the
failure, and rerun the full companion workflow to prove source assets are still
restored.

Generalizable rule: artifact validators should tolerate realistic long run
ids. Source-tree hygiene gates are supposed to make stress runs safer, not
make evidence collection depend on short folder names.

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

## One-Button Runs Should Reuse Proven Jobs

Problem: a dashboard can expose every required step as a separate button while
still making the full product path feel unfinished. Reviewers and operators
then have to remember the correct order: save, validate, generate APK, render,
detect Quest, install, replay/export, direct handoff, audit, and packet prep.

Solution: add a `Run headset sequence` button that calls the same companion
endpoints as the individual controls in the same order. It always requests the
local render preview during APK generation, keeps the existing `Preflight only`
toggle for direct handoff safety, reports readiness/product-path warnings, then
runs the readiness audit and prepares the physical gate packet from that audit
without inventing a separate backend contract.

Generalizable rule: make the happy path explicit in the GUI, but do not fork
validation semantics. A sequence button should compose already-tested jobs so
the one-click path and the step-by-step path produce comparable receipts.

## Sequence Buttons Need Composition Smoke Tests

Problem: a hosted/static validator can prove that a one-button runner label and
endpoint names exist while missing whether the actual sequence still calls the
trusted companion endpoints in the required order. That is especially risky
when the final steps are non-device-changing evidence boundaries such as
readiness audit and physical packet preparation.

Solution: the questionnaire builder smoke test now inspects
`runHeadsetSequenceWithApp()` and asserts the ordered endpoint spine: save,
validate, generate with `runTests` and local render preview, Quest readiness,
install, replay/export, 2D-first launcher gate, direct handoff gate, readiness
audit, and physical packet preparation. It also unit-checks
`physicalGatePacketPayloadFromEvidence()` so the packet prefers the visible
audit summary before falling back to companion summary discovery.

Generalizable rule: GUI sequence buttons should have a smoke gate that proves
composition, not only existence. When a one-button path is supposed to reuse
individual controls, assert the endpoint order and evidence handoff payloads
directly.

## Front-Door Gates Belong In The GUI

Problem: `quest-2d-first-launcher-validate.ps1` made the participant-facing
questionnaire-first path testable, but leaving it as a CLI-only gate meant the
hosted/offline builder could still lead operators through install,
replay/export, and direct handoff without ever proving that a normal Meta Home
launch starts demographics before Unity owns focus.

Solution: expose the 2D-first launcher validator through the companion as
`/api/2d-first-launcher` and `/api/2d-first-launcher-job`, add a `Run 2D-first
launch` GUI control, and insert that gate into `Run headset sequence` before
direct handoff. In preflight mode it inspects the packaged questionnaire APK
for `questionnaireFirst`, `demographics`, and `openNext` into the Unity APK;
in live mode it remains the separate one-trial participant-front-door Quest
gate.

Generalizable rule: if a workflow variant changes what the participant launches
first, put that gate in the operator GUI and in the companion receipt contract.
CLI validators are useful, but the default study path should surface the same
proof boundary where the operator actually runs the workflow.

## Completion Audits Should Be Operator-Visible

Problem: the Universal Handoff audit could already summarize proven offline
requirements and pending physical gates, but it lived behind a PowerShell
command. That made the GUI good at starting jobs while leaving the actual
"are we done yet?" answer in a separate CLI artifact.

Solution: expose `audit-universal-handoff-readiness.ps1` through the local
companion as `/api/handoff-readiness-audit`, add an `Audit readiness` button,
and return an `auditReceipt` that the GUI renders like the other evidence
receipts. The companion stress validator calls the endpoint against its own
summary so the audit route proves current-run evidence, not just stale files.

Generalizable rule: dashboards that orchestrate validation should also expose
the completion audit. Operators should see proven requirements, missing
offline evidence, and pending physical gates in the same place where they
generate APKs and run headset jobs.

## Manual Signoff Prep Belongs In The GUI

Problem: after structured manual signoff artifacts existed, operators still
had to remember a CLI-only helper to prepare the template and validate the
filled JSON. That left the final physical gate outside the website workflow
even though the GUI already exposed generation, install, replay, direct
handoff, 2D-first launch, and readiness audit receipts.

Solution: expose `new-direct-handoff-manual-signoff.ps1` through the local
companion as `/api/direct-handoff-manual-signoff`, add a `Prepare manual
signoff` GUI control, and return a `manualSignoffReceipt`. Without an operator
JSON path the endpoint writes instructions/template plus a pending summary;
with an operator JSON path it validates the filled signoff against the real
direct-handoff summary. The companion stress validator covers both auth and
template generation without claiming a physical pass.

Generalizable rule: if a dashboard owns the evidence workflow, it should also
prepare and validate human signoff artifacts. Keep the actual physical gate
human-owned, but make the artifact creation, receipt, and audit path
operator-visible.

## Physical Gate Packets Prevent Last-Mile Drift

Problem: once the offline workflow is green, the remaining work can still be
spread across an audit summary, a 2D-first launcher command, a direct handoff
trial command, a manual signoff template, and chat context. That is fragile
when the next operator is physically at the headset and needs to run the live
gates without re-deriving the sequence.

Solution: add a Universal Handoff physical gate packet helper and expose it as
`/api/physical-gate-packet` plus `Prepare physical packet` in the builder GUI.
It runs or consumes the readiness audit, prepares the manual signoff template,
and writes a packet summary plus `physical-gate-runbook.txt` under
`artifacts\universal-handoff-physical-gate-packet\`. The receipt proves the
runbook, audit, and signoff template exist while still reporting the live Quest
gates as pending.

Generalizable rule: after a requirement-first audit reaches
`pass-with-physical-pending`, generate a typed operator packet for the physical
session. Package the latest evidence paths and exact gate commands, but do not
let the packet itself close any device, product-path, or human-observation
gate.

## Operator Packets Need Stop Conditions

Problem: a physical-session runbook can list the right commands while still
letting the operator normalize bad headset states, such as clearing a
controller-required launch dialog or using Meta menus to recover from frozen
Unity video. That turns a product-path failure into ambiguous manual behavior.

Solution: the Universal Handoff physical gate packet now includes operator
guardrails: use `2D demographics -> Unity Start experiment -> video/stimulus`,
stop if a generic demo/stimulus APK shows a controller-required launch dialog,
do not use Meta menu or ADB foreground recovery after the initial launch, and
treat frozen Unity video after panel return as a Unity panel-focus/media-resume
bug. The manual signoff template now requires the operator to confirm that no
controller-required launch dialog blocked the Unity APK.

Generalizable rule: physical gate packets should include stop conditions and
failure meanings, not only success commands. If an operator action would mask
the app-owned product path, make it a false signoff rather than a workaround.

## Operator Packets Should Follow Visible Evidence

Problem: a dashboard can show the operator a specific readiness audit and then
prepare a packet by asking the backend to rediscover "latest" evidence. If a
newer diagnostic run exists on disk, the generated packet can silently point at
evidence different from what the operator just reviewed.

Solution: the builder now sends the visible `auditSummaryPath` to
`/api/physical-gate-packet` when the last rendered receipt is an audit or an
existing physical packet. The packet still falls back to latest local evidence
when no explicit visible path exists, but the preferred path is tied to the
dashboard state.

Generalizable rule: when a GUI prepares a handoff or signoff packet from
previous evidence, prefer explicit summary paths from the currently visible
receipt over backend "latest file" discovery. Use fallback discovery only when
the browser genuinely has no current evidence path.

## Operator Artifacts Need Long-Path-Safe Writers

Problem: physical gate packets nest audit outputs, manual signoff summaries,
runbooks, and descriptive run ids under artifact folders. On Windows, a valid
path can hit the 260-character boundary and make `Set-Content` or `Test-Path`
report that an existing directory or file is missing. In this workflow the
manual signoff summary existed in intent but disappeared from the packet
receipt because the path landed exactly on that boundary.

Solution: write and read operator artifacts through long-path-safe .NET file
helpers using the `\\?\` prefix on Windows. Apply that to packet summaries,
runbooks, child stdout files, manual signoff templates, and summary JSON, and
stress it with a deliberately descriptive run id before trusting the endpoint.

Generalizable rule: any validator or GUI endpoint that creates nested evidence
under human-readable run ids should use long-path-safe file IO for both writes
and receipt checks. Otherwise a valid evidence packet can be misclassified as
missing on the machine where the operator needs it most.

## Unity Must Own Panel-Focus Media Pause

Problem: launching a 2D questionnaire or tracer over a Unity Quest app does not
by itself guarantee clean media pause/resume. Quest foreground switching can
pause, focus, or resume the Unity Activity in different orders, and Unity may
keep the first returned Activity intent after it has already moved on to a
second trigger. In live validation this looked like a frozen video after the
first questionnaire return, and later like the trigger-2 tracer return being
missed or confused with the stale trigger-1 result.

Solution: source apps should explicitly enter a panel-focus mode before
launching a questionnaire/tracer: pause `VideoPlayer`, remember whether playback
should resume, actively poll for completion while waiting for a panel result,
consume/clear handled result extras, and accept only the `mq.triggerId` that
matches the current waiting phase. Unity bridge callbacks should create a
distinct return `PendingIntent` per trigger or chain step. The reusable Unity
bridge template now exposes `ClearQuestionnaireResult()` and builds the
PendingIntent request key from caller package/activity plus trigger, chain
step, and block identity; the static workflow gate checks those exact
guardrails. The direct handoff validator also checks ordered media liveness:
after `PANEL_COMPLETION_RECEIVED`, it requires a playback marker and a
frame/non-black marker before treating the Unity video path as live.

Generalizable rule: Android/Quest can move focus between APKs, but experiment
continuity belongs to the source app. Treat panel launch as a source-app state
transition, not as an OS-level media pause guarantee, and validate the resumed
stimulus with ordered liveness evidence rather than unordered log counts.

## Start Gates Simplify The First Handoff

Problem: launching Unity and immediately opening trigger 1 puts scene start,
Horizon focus settling, questionnaire launch, and eventual video start into one
compressed window. That makes operator setup harder and can hide whether a
frozen video came from app focus, stale return extras, or media startup.

Solution: source Unity scenes can add a start-experiment gate before the first
questionnaire trigger. The scene should show a visible `Start experiment`
target, wait for real participant/operator input inside the foreground Unity
app, then launch trigger 1. The video still starts only after the expected
panel result returns. Automated direct-handoff validators may bypass this gate
only by passing an explicit validation extra such as
`mq.validationAutoStart=true` and recording `AWE_START_GATE_AUTO_START` in the
log evidence.

Generalizable rule: put human readiness gates in the foreground scenario app,
not in the 2D panel or the host script. Keep product runs input-gated and make
validation bypasses explicit and auditable.

## Demo APKs Should Be Hand-And-Controller Capable

Problem: Horizon can block an immersive Unity APK with a controller-required
launch dialog before the questionnaire chain ever reaches the app-owned
handoff path. That makes the workflow look flaky even when the package/activity
contract and PendingIntent return path are correct.

Solution: generic demo and stimulus APKs should opt into both Quest controller
profiles and hand interaction profiles. The Android manifest should advertise
`oculus.software.handtracking` with `android:required=false` and include the
Quest hand-tracking permission/metadata. Keep controller-only launch behavior
only for experiments where physical controller input is part of the protocol.
Validators should treat `LaunchCheckControllerRequiredDialogActivity` as a
build/input-modality preflight issue for generic demo APKs.

Generalizable rule: broad input modality is the default for workflow demos;
controller-only is an explicit study constraint, not a casual Unity default.

## 2D-First Launcher Is The Default Demographics Front Door

Problem: when Unity is the first app in the chain, Horizon controller-required
launch prompts and Unity focus recovery can block the participant before the
demographics questionnaire is even collected. Rebuilding Unity every time to
change the front door also makes the study flow brittle.

Solution: support a questionnaire-first start mode in packaged config. The 2D
questionnaire APK can default to demographics on a normal launcher start, save
block 1, and then open the Unity APK with `finishBehavior=openNext` plus the
same `mq.handoff.v1` completion extras that Unity expects after trigger 1.
This is a builder/config preset, not a source-level hard-code to one Unity
package. Unity still owns later XR triggers and still needs hand+controller
metadata so Horizon does not show controller-required launch dialogs for
generic demo/stimulus APKs.

Generalizable rule: for demographics-before-stimulus studies, choose the 2D
panel as the participant-facing front door by config. A generated study APK may
be pinned to one next Unity package/activity, but the reusable 2D app source
must stay configurable. Starting with the 2D panel simplifies demographics
collection, but it does not move raw XR input ownership out of Unity.

## Generated Configs Must Own Test Expectations

Problem: full APK generation applies the GUI-generated questionnaire config
before running Android unit tests. Tests that hard-code the default bundled
config id, MAIA/pictographic counts, or no-extra launch mode can pass in the
source tree but fail when the builder produces a smaller custom APK such as a
2D-first demographics launcher.

Solution: runtime tests should derive expected questionnaire ids and optional
sections from the active packaged config, or pass explicit launch extras when
the test is proving full replay behavior. The 2D-first demo workflow now runs
the same APK/render/preflight spine after applying
`QuestionnaireConfigs/examples/awe-great-dictator-2d-first-demo.config.json`,
so custom-config generation exercises the unit-test gate instead of skipping
it.

Generalizable rule: build validation must test the APK as packaged, not the
developer's favorite default assets. Make tests fixture-aware when config
builders can change the asset set.

## Variant Evidence Belongs In The Main Audit

Problem: once 2D-first launcher mode existed, the strongest evidence for that
path lived in a separate builder-to-Quest summary. Future agents could rerun the
universal readiness audit, see only generic generated-questionnaire coverage,
and miss that the questionnaire-first chain already had APK, render, and direct
handoff preflight proof.

Solution: `audit-universal-handoff-readiness.ps1` now finds the latest
`mq.builder_to_quest.workflow_validation.v1` summary whose packaged config has
`chainDefaults.startMode=questionnaireFirst`. It promotes that receipt as the
`2d-first-launcher-offline-spine` requirement when APK build, local render gate,
dry-run direct handoff preflight, and warning-only physical Quest pending state
all match.

Generalizable rule: when a workflow gains a supported variant, teach the main
readiness audit to surface the variant's evidence. Otherwise the variant
becomes real in code but invisible in operations.

## 2D-First Front Doors Need Their Own Physical Gate

Problem: the direct handoff validator proves the Unity-first path: Unity emits
trigger 1, the questionnaire returns, Unity resumes video, trigger 2 opens the
tracer, and Unity receives completion. After adopting the questionnaire APK as
the participant-facing front door, that evidence no longer proves the first
thing the participant actually does: launch the 2D APK, finish demographics,
and enter Unity through `openNext`.

Solution: add `quest-2d-first-launcher-validate.ps1`. Its dry-run preflight
inspects the generated questionnaire APK and Unity APK, including packaged
`chainDefaults.startMode=questionnaireFirst`, `questionnaireMode=demographics`,
`finishBehavior=openNext`, Unity package/activity, trigger catalog, and
hand-tracking metadata. Its live mode launches the questionnaire APK first,
uses command replay to complete demographics, verifies exports and
`MYQUESTIONNAIRE_CHAIN_RETURN finishBehavior=openNext`, and observes Unity
focus without shell foreground switching after the initial questionnaire
launch. The universal readiness audit now records this as a separate physical
pending gate.

Generalizable rule: when the front door changes, add a front-door-specific
product-path gate. Do not use a later return-path validator as proof that the
participant's first launch path works.

## Mid-Run Headset Sleep Is A Blocker, Not A Strategy Failure

Problem: a direct handoff trial can launch Unity, return from the first
questionnaire, and even show video playback markers, then lose the remaining
evidence because the headset falls asleep before trigger 2. Reporting that run
as `fail` makes the direct `PendingIntent` strategy look broken when the
evidence window itself was interrupted.

Solution: classify final sleep/display-off evidence as a blocked product-path
trial when the product path has started, required markers are still missing,
and no fatal app logs were observed. Preserve actual crashes as failures, but
route unworn/asleep headset interruptions to `blocked` with a specific
`headset-asleep-or-display-off-during-product-path` reason.

Generalizable rule: a validator should distinguish app-contract evidence from
operator/headset-state evidence. Do not let missing markers caused by an
invalid evidence window become a negative strategy decision.
