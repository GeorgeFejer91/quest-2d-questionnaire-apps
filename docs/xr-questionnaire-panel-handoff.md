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
`/api/generate-apk` endpoint.
