# Quest Questionnaire Passive Trigger Kit

This is the smallest Unity-side integration for the v2 two-APK product path.
It keeps the Unity APK passive and lets the generated Quest 2D questionnaire
APK own all study logic.

## What To Copy

Copy this file into a Unity project:

```text
../QuestQuestionnairePassiveTriggerBridge.cs
```

Add this catalog to Unity StreamingAssets:

```text
Assets/StreamingAssets/mq/questionnaire-trigger-catalog.json
```

Start from:

```text
questionnaire-trigger-catalog.template.json
```

If your Unity activity uses `launchMode="singleTop"`, adapt:

```text
QuestQuestionnaireUnityActivity.template.java
AndroidManifest.activity-snippet.xml
```

The Java activity must use your Unity Android package name. Its only job is to
call `setIntent(intent)` in `onNewIntent()` so Unity always reads the latest
questionnaire-supplied receiver extras.
The passive v2 snippet does not expose the older
`org.questquestionnaire.CHAIN_COMMAND` intent action; the generated
questionnaire APK launches the Unity activity explicitly and supplies the
trigger receiver extras.

## Unity Call

Call the bridge at the real stimulus event:

```csharp
QuestQuestionnairePassiveTriggerBridge.EmitTrigger("trigger_1_complete");
```

For example:

```csharp
public void OnVideoFinished()
{
    QuestQuestionnairePassiveTriggerBridge.EmitTrigger("video_complete");
}
```

## Product Contract

The participant starts the generated questionnaire APK. The questionnaire APK
runs the configured first block, saves, then launches Unity with:

```text
mq.triggerReceiverPackage
mq.triggerReceiverActivity
mq.triggerReceiverAction
```

Unity reads those launch extras and sends back only:

```text
mq.triggerId
mq.handoffSchema
mq.triggerSource
mq.triggerTimestampUtc
mq.triggerTimestampUnixMs
optional session/scenario/trial metadata
```

The bridge allow-lists that outgoing metadata. Extra values that are not
passive session/source/timing fields are ignored before the trigger intent is
sent back to the questionnaire APK.

Do not add questionnaire decisions to Unity:

```text
questionnaireMode
questionnaireType
questionnaireSequence
blockId
blockNumber
finishBehavior
nextPackage
nextActivity
score
exportBehavior
participantState
```

If Unity is opened directly without `mq.triggerReceiver*` extras, the bridge
logs a warning and does not perform questionnaire handoff. That is intentional:
public Unity demos should not contain hard-coded questionnaire package
fallbacks.

## Validate

From the repo root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MyQuestionnaireVR-2D\tools\validate-passive-trigger-protocol.ps1
```

That validator checks this kit, the Unity bridge, trigger catalogs, LSL passive
trigger rules, and the transport decision record.
