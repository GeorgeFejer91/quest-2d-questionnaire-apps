# Minimal Trigger Integration Guide

This is the short public recipe for linking one generated Quest questionnaire
APK with one Unity or stimulus APK.

For the full transport decision, including why native LSL is future/advanced
rather than the default product path, see
[trigger-transport-decision-record.md](trigger-transport-decision-record.md).

## Recommended Protocol

Use Android intents for the headset app-to-app handoff. Use LSL only as an
optional host-side marker adapter into the same questionnaire-owned trigger
broker.

```text
participant starts generated 2D questionnaire APK
  -> questionnaire runs Block 1
  -> questionnaire launches Unity/stimulus APK with mq.triggerReceiver* extras
  -> Unity emits mq.triggerId at the real stimulus moment
  -> same questionnaire APK resumes the next configured block
```

The generated 2D questionnaire APK owns study logic: block order, trigger
mapping, questionnaire type, scoring, participant/session state, repeat rules,
and exports. Unity and LSL only emit passive event IDs.

## Unity Developer Checklist

1. Add a trigger catalog under Unity StreamingAssets:

```text
Assets/StreamingAssets/mq/questionnaire-trigger-catalog.json
```

2. Keep the catalog as an event manifest only:

```json
{
  "schemaVersion": "mq.quest_questionnaire_trigger_catalog.v1",
  "catalogVersion": "1.0.0",
  "scenarioId": "my-stimulus",
  "package": "org.example.mystimulus",
  "activity": "org.example.mystimulus.MainUnityActivity",
  "label": "My Stimulus",
  "triggers": [
    {
      "triggerId": "trigger_1_complete",
      "label": "After trigger 1"
    }
  ]
}
```

3. Copy the bridge into the Unity project:

```text
MyQuestionnaireVR-2D/tools/unity/QuestQuestionnairePassiveTriggerBridge.cs
```

The packaged builder also includes a copyable starter kit under:

```text
unity/passive-trigger-kit/
```

Use that kit for the trigger catalog template and optional `singleTop` activity
snippet.
The passive snippet is launched by explicit package/activity from the
questionnaire APK; it does not require the legacy
`org.questquestionnaire.CHAIN_COMMAND` action.

4. Call it at the stimulus event:

```csharp
QuestQuestionnairePassiveTriggerBridge.EmitTrigger("trigger_1_complete");
```

5. If the Unity activity uses `singleTop`, make the latest launch intent visible
to Unity. The public demo does this with a tiny Android activity subclass:

```java
public class QuestQuestionnaireUnityActivity extends UnityPlayerGameActivity {
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
    }
}
```

## Forbidden Unity Payload

Do not put these in the Unity trigger catalog or Unity runtime trigger intent:

```text
questionnaireMode
questionnaireSequence
questionnaireType
blockId
blockNumber
finishBehavior
nextPackage
nextActivity
score*
exportBehavior
participantState
```

Those are questionnaire protocol decisions and belong only to the generated 2D
questionnaire APK/config.

## LSL Adapter Boundary

LSL can work, but it should be an adapter, not the default headset app-switch
transport. The v1 host bridge receives a lab-network LSL marker and sends an
Android broker intent to the questionnaire APK.

Passive LSL trigger samples may carry only:

```text
schemaVersion
command=trigger
sessionId
invocationId
experimentId
scenarioId
trialId
chainId
triggerId
triggerSource
triggerTimestampUtc
triggerTimestampUnixMs
```

Example:

```json
{
  "schemaVersion": "my-questionnaire-2d.lsl-chain-command.v1",
  "command": "trigger",
  "sessionId": "demo-session-001",
  "scenarioId": "three-circle-demo",
  "trialId": "trial-001",
  "triggerId": "trigger_1_complete",
  "triggerSource": "external-lsl-marker",
  "triggerTimestampUtc": "2026-06-09T12:00:00.000Z"
}
```

The bridge rejects routing fields on `command=trigger`. If a future native
Android LSL listener is added inside the questionnaire APK, it should feed this
same passive trigger broker/state machine rather than inventing a second study
logic path.

## Validation

Before publishing a Unity demo or generated questionnaire APK, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MyQuestionnaireVR-2D\tools\validate-passive-trigger-protocol.ps1

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MyQuestionnaireVR-2D\tools\quest-minimal-apk-trigger-protocol-validate.ps1 `
  -SkipQuestionnaireBuild
```

The first command checks passive source/catalog/LSL boundaries. The second
checks the concrete two-APK dry-run path. A dry-run pass still leaves the live
Quest install, launch, Unity trigger, questionnaire return, and export pull as
physical evidence gates.

To audit a concrete generated questionnaire config against a concrete
Unity/stimulus APK before headset install, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MyQuestionnaireVR-2D\tools\validate-two-apk-pair.ps1 `
  -QuestionnaireConfig .\MyQuestionnaireVR-2D\QuestionnaireConfigs\examples\quest-questionnaire-three-circle-protocol-demo.config.json `
  -UnityApk .\example-scenario-apk\unity-project\three-circle-trigger-demo\Builds\QuestQuestionnaireThreeCircleTriggerDemo.apk
```

This checks package/activity agreement, trigger coverage, questionnaire-owned
return blocks, and APK badging when Android build-tools are available.

For the operator-facing live proof packet:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MyQuestionnaireVR-2D\tools\new-two-apk-live-validation-packet.ps1
```

The packet prepares a runbook and typed signoff for the exact product sequence:
start the generated questionnaire APK from Meta Home, let it launch immersive
Unity, fire the passive Unity trigger, and confirm the questionnaire APK resumes
its own next block.
