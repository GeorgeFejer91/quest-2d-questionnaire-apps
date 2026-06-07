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
