# Chaining And Validation

## Chain Ownership

For XR app to questionnaire/tracer handoff, prefer the direct app-owned
contract first:

```text
XR app -> 2D panel -> same XR app via mq.returnPendingIntent
```

The XR app owns semantic triggers and launches the panel with
`mq.handoffSchema=mq.handoff.v1`, `mq.triggerId`, block metadata, and a
`PendingIntent` targeting the same XR activity with
`REORDER_TO_FRONT | SINGLE_TOP | NEW_TASK`. The panel saves exports before it
returns. See `../docs/xr-questionnaire-panel-handoff.md`.

For multi-APK experiments, use the standalone orchestrator APK as the plan
owner when possible:

```text
package: org.viscereality.orchestrator
activity: org.viscereality.orchestrator.ExperimentOrchestratorActivity
action: org.viscereality.orchestrator.BROKER
```

The questionnaire app also keeps a compatible questionnaire-owned broker:

```text
package: org.viscereality.questionnaires2d
activity: org.viscereality.questionnaires2d.QuestChainBrokerActivity
action: org.viscereality.questionnaires2d.BROKER
```

Both broker styles accept commands such as:

```text
startPlan
continuePlan
clearPlan
startQuestionnaire
openApp
goHome
ping
trigger
triggerComplete
```

ChainLink is now the plan compiler, trigger-mapping validator, and fallback
router. Use ChainLink-routed foreground handoff only if direct
`PendingIntent` return fails on Quest but ChainLink passes the same evidence
requirements.

## Scenario Link Modes

Use the right link mode for the target APK:

| Target type | Link mode | What it proves | Remaining gap |
| --- | --- | --- | --- |
| Existing compiled Unity APK | Wrapper hook | Orchestrator route, target launch request, questionnaire export safety | Scenario may not have reached real internal completion |
| Rebuildable Unity source APK | Source hook | Real semantic callback from scenario end event | Requires correct Unity source/build profile |
| Lab network command source | LSL bridge | External command can start/continue headset-owned plan | LSL should not own headset state |

Wrapper links are good for smoke tests, timed segments, and legacy APKs. Source
hooks are the stronger study route because the active Unity app can call back
when the scenario truly finishes.

## Validation Ladder

Use this progression before treating an APK as ready:

```text
static config validation
unit/logic tests
local Android render preview
APK build
Quest install and foreground launch
command replay/export pull
foreground-linked render pack
manual hardware input gate
full chain validation
```

For Quest work, record evidence:

- serial and model,
- package/activity,
- install output,
- foreground before/after,
- logcat window,
- export paths pulled from device,
- answer/trace counts,
- any system prompt or controller-required warning.

For direct XR-to-panel handoff, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MyQuestionnaireVR-2D\tools\quest-direct-handoff-validate.ps1 -Serial <quest-serial> -TrialCount 1 -WaitForReadySeconds 30 -FastVideoForValidation -AutoTraceForValidation
```

This validator checks APK package/activity/catalog agreement before installing,
then waits for headset readiness before starting the product path. If the
headset is asleep or Horizon is already focused on
`LaunchCheckControllerRequiredDialogActivity`, the run is `blocked` with
`initialUnityLaunchAttempted=false`; wake/wear the headset or clear the system
dialog before claiming a handoff result. Once Unity is launched, the validator
only observes and pulls evidence.

For a single evidence matrix from GUI config through local software, APKs,
local renderers, Unity bridge static checks, APK handoff preflight, and Quest
readiness, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\MyQuestionnaireVR-2D\tools\validate-builder-to-quest-workflow.ps1 -ConfigPath .\MyQuestionnaireVR-2D\QuestionnaireConfigs\generated\viscereality-maia2.config.json -RunQuestReadiness -Serial <quest-serial>
```

The builder GUI's `Validate workflow` button calls the same path through the
local companion. Treat `pending` or `blocked` Quest trial rows as honest
residual gates, not as local pipeline failures.

## ADB Baseline

Start device-facing work with read-only discovery:

```powershell
adb devices -l
adb -s <serial> shell getprop ro.product.model
adb -s <serial> shell getprop ro.build.version.release
adb -s <serial> shell wm size
adb -s <serial> shell wm density
adb -s <serial> shell dumpsys window | findstr /i "mCurrentFocus mFocusedApp"
```

Install and launch a questionnaire APK:

```powershell
adb -s <serial> install -r -d .\apks\demographic-questionnaire\MyQuestionnaireVR-2D.apk
adb -s <serial> shell am start -n org.viscereality.questionnaires2d/.MainActivity
```

Launch temporal tracer command replay:

```powershell
adb -s <serial> shell am start -n org.viscereality.temporaltracer2d/org.viscereality.temporaltracer2d.MainActivity --ez mq.autoTrace true --es mq.participantName AutoTemporal --es mq.participantId AUTO001 --es mq.language English --es mq.sessionId temporal-smoke
```

## Controller Boundary

A 2D orchestrator cannot reliably listen for raw Meta Touch controller events
while another immersive app owns focus. Real controller-button gates belong in
the active Unity/OpenXR app, which should then emit the same ChainLink or broker
intent already validated through synthetic commands.
