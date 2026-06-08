# Unity Quest Questionnaire Chain Bridge

Copy these files into a Unity Android project that needs to participate in an
on-headset APK chain with the 2D questionnaire panel app:

- `QuestQuestionnaireChainBridge.cs`: static Android intent bridge.
- `ChainLinkControllerHook.cs`: optional scene component that watches the left
  Quest controller and emits a passive `mq.triggerId` event.
- `ChainLinkTimedTrigger.cs`: optional scene component that fires the same
  chain action from a Unity timer, without requiring controller input.
- `QuestQuestionnairePassiveTriggerDemo.cs`: optional scene component for
  simple 2/3/4-trigger stimulus demos. Configure a list of passive trigger ids
  such as `trigger_1_complete`, `trigger_2_complete`, and
  `trigger_3_complete`; the questionnaire APK decides which block each event
  resumes.

Unity/stimulus APKs should stay passive in the product architecture. They may
present stimulus content and emit simple trigger events, but they should not
choose questionnaire order, questionnaire type, scoring, participant state,
block progression, or export behavior. The generated 2D questionnaire APK owns
that study logic and interprets `mq.triggerId` against its own protocol state.
Use `mq.blockId`, `mq.blockNumber`, or `mq.questionnaireMode` only as
diagnostic or legacy fallbacks.

## Drop-In Timed Trigger

For controller-free experiment switching, add `ChainLinkTimedTrigger` to a
GameObject in the foreground Unity scene. This lets the Unity APK emit a
passive trigger and bring the 2D questionnaire panel forward after a fixed
delay.

Common settings:

- `Action = ContinueBrokerPlan`: legacy broker fallback for existing ChainLink
  plans.
- `Action = ChainLinkNextBlock`: use when the Unity APK should send the
  standalone legacy ChainLink `nextBlock` command.
- `Action = LaunchQuestionnaire`: use when the Unity APK is started directly
  and should open the questionnaire APK with `mq.triggerId` and no broker
  state.
- `Initial Delay Seconds`: time after scene start before firing.
- `Repeat`, `Repeat Interval Seconds`, and `Max Sends`: use for repeated
  timed pictographic probes. `Max Sends = 0` means unlimited sends.

The hook copies incoming broker extras from the Unity activity intent by
default, then attaches timing metadata:

```text
mq.triggerId = <configured passive trigger id>
mq.triggerSource = unity-timed-trigger
mq.triggerTimestampUtc = <UTC ISO-8601 timestamp>
mq.triggerTimestampUnixMs = <milliseconds since epoch>
mq.commandSource = unity-timed-hook
mq.triggerDelaySeconds = <configured delay>
mq.triggerSequence = <1-based send count>
```

Example: if the scenario should show a pictographic questionnaire every two
minutes while it is running, set:

```text
Action = ContinueBrokerPlan
Initial Delay Seconds = 120
Repeat = true
Repeat Interval Seconds = 120
Max Sends = 3
```

Example: if the Unity APK itself should emit a single end trigger when launched
directly, set:

```text
Action = LaunchQuestionnaire
Initial Delay Seconds = 0.5
Trigger Id = video_complete
Finish Behavior = resumeCaller
Caller Package = <this Unity package>
Caller Activity = <this Unity activity>
```

The timer is the quickest way to prove the switching mechanism in-device before
adding the physical controller gate. Once the timer path works, the controller
hook only has to emit the same passive trigger intent.

## Drop-In Multi-Trigger Demo

For testing builder scans against more than one trigger, add
`QuestQuestionnairePassiveTriggerDemo` to a GameObject and configure its
`Triggers` list. The public fixtures under
`example-scenario-apk/multi-trigger-demos/` provide matching catalogs for 2,
3, and 4 passive trigger ids. The component can launch the questionnaire APK
directly with `mq.triggerId` or send a ChainLink trigger command, but it does
not choose questionnaire modules, block order, scoring, or export behavior.

## Drop-In ChainLink Controller Hook

For the common ChainLink flow, add `ChainLinkControllerHook` to a GameObject in
the foreground Unity scene. In the inspector, set:

