# Minimal APK Trigger Protocol

This is the product contract for chaining one generated Quest 2D questionnaire
APK with one immersive Unity/stimulus APK while keeping all study logic inside
the questionnaire APK.

For the short Unity-user recipe, see
[minimal-trigger-integration-guide.md](minimal-trigger-integration-guide.md).
For the transport decision record, see
[trigger-transport-decision-record.md](trigger-transport-decision-record.md).

## Decision

Use explicit Android app intents as the primary in-headset transport. Unity
emits passive trigger IDs; the generated 2D questionnaire APK maps those trigger
IDs against its own protocol state.

```text
Meta Home
  -> generated 2D questionnaire APK
  -> configured immersive Unity/stimulus APK with trigger receiver extras
  -> passive trigger intent with mq.triggerId
  -> same generated 2D questionnaire APK resumes the next configured block
```

LSL is useful as an optional lab-network trigger source, but it should not be
the default headset-to-headset app-switching mechanism. A host-side LSL bridge
can receive an LSL marker and forward `command=trigger` plus `triggerId` into
the same questionnaire-owned Android broker. That keeps LSL as transport only.

Do not make Unity, LSL, or a wrapper decide questionnaire order, questionnaire
type, scoring, participant state, block progression, repeat behavior, or export
behavior.

## Transport Decision

| Transport | Use it for | Do not use it for | Product status |
| --- | --- | --- | --- |
| Android intent from foreground Unity to generated questionnaire APK | Default in-headset app handoff. It can bring the existing 2D panel forward with `mq.triggerId`. | Questionnaire order, scoring, block routing, participant state, or raw controller input. | V2 default |
| Host-side LSL bridge | Lab markers from existing Wi-Fi/LSL equipment. It can translate a marker into the same questionnaire-owned `trigger` command. | Direct Quest foreground switching without Android lifecycle rules, or any questionnaire decision payload. | Optional adapter |
| Native LSL listener inside the 2D APK | Future studies that truly require headset-side LSL stream listening. | V1 simplicity, because Android foreground/background launch limits still apply. | Future/advanced |
| ChainLink/broker/orchestrator helpers | Legacy plans, debugging, closed APKs, and fallback validation. | The public two-APK v2 product path when source Unity can emit passive triggers. | Legacy/advanced |

## Why Android Intents Are The Default

Android intents are the native app-to-app lifecycle primitive on Quest. They can
target a known package/activity, carry stable extras, and bring the existing
questionnaire activity forward with `SINGLE_TOP`/`REORDER_TO_FRONT`.

Android also restricts background activity launches, especially for apps
targeting newer Android versions. A native LSL listener inside a background 2D
APK would still need a foreground/visible activity or carefully configured
PendingIntent behavior before it could reliably bring a panel to the front.
That makes native LSL a possible future input source, but not the simplest v1
handoff mechanism.

LSL itself remains appropriate for lab markers. It discovers streams over the
network and then receives samples over a transport connection. On Android,
`liblsl` can be packaged as an AAR, but that adds SDK/NDK/CMake build work and
does not remove Android foreground launch constraints.

Primary source references:

- Android background activity launch restrictions:
  https://developer.android.com/guide/components/activities/background-starts
- Android PendingIntent/background launch security:
  https://developer.android.com/guide/components/activities/secure-bal
- LSL Android build notes:
  https://labstreaminglayer.readthedocs.io/dev/build_android.html
- LSL transport/user guide:
  https://labstreaminglayer.readthedocs.io/info/user_guide.html

## Static Unity Trigger Catalog

Every chainable Unity/stimulus APK should embed one trigger catalog at one of
the builder-scanned paths, preferably:

```text
Assets/StreamingAssets/mq/questionnaire-trigger-catalog.json
```

The catalog is an event manifest only:

```json
{
  "schemaVersion": "mq.quest_questionnaire_trigger_catalog.v1",
  "catalogVersion": "1.0.0",
  "scenarioId": "example-stimulus",
  "package": "org.questquestionnaire.example",
  "activity": "com.unity3d.player.UnityPlayerGameActivity",
  "label": "Example Stimulus",
  "triggers": [
    {
      "triggerId": "trigger_1_complete",
      "label": "After trigger 1",
      "description": "Passive event emitted by the foreground stimulus APK."
    }
  ]
}
```

