# Chaining And Validation

## Chain Ownership

For multi-APK experiments, use the standalone orchestrator APK as the plan
owner when possible:

```text
package: org.mesmerprism.viscereality.orchestrator
activity: org.mesmerprism.viscereality.orchestrator.ExperimentOrchestratorActivity
action: org.mesmerprism.viscereality.orchestrator.BROKER
```

The questionnaire app also keeps a compatible questionnaire-owned broker:

```text
package: org.mesmerprism.viscereality.questionnaires2d
activity: org.mesmerprism.viscereality.questionnaires2d.QuestChainBrokerActivity
action: org.mesmerprism.viscereality.questionnaires2d.BROKER
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
```

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
adb -s <serial> shell am start -n org.mesmerprism.viscereality.questionnaires2d/.MainActivity
```

Launch temporal tracer command replay:

```powershell
adb -s <serial> shell am start -n org.mesmerprism.viscereality.temporaltracer2d/org.mesmerprism.viscereality.temporaltracer2d.MainActivity --ez mq.autoTrace true --es mq.participantName AutoTemporal --es mq.participantId AUTO001 --es mq.language English --es mq.sessionId temporal-smoke
```

## Controller Boundary

A 2D orchestrator cannot reliably listen for raw Meta Touch controller events
while another immersive app owns focus. Real controller-button gates belong in
the active Unity/OpenXR app, which should then emit the same ChainLink or broker
intent already validated through synthetic commands.

