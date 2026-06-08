# Existing APK Hooks

Use this when chaining an already-built Quest 2D Questionnaire stimulus APK such as Peripersonal Space Right.

## Hook Choices

### Wrapper Hook

Use the wrapper hook for closed or already-built APKs that you do not want to rebuild.

The orchestrator launches:

```text
org.questquestionnaire.chainhookwrapper/.ChainHookActivity
```

The wrapper then launches the real target app from chain-plan extras:

```text
targetPackage=org.questquestionnaire.stimulusdemo
targetActivity=com.unity3d.player.UnityPlayerGameActivity
```

This proves app routing and can run timed chains such as:

```text
Peripersonal Space Right -> questionnaire
questionnaire -> Peripersonal Space Right
```

For automated validation, set `mq.autoContinueDelayMs`. For real experiments,
use the wrapper only when a timed segment is acceptable or when a human/operator
gate confirms the target scenario has progressed.

The manual gate tool disables wrapper auto-continue and leaves the orchestrator
waiting until an operator sends `continuePlan`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-wrapper-manual-gate-validate.ps1 `
  -Mode Start `
  -Serial 2G0YC1ZG1002QL `
  -SkipBuild
```

After headset/controller completion, continue the same evidence directory with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-wrapper-manual-gate-validate.ps1 `
  -Mode Continue `
  -Serial 2G0YC1ZG1002QL `
  -OutputRoot .\artifacts\qmanual\<run-id>
```

### Source Hook

Use the source hook when you can rebuild the Unity app. The Unity app receives
the chain intent directly and calls the orchestrator when the scenario is truly
finished:

```csharp
QuestExperimentChainHook.ContinueCurrentPlan();
```

This is the preferred route for semantic experiment chains, because the
questionnaire starts after the scenario says it is complete rather than after a
timer.

### Binary APK Patching

Do not treat binary patching as the normal workflow. A repacked Unity APK must
be re-signed, usually cannot update over the original package signature, and
still cannot infer scenario completion unless code is injected deeply enough to
understand the app. In practice it is less reliable than either a wrapper hook
or a rebuildable source hook.

## Current Peripersonal Space Right Evidence

Closed-APK wrapper validation passed on Quest 3 serial `2G0YC1ZG1002QL`:

```text
artifacts\quest-orchestrator-wrapper-chain-validation\20260605T035658Z\quest-orchestrator-wrapper-chain-validation-summary.json
```

Validated package/activity:

```text
org.questquestionnaire.stimulusdemo/com.unity3d.player.UnityPlayerGameActivity
```

The orchestrator completed the chain, the wrapper received and launched the
target, the questionnaire exported JSON/CSV, and export counts matched exactly:

```text
37 MAIA-2 answers
8 MAIA-2 scores
3 pictographic selections
42 slider answers
```

The validation warning is expected for this closed APK: Horizon OS displayed a
controller-required launch check, so the wrapper proof covers launch routing and
questionnaire export. A source hook or manual controller gate is still needed to
prove semantic scenario completion inside the Peripersonal app.