Forbidden in a Unity trigger catalog:

- `recommendedMode`
- `questionnaireMode`
- `questionnaireType`
- `questionnaireSequence`
- `blockId`
- `blockNumber`
- `flowMode`
- `finishBehavior`
- `nextPackage`
- `nextActivity`
- scoring/export/participant-state fields

Those fields belong in the generated questionnaire config, not in Unity.

## Runtime Unity Trigger Intent

At the trigger point, Unity launches or reorders the questionnaire panel with an
explicit intent.

Required:

```text
action: org.questquestionnaire.questionnaires2d.RUN
component: org.questquestionnaire.questionnaires2d/.MainActivity
extra: mq.triggerId=<catalog trigger id>
flags: FLAG_ACTIVITY_REORDER_TO_FRONT | FLAG_ACTIVITY_SINGLE_TOP
```

In the questionnaire-first product path, the questionnaire APK supplies the
return target when it launches Unity:

```text
mq.triggerReceiverPackage=<generated questionnaire package>
mq.triggerReceiverActivity=<generated questionnaire activity>
mq.triggerReceiverAction=org.questquestionnaire.questionnaires2d.RUN
```

Unity trigger code should read those `mq.triggerReceiver*` extras from its
launch intent and send the passive trigger to that target. Public/preloaded
Unity demos in this repo must not hard-code a questionnaire package fallback:
if they are opened directly without receiver extras, they should keep running
as stimulus demos and ignore questionnaire handoff. Reusable developer
templates may document an explicit local fallback, but that is not the product
contract.

Public passive Unity snippets and demos also should not expose the older
`org.questquestionnaire.CHAIN_COMMAND` action. The generated questionnaire APK
launches the immersive Unity activity explicitly after its configured first
block, and Unity returns by using only the questionnaire-supplied
`mq.triggerReceiver*` target.

If the Unity activity uses `launchMode="singleTop"`, it must make the newest
Android intent visible to Unity code by calling `setIntent(intent)` in
`onNewIntent()`. Otherwise a direct Meta Home launch can accidentally reuse old
questionnaire receiver extras. The public three-circle demo uses a tiny
`QuestQuestionnaireUnityActivity` subclass for this and still remains a fully
immersive Unity APK.

Allowed metadata:

```text
mq.handoffSchema=mq.handoff.v1
mq.sessionId=<stable session id>
mq.experimentId=<experiment id>
mq.scenarioId=<stimulus id>
mq.trialId=<trial id>
mq.triggerSource=<source label>
mq.triggerTimestampUtc=<UTC timestamp>
mq.triggerTimestampUnixMs=<Unix milliseconds>
mq.callerPackage=<Unity package>
mq.callerActivity=<Unity activity>
```

Forbidden runtime trigger extras from Unity:

```text
mq.questionnaireMode
mq.questionnaireSequence
mq.blockId
mq.blockNumber
mq.finishBehavior
mq.nextPackage
mq.nextActivity
mq.exportBehavior
mq.score*
```

The copy-first Unity source file for this v2 product path is:

```text
MyQuestionnaireVR-2D/tools/unity/QuestQuestionnairePassiveTriggerBridge.cs
```

Use it from Unity as:

```csharp
QuestQuestionnairePassiveTriggerBridge.EmitTrigger("trigger_1_complete");
```

That file intentionally has no hard-coded questionnaire package fallback and no
questionnaire-routing extras. If Unity was not launched by the generated
questionnaire APK and therefore has no `mq.triggerReceiver*` launch extras, the
bridge logs a warning and does not perform questionnaire handoff.

## Optional LSL Trigger Input

For labs that already emit LSL markers, use the host bridge as:

```json
{
  "schemaVersion": "my-questionnaire-2d.lsl-chain-command.v1",
  "command": "trigger",
  "sessionId": "demo-session-001",
  "scenarioId": "example-stimulus",
  "trialId": "trial-001",
  "triggerId": "trigger_1_complete",
  "triggerSource": "external-lsl-marker",
  "triggerTimestampUtc": "2026-06-09T12:00:00.000Z"
}
```