- `Button`: usually `SecondaryButton` for the left controller Y button, because
  X/left primary is already used in the Peripersonal Space scene controls.
- `Trigger Id`: the passive event id for the questionnaire APK to interpret.
- `Experiment metadata`: chain/session fields you want repeated in ChainLink
  event logs.
- `Debounce Seconds`: keep the default unless the scenario needs rapid repeats.

At runtime, the hook listens with Unity XR input while the Unity APK owns the
foreground OpenXR session. On a rising button edge it starts ChainLink with:

```text
action = org.questquestionnaire.chainlink.COMMAND
component = org.questquestionnaire.chainlink/.ChainLinkActivity
mq.command = trigger
mq.triggerId = <configured passive trigger id>
mq.triggerTimestampUtc = <UTC ISO-8601 timestamp>
mq.triggerTimestampUnixMs = <milliseconds since epoch>
```

Legacy next-block calls use `org.questquestionnaire.chainlink.COMMAND` with
`mq.command = nextBlock`; new V2 source triggers should prefer
`mq.command = trigger` plus `mq.triggerId`.

This is the reliable route for controller-triggered APK switches. Android and
Horizon OS do not deliver another immersive APK's controller events to a
background 2D app. Leave `Trigger Id` blank only for legacy `nextBlock`
ChainLink plans.

Scenario scripts can also call the bridge directly:

```csharp
QuestQuestionnaireChainBridge.LaunchQuestionnaireTrigger("video_complete", new Dictionary<string, string>
{
    ["mq.chainId"] = "participant-001-chain-a",
    ["mq.scenarioId"] = "peripersonal-space-right",
    ["mq.trialId"] = "trial-03"
});
```

For rebuilt Quest 2D Questionnaire scenario APKs, also add an Android intent filter for
`org.questquestionnaire.CHAIN_COMMAND` to the Unity activity. The
`QuestExperimentChainHook` script in the Quest 2D Questionnaire stimulus source tree does this
passively: it logs incoming broker commands, refreshes launch intents while the
Unity activity stays alive, and exposes one completion call for scenario
scripts.

Preferred brokered flow:

1. Start the broker plan once, usually from the first scenario.
2. When a scenario reaches its passive trigger point, emit the configured trigger id.
3. The questionnaire saves locally, interprets the trigger, and returns/opens the next app from its own protocol state.

Start a plan:

```csharp
string chainPlanJson = @"{
  ""schemaVersion"": ""my-questionnaire-2d.chain-plan.v1"",
  ""chainId"": ""participant-001-chain-a"",
  ""steps"": [
    {
      ""id"": ""scenario-01"",
      ""type"": ""scenario"",
      ""package"": ""org.example.scenario01"",
      ""activity"": ""org.example.scenario01.MainActivity""
    },
    {
      ""id"": ""questionnaire-after-scenario-01"",
      ""type"": ""questionnaire"",
      ""package"": ""org.questquestionnaire.questionnaires2d"",
      ""activity"": "".MainActivity"",
      ""extras"": {
        ""mq.sessionId"": ""participant-001-session-a"",
        ""mq.experimentId"": ""quest-questionnaire-study"",
        ""mq.scenarioId"": ""scenario-01"",
        ""mq.trialId"": ""trial-03"",
        ""mq.participantId"": ""P001"",
        ""mq.participantName"": ""P001"",
        ""mq.language"": ""English"",
        ""mq.autoCloseDelayMs"": ""2000""
      }
    },
    {
      ""id"": ""scenario-02"",
      ""type"": ""scenario"",
      ""package"": ""org.example.scenario02"",
      ""activity"": ""org.example.scenario02.MainActivity""
    }
  ]
}";

QuestQuestionnaireChainBridge.StartBrokerPlan(chainPlanJson, new Dictionary<string, string>
{
    ["mq.chainId"] = "participant-001-chain-a"
});
```

Continue from a scenario trigger in legacy brokered plans:

```csharp
QuestQuestionnaireChainBridge.ContinueBrokerPlan();
```

If the project includes `QuestExperimentChainHook`, prefer this at the real
semantic completion point of the scenario:

