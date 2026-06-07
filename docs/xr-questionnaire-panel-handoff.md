# XR Questionnaire Panel Handoff

This contract defines the product-path handoff between a foreground XR/Unity
APK and reusable Meta Quest 2D panel apps. The goal is:

```text
XR focused -> 2D questionnaire/tracer focused -> same XR app focused again
```

The product path must not depend on ADB foreground switching, force-stop,
package killing, or Meta menu navigation. ADB remains valid for installation,
log capture, evidence pulls, and developer stress tests.

## Contract

The foreground XR app owns semantic triggers. When the app reaches an event,
it launches the appropriate 2D panel with an explicit component intent and the
`mq.handoff.v1` extras below.

Required extras:

```text
mq.handoffSchema=mq.handoff.v1
mq.sessionId=<stable session id>
mq.triggerId=<manifest trigger id>
mq.blockId=<generated block id>
mq.blockNumber=<three digit block number>
mq.scenarioId=<scenario/study id>
mq.finishBehavior=resumeCaller
```

Preferred return extra:

```text
mq.returnPendingIntent=<Parcelable PendingIntent>
```

Fallback return extras:

```text
mq.callerPackage=<XR package>
mq.callerActivity=<XR activity>
```

The `PendingIntent` must target the same XR activity with:

```text
FLAG_ACTIVITY_REORDER_TO_FRONT
FLAG_ACTIVITY_SINGLE_TOP
FLAG_ACTIVITY_NEW_TASK
```

The 2D panel must save exports before returning. On completion it sends the
return token first; if no token exists or sending fails, it uses the explicit
caller package/activity fallback.

Result extras returned to the XR app:

```text
mq.resultStatus=complete
mq.triggerId=<completed trigger id>
mq.runId=<panel run id>
mq.sessionId=<session id>
mq.timestampUtc=<completion timestamp>
mq.exportJsonPath=<device path>
mq.exportCsvPath=<device path>
mq.exportSvgPath=<device path, temporal tracer only>
mq.questionnaireConfigId=<questionnaire config id>
mq.tracerConfigId=<tracer config id>
```

## Manifest Shape

The XR app activity should be the real enabled Unity activity and should use
`launchMode="singleTop"`. It must handle `onNewIntent()` and make the latest
intent available to Unity code.

The 2D panel activities should be exported, resizeable, `singleTop`, and
launched by explicit action/component pairs:

```text
org.viscereality.questionnaires2d.RUN
org.viscereality.temporaltracer2d.RUN
```

## Focus Expectations

The XR app should pause video or experiment progression when it loses focus or
is paused. It may resume only after it receives `mq.resultStatus=complete` for
the expected trigger.

For stimulus scenes that should not begin until the participant/operator is
ready, put a source-app start gate before the first questionnaire trigger. The
Unity scene should show a simple `Start experiment` target, wait for real
controller/hand/mouse input, then launch trigger 1. This keeps initial video
decode and timing out of the uncertain app-launch/focus window. Automated
validation may bypass that human gate only through an explicit launch extra,
for example `mq.validationAutoStart=true`, and should record the bypass in
log/evidence markers.

Do not rely on Quest foreground switching alone to freeze and resume media.
Android/OpenXR focus and pause callbacks can arrive differently across headset
states, and Unity can keep a stale return intent on the Activity after the
first panel. A trigger-enabled Unity app should explicitly enter a panel-focus
mode before launching a 2D APK: pause the `VideoPlayer`, remember whether the
video should resume, poll for a completion result while waiting, consume the
handled result, and require the returned `mq.triggerId` to match the trigger it
is currently waiting for. The return `PendingIntent` should also be unique per
trigger or chain step so later panel returns cannot collapse into an earlier
callback. The reusable Unity bridge template under
`MyQuestionnaireVR-2D/tools/unity/QuestQuestionnaireChainBridge.cs` exposes
`ClearQuestionnaireResult()` and creates return tokens from caller package,
caller activity, trigger id, chain step id, and block id; the builder-to-Quest
workflow matrix statically checks those guardrails.

The 2D panel receives normal Quest panel input while focused. It does not own
the foreground XR app's OpenXR session or raw controller state.

## ChainLink Strategy

Candidate A is direct:

```text
XR app -> 2D panel -> same XR app via PendingIntent
```

Candidate B is fallback:

```text
XR app -> ChainLink mq.command=trigger -> 2D panel -> ChainLink -> XR app
```

Candidate C is legacy compatibility:

```text
XR app -> 2D panel -> callerPackage/callerActivity return
```