The bridge forwards this to the questionnaire broker as `mq.brokerCommand=trigger`
and `mq.triggerId=<id>`. The questionnaire APK then chooses the next block from
its own stored protocol. LSL does not choose the questionnaire.

Native in-APK LSL can be considered later if a study needs direct headset-side
stream listening. If added, it must feed the same broker/state machine and obey
the same passive-trigger rules.

The v1 host bridge rejects routing fields on `command=trigger`. Passive LSL
trigger commands may carry only `triggerId` plus inert session/source/timing
metadata; legacy LSL commands such as `startPlan` remain advanced tooling and
are not the public two-APK product path.

## Repeat Rule

Repeated triggers do not replay completed blocks by default. A block may repeat
only if the generated questionnaire protocol explicitly marks that step
`allowRepeat=true` or `repeatable=true`.

## Validation

Run the minimal protocol validator before publishing demos or release packages:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MyQuestionnaireVR-2D\tools\validate-minimal-apk-trigger-protocol.ps1
```

This writes a local receipt under
`MyQuestionnaireVR-2D\artifacts\minimal-apk-trigger-protocol\...` and checks
the passive trigger catalogs, LSL trigger example, Unity bridge receiver
contract, questionnaire broker/launch tests, builder multi-trigger behavior,
questionnaire APK build, and Unity input-modality metadata. It does not install,
wake, launch, force-stop, or foreground-switch a physical headset.

For the concrete two-APK public demo pair, run the Quest gate wrapper:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MyQuestionnaireVR-2D\tools\quest-minimal-apk-trigger-protocol-validate.ps1 `
  -SkipQuestionnaireBuild
```

By default this is a dry-run preflight. It checks the passive Unity trigger
contract and generated questionnaire config before any live headset gate.

For a standalone no-headset audit of any generated config and Unity APK pair,
run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MyQuestionnaireVR-2D\tools\validate-two-apk-pair.ps1 `
  -QuestionnaireConfig <generated-questionnaire.config.json> `
  -UnityApk <unity-stimulus.apk>
```

This pair audit checks the embedded Unity trigger catalog, package/activity
agreement, trigger-to-block coverage, and questionnaire-owned return-block
registry.

To prepare the live operator gate without touching the headset, generate a
typed two-APK packet:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MyQuestionnaireVR-2D\tools\new-two-apk-live-validation-packet.ps1
```

The packet bundles the pair audit, dry-run preflight, a runbook, and an
operator signoff template. It explicitly checks the participant-facing path:
start the generated questionnaire APK first, let it launch the immersive Unity
APK, fire a passive Unity trigger, then verify the questionnaire resumes the
block selected by its own protocol state.

The Quest wrapper validates the generated three-circle questionnaire config,
verifies Unity input modality, and proves the packaged questionnaire APK is
`questionnaireFirst -> Block 1 -> openNext -> immersive Unity` without touching
a headset. Run the physical gate only with explicit operator intent:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MyQuestionnaireVR-2D\tools\quest-minimal-apk-trigger-protocol-validate.ps1 `
  -RunLive -Serial <quest-serial>
```

The live run may install and launch APKs. A dry-run pass still leaves Quest
install, participant launch, Unity trigger input, questionnaire return, and
export pull as live evidence gates.

The local companion exposes the same wrapper as a token-protected developer
job:

```text
POST /api/minimal-protocol
GET  /api/minimal-protocol-job?runId=<run-id>
```

The endpoint defaults to dry-run/software preflight unless the payload
explicitly sets `runLive=true` with a Quest serial. A dry-run receipt reports
`pass-with-physical-pending`; that is expected and must not be treated as a
live headset pass.

For the narrower passive-artifact check only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MyQuestionnaireVR-2D\tools\validate-passive-trigger-protocol.ps1
```

The validator checks source trigger catalogs, embedded APK catalogs when an APK
path is supplied, and LSL trigger command examples for forbidden questionnaire
logic fields.
