# Unity Quest Questionnaire Chain Bridge

Copy these files into a Unity Android project that needs to participate in an
on-headset APK chain with the 2D questionnaire panel app:

- `QuestQuestionnaireChainBridge.cs`: static Android intent bridge.
- `ChainLinkControllerHook.cs`: optional scene component that watches the left
  Quest controller and sends `mq.command=nextBlock` to ChainLink.
- `ChainLinkTimedTrigger.cs`: optional scene component that fires the same
  chain action from a Unity timer, without requiring controller input.

## Drop-In Timed Trigger

For controller-free experiment switching, add `ChainLinkTimedTrigger` to a
GameObject in the foreground Unity scene. This lets the Unity APK bring the 2D
questionnaire panel forward after a fixed delay.

Common settings:

- `Action = ContinueBrokerPlan`: use when ChainLink/broker launched the Unity
  APK and the timer should advance to the next plan block.
- `Action = ChainLinkNextBlock`: use when the Unity APK should send the
  standalone ChainLink `nextBlock` command.
- `Action = LaunchQuestionnaire`: use when the Unity APK is started directly
  and should open the questionnaire without broker state.
- `Initial Delay Seconds`: time after scene start before firing.
- `Repeat`, `Repeat Interval Seconds`, and `Max Sends`: use for repeated
  timed pictographic probes. `Max Sends = 0` means unlimited sends.

The hook copies incoming broker extras from the Unity activity intent by
default, then attaches timing metadata:

```text
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

Example: if the Unity APK itself should immediately open the baseline
questionnaire when launched directly, set:

```text
Action = LaunchQuestionnaire
Initial Delay Seconds = 0.5
Questionnaire Mode = baseline
Finish Behavior = resumeCaller
Caller Package = <this Unity package>
Caller Activity = <this Unity activity>
```

The timer is the quickest way to prove the switching mechanism in-device before
adding the physical controller gate. Once the timer path works, the controller
hook only has to emit the same broker continuation or ChainLink `nextBlock`
intent.

## Drop-In ChainLink Controller Hook

For the common ChainLink flow, add `ChainLinkControllerHook` to a GameObject in
the foreground Unity scene. In the inspector, set:

- `Button`: usually `SecondaryButton` for the left controller Y button, because
  X/left primary is already used in the Peripersonal Space scene controls.
- `Experiment metadata`: chain/session fields you want repeated in ChainLink
  event logs.
- `Debounce Seconds`: keep the default unless the scenario needs rapid repeats.

At runtime, the hook listens with Unity XR input while the Unity APK owns the
foreground OpenXR session. On a rising button edge it starts ChainLink with:

```text
action = org.mesmerprism.viscereality.chainlink.COMMAND
component = org.mesmerprism.viscereality.chainlink/.ChainLinkActivity
mq.command = nextBlock
mq.triggerTimestampUtc = <UTC ISO-8601 timestamp>
mq.triggerTimestampUnixMs = <milliseconds since epoch>
```

This is the reliable route for controller-triggered APK switches. Android and
Horizon OS do not deliver another immersive APK's controller events to a
background 2D app.

Scenario scripts can also call the bridge directly:

```csharp
QuestQuestionnaireChainBridge.SendChainLinkNextBlock(new Dictionary<string, string>
{
    ["mq.chainId"] = "participant-001-chain-a",
    ["mq.scenarioId"] = "peripersonal-space-right",
    ["mq.trialId"] = "trial-03"
});
```

For rebuilt Viscereality scenario APKs, also add an Android intent filter for
`org.mesmerprism.viscereality.CHAIN_COMMAND` to the Unity activity. The
`QuestExperimentChainHook` script in the Viscereality source tree does this
passively: it logs incoming broker commands, refreshes launch intents while the
Unity activity stays alive, and exposes one completion call for scenario
scripts.

Preferred brokered flow:

1. Start the broker plan once, usually from the first scenario.
2. When a scenario reaches its questionnaire trigger point, call `ContinueBrokerPlan()`.
3. The questionnaire saves locally, returns to the broker, and the broker opens the next plan step.

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
      ""package"": ""org.mesmerprism.viscereality.questionnaires2d"",
      ""activity"": "".MainActivity"",
      ""extras"": {
        ""mq.sessionId"": ""participant-001-session-a"",
        ""mq.experimentId"": ""viscereality-study"",
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

Continue from a scenario trigger:

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

In the current Viscereality source project, `ExperimentRun` already calls
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
directly with `action=org.mesmerprism.viscereality.CHAIN_COMMAND`. For compiled
APKs that cannot be rebuilt, use the separate hook-wrapper APK instead.

Simple direct launch, without broker state:

```csharp
QuestQuestionnaireChainBridge.LaunchQuestionnaire(new Dictionary<string, string>
{
    ["mq.sessionId"] = "participant-001-session-a",
    ["mq.experimentId"] = "viscereality-study",
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

Use direct `mq.finishBehavior=openNext` with `mq.nextPackage` and `mq.nextActivity` only for simple two-app chains. Use the broker for multi-step experiment chains.

When Unity is resumed directly by the questionnaire or launched by the broker after a questionnaire step, call `ReadQuestionnaireResult()` and look for `mq.resultStatus=complete`, `mq.runId`, `mq.chainId`, and the JSON/CSV export paths.