ChainLink is the plan compiler, trigger mapping validator, and fallback router.
It should not be required in the foreground for a production direct handoff
unless Candidate A fails on Quest.

## ADB Boundary

ADB can install APKs, launch the initial app for a test, capture foreground
state, collect logcat, and pull exports. After the initial test launch, a
product-path pass must not use shell commands to force the foreground app.

The proof must show both packages stay alive and the focus sequence returns to
the same XR package/activity through app-owned handoff.

Run a direct Quest evidence attempt with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MyQuestionnaireVR-2D\tools\quest-direct-handoff-validate.ps1 -Serial <quest-serial> -TrialCount 1 -WaitForReadySeconds 30 -FastVideoForValidation -AutoTraceForValidation
```

The script installs the questionnaire, temporal tracer, and Unity demo APKs,
waits for the headset to be ready, pushes only the validation replay marker
before the product-path launch, starts Unity once, then records focus samples,
logcat, power state, and exports. If the headset is asleep or Horizon is
already focused on `LaunchCheckControllerRequiredDialogActivity`, the script
records `blocked` with `initialUnityLaunchAttempted=false` and does not begin
the product path. Use `-AllowLaunchWhenNotReady` only when deliberately
diagnosing the Horizon launch gate.

The 2026-06-07 live Quest pass
`quest-direct-handoff\20260607T111059Z` proved one end-to-end direct
PendingIntent product-path trial: Unity launched once, trigger 1 returned from
the questionnaire, video playback resumed and produced non-black frame markers,
trigger 2 launched Temporal Tracer, Temporal Tracer exported 12 SVG/JSON traces
plus CSV/session files, and Unity received `AWE_DEMO_COMPLETE` after the tracer
return. The trial still leaves the production decision gate open because the
validator requires 10 clean real Quest trials and a manual headset pass before
defaulting Candidate A.

Use `/api/quest-readiness` or `quest-adb-readiness.ps1` before live trials to
separate transport from launch readiness. `readiness=online` means ADB can see
the Quest; `productPathStatus=ready` is the stronger evidence needed before
replay/export, foreground render, or direct handoff launch attempts.
If the product path has started but final power/window evidence shows the
headset or display fell asleep before required app markers arrived, the direct
handoff validator classifies the trial as `blocked` with
`headset-asleep-or-display-off-during-product-path` instead of counting it as a
Candidate A failure.
When the questionnaire return is observed but Unity playback does not show
ordered `VIDEO_PLAY`/`VIDEO_RESUME_AFTER_PANEL` and
`VIDEO_FIRST_FRAME`/`VIDEO_NONBLACK_FRAME` evidence after
`PANEL_COMPLETION_RECEIVED`, the trial records `mediaLiveness=false` and
`unity-video-*` failure reasons. That separates a software resume/liveness bug
from headset sleep and system launch-gate blockers.
Use `-WakeBeforeReadiness` only as an explicit developer aid for unattended
product-path attempts. It sends a bounded `KEYCODE_WAKEUP` before the
readiness poll, records `wakeBeforeReadiness` in the trial and summary
evidence, and still requires the normal readiness, focus, export, 10-trial,
and manual headset gates.

## Local Validation

The no-headset stress ladder is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MyQuestionnaireVR-2D\tools\validate-universal-handoff-workflow.ps1 -SkipApkBuild -SkipUnity
```

The 2026-06-07 local pass wrote
`MyQuestionnaireVR-2D\artifacts\universal-handoff\universal-handoff-20260607T010957Z\universal-handoff-workflow-summary.json`.
This proves the builder/compiler, generated handoff config, questionnaire
local render, temporal tracer assets, and temporal tracer local render. It does
not replace the required headset focus trials.

The local GUI-to-companion API stress ladder is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MyQuestionnaireVR-2D\tools\validate-builder-companion-workflow.ps1
```

The 2026-06-07 full companion pass wrote
`MyQuestionnaireVR-2D\artifacts\builder-companion-workflow\builder-companion-20260607T013607Z\builder-companion-workflow-summary.json`
and generated
`MyQuestionnaireVR-2D\Builds\viscereality-maia2-1.0.0.apk` through the local
`/api/generate-apk` endpoint. The companion validator also dry-runs the
standalone `/api/direct-handoff` job with real questionnaire, temporal tracer,
and Unity APKs so the direct PendingIntent package/activity/catalog preflight
is covered without launching the headset. Inspect the summary's
`endToEndReceipt`: full runs should report `pass-with-physical-pending`, while
fast runs with intentionally skipped APK or render evidence should report
`partial-skipped-evidence`.

To audit the whole Universal Quest Handoff evidence state without rerunning
builds or touching the headset, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MyQuestionnaireVR-2D\tools\audit-universal-handoff-readiness.ps1
```

