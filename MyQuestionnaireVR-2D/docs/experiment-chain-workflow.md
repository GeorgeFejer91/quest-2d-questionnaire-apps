# Experiment Chain Workflow

This is the recommended workflow for building Quest experiment chains that mix
Viscereality Unity APKs and the native Android questionnaire 2D panel app.

## Recommended Architecture

Use the standalone orchestrator APK as the chain owner:

```text
org.mesmerprism.viscereality.orchestrator/.ExperimentOrchestratorActivity
```

Install these APKs on the headset:

```text
Builds\ViscerealityExperimentOrchestrator.apk
Builds\MyQuestionnaireVR-2D.apk
Builds\ViscerealityChainHookWrapper.apk
```

For a portable handoff folder, publish the experiment-chain kit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\publish-experiment-chain-kit.ps1
```

This writes:

```text
Builds\ExperimentChainKit
Builds\ExperimentChainKit.zip
Builds\ExperimentChainKit-package-summary.json
```

The kit includes the core APKs, Peripersonal Space Right APK when available,
chain-plan examples, wrapper/manual-gate scripts, LSL bridge tools, Unity source
hook helper, docs, and the latest evidence summaries.

Then choose a scenario link mode per APK:

| Scenario APK type | Link mode | Best use | Completion signal |
| --- | --- | --- | --- |
| Existing compiled APK, no source rebuild | Wrapper hook | Legacy scenarios, smoke tests, timed segments | Timer or manual gate |
| Rebuildable Unity source APK | Source hook | Real experiment chain with semantic scenario completion | Unity scenario end event |
| Lab network trigger | Optional LSL bridge | Starting or continuing a headset-owned plan from another PC | LSL JSON sample translated to broker intent |

The orchestrator should remain the owner of the plan. LSL can be an input route,
but it should not replace the on-headset broker.

## Chain Patterns

### Scenario Then Questionnaire

```text
orchestrator
  -> scenario wrapper/source hook
  -> questionnaire 2D panel app
  -> orchestrator complete or next step
```

Use this when the questionnaire should capture post-scenario state.

### Questionnaire Then Scenario

```text
orchestrator
  -> questionnaire 2D panel app
  -> scenario wrapper/source hook
  -> orchestrator complete or next step
```

Use this for pre-scenario baseline questionnaires or participant setup.

### Scenario Questionnaire Scenario

```text
orchestrator
  -> scenario A hook
  -> questionnaire
  -> scenario B hook
```

Use wrapper links only if fixed timing is acceptable. Use source hooks when the
next step must wait for the scenario's real internal completion.

### Legacy Scenario With Manual Completion Gate

For an existing APK that cannot call back to the orchestrator, run the wrapper
with auto-continue disabled. The operator advances the broker only after using
the Quest controller to reach the intended scenario completion point.

Start the chain and pause after the legacy scenario launch:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-wrapper-manual-gate-validate.ps1 `
  -Mode Start `
  -Serial 2G0YC1ZG1002QL `
  -SkipBuild `
  -TargetPackage com.Viscereality.ViscerealityPeriPersonalSpaceRight `
  -TargetActivity com.unity3d.player.UnityPlayerGameActivity `
  -ChainPlanPath .\QuestionnaireConfigs\examples\peripersonal-space-right-then-questionnaire.chain-plan.json
```

The tool writes `operator-instructions.md` inside the evidence directory. After
the operator confirms the scenario is complete, continue the same plan:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-wrapper-manual-gate-validate.ps1 `
  -Mode Continue `
  -Serial 2G0YC1ZG1002QL `
  -OutputRoot .\artifacts\qmanual\<run-id>
```

For automated smoke testing of the same manual-continue route, use `Full` with a
short delay:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-wrapper-manual-gate-validate.ps1 `
  -Mode Full `
  -Serial 2G0YC1ZG1002QL `
  -SkipBuild `
  -AutoContinueAfterSeconds 8
```

This is still not a semantic source hook: the human/operator is the completion
witness. It is stronger than blind wrapper timing because the plan does not
advance until an explicit continue command is sent.

### Rebuildable Scenario With Source Hook

For source projects, the strongest route is an in-app semantic hook. In the
current Viscereality source tree, `ExperimentRun.NotifyExperimentChainComplete()`
already calls:

```text
QuestExperimentChainHook.ContinueCurrentPlan()
```

Run the source-candidate audit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\audit-unity-source-hook-candidates.ps1
```

Dry-run a Unity source-hook build command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-unity-source-hook-apk.ps1 `
  -DryRun `
  -SkipPreflight `
  -SkipCandidateAudit
```

Build a source-hook candidate APK from the currently hooked experiment scene:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-unity-source-hook-apk.ps1 `
  -ScenePath "Assets\Scenes\Main Questionnaire.unity" `
  -PackageId "com.Viscereality.ViscerealityPeriPersonalSpaceRight.SourceHook" `
  -ProductName "Viscereality Peripersonal Source Hook Candidate"
```