```csharp
QuestExperimentChainHook.ContinueCurrentPlan();
```

You can attach result metadata to the callback:

```csharp
QuestExperimentChainHook.ContinueCurrentPlan(new Dictionary<string, string>
{
    ["mq.scenarioResultStatus"] = "complete",
    ["mq.scenarioVersion"] = version.ToString(),
    ["mq.scenarioParticipantDataPath"] = participantDataPath
});
```

The hook returns to the broker named in the incoming extras
`mq.brokerAction`, `mq.brokerPackage`, and `mq.brokerActivity`. If those extras
are absent, it falls back to the questionnaire-owned broker. This makes the
same Unity hook compatible with the standalone orchestrator APK.

In the current Quest 2D Questionnaire stimulus source project, `ExperimentRun` already calls
`QuestExperimentChainHook.ContinueCurrentPlan(...)` after `ThankYou()`, so a
rebuilt Peripersonal-style APK can return to the broker at real experiment
completion instead of using a wrapper timer.

Before rebuilding that APK, run the Android project's preflight from
`MyQuestionnaireVR-2D`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\unity-source-hook-preflight.ps1
```

It checks the Unity editor version, package manifest entries, package source
metadata, free disk space, Android chain intent filter, and the hook files.
Treat source-hook rebuild validation as blocked until that preflight and Unity
compilation pass.

For source-hook APKs, chain-plan scenario steps should target the Unity package
directly with `action=org.questquestionnaire.CHAIN_COMMAND`. For compiled
APKs that cannot be rebuilt, use the separate hook-wrapper APK instead.

Simple direct passive trigger launch, without broker state:

```csharp
QuestQuestionnaireChainBridge.LaunchQuestionnaireTrigger("video_complete", new Dictionary<string, string>
{
    ["mq.sessionId"] = "participant-001-session-a",
    ["mq.experimentId"] = "quest-questionnaire-study",
    ["mq.scenarioId"] = "scenario-01",
    ["mq.trialId"] = "trial-03",
    ["mq.participantId"] = "P001",
    ["mq.participantName"] = "P001",
    ["mq.language"] = "English",
    ["mq.finishBehavior"] = "resumeCaller",
    ["mq.callerPackage"] = "org.example.scenario01",
    ["mq.callerActivity"] = "org.example.scenario01.MainActivity",
    ["mq.autoCloseDelayMs"] = "2000"
});
```

For source scenes that should not start stimulus timing immediately, keep the
start gate inside Unity. Show a visible `Start experiment` target, wait for
foreground Unity input, then call `LaunchQuestionnaireTrigger(...)` for the
configured passive trigger.
Validation-only launch extras can be read through `ReadValidationExtras()`; use
an explicit `mq.validationAutoStart=true` bypass for unattended scripts rather
than silently starting product runs without a participant click.

For generic demo/stimulus APKs, do not ship controller-only input metadata.
Enable Quest controller interaction profiles and hand interaction profiles
together, and declare optional hand tracking in `AndroidManifest.xml`. Reserve
controller-only builds for experiments where the controller itself is part of
the measured task; otherwise Horizon may block the launch behind a
controller-required dialog before the questionnaire handoff can start.

Use direct `mq.finishBehavior=openNext` with `mq.nextPackage` and `mq.nextActivity` only for simple two-app chains. Use the broker for multi-step experiment chains.

When Unity is resumed directly by the questionnaire or launched by the broker
after a questionnaire step, call `ReadQuestionnaireResult()` and look for
`mq.resultStatus=complete`, `mq.triggerId`, `mq.runId`, `mq.chainId`, and the
JSON/CSV/SVG export paths. After your scenario code has accepted the expected
trigger result, call:

```csharp
QuestQuestionnaireChainBridge.ClearQuestionnaireResult();
```

That clears the handled Android intent from the live Unity Activity so a later
focus/resume callback cannot re-read a stale panel result. The bridge also
creates a distinct return `PendingIntent` request key from caller package,
caller activity, `mq.triggerId`, `mq.chainStepId`, and `mq.blockId`; keep those
extras stable and unique for each semantic trigger or chain step.