The audit reads the companion receipt and direct handoff trial summaries,
emits one requirement-by-requirement JSON matrix, and exits successfully when
all offline requirements are proven while the only remaining items are the
physical 10 clean Quest product-path trials and manual headset pass. It also
promotes the demo Unity APK and public example trigger catalog as their own
evidence row, so the "starting with a demo Unity" part of the workflow is not
left implicit. Add `-RequireComplete` when those physical artifacts should
already exist.

The end-to-end builder-to-Quest evidence matrix is:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MyQuestionnaireVR-2D\tools\validate-builder-to-quest-workflow.ps1 -ConfigPath .\MyQuestionnaireVR-2D\QuestionnaireConfigs\generated\viscereality-maia2.config.json -RunQuestReadiness -Serial <quest-serial>
```

The hosted/offline GUI exposes the same gate through the companion
`/api/validate-workflow` endpoint. It also exposes the direct handoff gate as a
dedicated `Run direct handoff` action backed by `/api/direct-handoff` and
`/api/direct-handoff-job`, placed after replay/export in the sequential runner.
That button defaults to `Preflight only`, which uses the same direct handoff
job endpoint with `dryRun=true` and `skipInstall=true` to prove the real APK
package/activity/catalog contract without launching the headset. Clear that
toggle only for operator-supervised or explicitly scheduled product-path
trials.
When `Preflight only` remains checked, the aggregate `Validate workflow` button
also includes the direct handoff preflight row by sending
`dryRunQuestDirectHandoff=true` and `skipInstall=true` to the companion
workflow job. This mode does not require a Quest serial. It keeps the
one-button workflow matrix aligned with the dedicated direct handoff runner
while preserving the dry-run versus physical evidence boundary.
The `/api/generate-apk` endpoint returns a `generationReceipt` so the GUI's
APK-generation step can immediately show the generated APK byte/hash evidence
and local render-preview artifact gate.
The builder's `Run headset sequence` control strings the trusted local actions
together for the operator-facing path: save, validate, generate with tests and
local render preview, detect Quest, install the APK, run replay/export, and
then run direct handoff preflight or live trials according to the same
`Preflight only` toggle. It reuses the existing companion endpoints so the
one-button path and individual-button path share the same evidence semantics.
The workflow polling endpoint returns a compact `workflowReceipt`, while the
install, replay/export, and direct handoff polling endpoints return compact
`jobReceipt` objects. The GUI displays these beside the job status so the
reviewer can see whether offline gates are inspectable, how many
failures/blocks/pending physical gates remain, which APK/render artifacts were
produced, whether product-path readiness blocked a live rung, and whether
direct PendingIntent is still awaiting product-path evidence.
The companion `/api/status` health payload advertises `apiVersion`,
`receiptSchemaVersion`, and receipt capabilities such as
`generate-apk-receipt`, `artifact-preview`, `workflow-render-previews`,
`evidence-bundle`, `workflow-receipt`, `direct-handoff-preflight`, and
`runner-job-receipts`; the hosted GUI should warn if a user connects an older
local companion that lacks those capabilities. The
`artifact-preview` capability means the companion can serve generation-receipt
and workflow-receipt sample PNGs through the token-protected
`/api/artifact-preview` route. That route is only for generated local PNG
artifacts and is part of offline visual inspection, not a substitute for
Quest product-path focus evidence.
The `evidence-bundle` capability means the GUI can ask the local companion to
zip a workflow, generation, or runner summary plus referenced JSON/TXT/LOG/CSV
and PNG artifacts under known artifact roots. The bundle includes a manifest
and is review evidence only; it does not replace Quest product-path focus or
manual headset gates.
The runner's `Ready wait (s)` field controls how long these jobs wait for
product-path readiness before classifying the attempt as blocked; the companion
clamps it to 0-28800 seconds. A pre-product-path readiness block records one
blocked trial and stops, because repeated blocked trials would not add product
path evidence.
The optional `Wake before readiness` runner toggle is ignored for `Preflight
only` and passed through only for live direct-handoff attempts. Its receipt
field exists so reviewers can distinguish ordinary handoff evidence from a run
where the host sent a wake key before readiness sampling.
A `warn` status is expected when the physical 10/10 direct PendingIntent Quest
trials are not requested or cannot start because the headset is asleep.