Validate the source-hook smoke plan:

```text
QuestionnaireConfigs\examples\peripersonal-source-hook-candidate-smoke.chain-plan.json
```

That smoke plan uses `mq.sourceAutoContinueDelayMs`. Remove that extra for a
real semantic experiment chain so the app advances only from its true end event.

## Evidence From Current Quest Stress Tests

Latest multi-scenario wrapper stress pass:

```text
artifacts\qbatch\20260605T040228Z\quest-installed-scenario-batch-validation-summary.json
```

Quest serial:

```text
2G0YC1ZG1002QL
```

Validated packages:

```text
com.Viscereality.ViscerealityPeriPersonalSpaceRight
com.Viscereality.ViscerealityPeriPersonalSpaceLeft
com.Viscereality.ViscerealityPeriPersonalRight2
com.Viscereality.ViscerealitySphere
com.Viscereality.ViscerealityEggspansion
```

The batch ran both orders for each scenario:

```text
ScenarioThenQuestionnaire
QuestionnaireThenScenario
```

Result:

```text
10 runs
10 pass
0 fail
0 fatal logs
```

Every run exported exactly:

```text
37 MAIA-2 answers
8 MAIA-2 scores
3 pictographic selections
42 slider answers
1 JSON export
1 CSV export
1 draft JSON
1 session-index.jsonl line
```

All ten wrapper runs showed Horizon OS's controller-required launch check. That
is expected for these controller-only immersive APKs and means:

```text
Wrapper route proves: orchestrator routing, target launch request, questionnaire export, data safety.
Wrapper route does not prove: target scenario progressed past the system controller prompt or reached real internal completion.
```

For final experiment execution, pair legacy wrapper links with a short manual
controller gate or rebuild the scenario with a source hook.

## Peripersonal Space Right Status

Closed APK route is verified:

```text
artifacts\quest-orchestrator-wrapper-chain-validation\20260605T035658Z\quest-orchestrator-wrapper-chain-validation-summary.json
```

The installed package/activity are:

```text
com.Viscereality.ViscerealityPeriPersonalSpaceRight/com.unity3d.player.UnityPlayerGameActivity
```

The source-hook Unity project also preflights and compiles:

```text
artifacts\unity-source-hook-preflight\20260605T040009Z\unity-source-hook-preflight.json
artifacts\unity-batchmode-compile\20260605T034953Z\unity-batchmode-summary.json
```

The remaining gap is not the hook mechanism. The remaining gap is locating or
recreating the exact Peripersonal Space Right Unity build profile/source scene
so the source hook can be baked into that specific APK.

## Data Safety Contract

The questionnaire saves locally before returning to any broker or next app.

Exports live on the headset under:

```text
/sdcard/Android/data/org.mesmerprism.viscereality.questionnaires2d/files/QuestionnaireExports
```

Each run gets a unique run id and participant-safe filename:

```text
<runId>_<participantName>_<questionnaireConfigId>.json
<runId>_<participantName>_<questionnaireConfigId>.csv
```

Drafts are updated during the run:

```text
QuestionnaireExports\in_progress
```

Completed runs append to:

```text
QuestionnaireExports\session-index.jsonl
```

The orchestrator receives result metadata, but the questionnaire remains the
owner of the saved data.

## Operational Commands

Build the core APKs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-apk.ps1 -SkipTests
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-orchestrator-apk.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-hook-wrapper-apk.ps1
```

Validate the Unity source-hook project:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\unity-source-hook-preflight.ps1
```

Validate one Peripersonal Space Right wrapper chain:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-orchestrator-wrapper-chain-validate.ps1 `
  -Serial 2G0YC1ZG1002QL `
  -SkipBuild `
  -TargetPackage com.Viscereality.ViscerealityPeriPersonalSpaceRight `
  -TargetActivity com.unity3d.player.UnityPlayerGameActivity `
  -ChainPlanPath .\QuestionnaireConfigs\examples\peripersonal-space-right-then-questionnaire.chain-plan.json
```

Stress test installed Viscereality scenarios in both directions:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-installed-scenario-batch-validate.ps1 `
  -Serial 2G0YC1ZG1002QL `
  -MaxTargets 5 `
  -Order Both `
  -SkipBuild
```

Validate the manual-wrapper gate route:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-wrapper-manual-gate-validate.ps1 `
  -Mode Full `
  -Serial 2G0YC1ZG1002QL `
  -SkipBuild `
  -AutoContinueAfterSeconds 8
```

Use the optional LSL bridge only as a command source into the same broker:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\lsl-chain-bridge.ps1 `
  -Serial 2G0YC1ZG1002QL `
  -InstallDependencies
```
