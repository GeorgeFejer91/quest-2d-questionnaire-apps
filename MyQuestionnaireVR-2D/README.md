# MyQuestionnaireVR-2D

Native Android 2D panel app for Meta Horizon OS, recreating the questionnaire
workflow from `MyQuestionnaireVR`.

This project intentionally does not use Unity, OpenXR, Meta XR SDK, or a VR
canvas. It launches as a regular 2D panel in Horizon OS / Meta Home and uses
standard Android panel input from controllers, hands, keyboard, mouse, or touch.
It is a 2D panel app, not a full immersive XR app.

## Terminology

Use these terms consistently:

```text
2D panel app
Android 2D app for Meta Horizon OS
2D panel app for Meta Horizon OS
```

Avoid calling this an XR app unless the project later adds spatialized or
immersive features. Compared with a full immersive XR app, this app stays in a
flat, resizable Horizon OS panel and does not take over XR presentation.

## Build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-apk.ps1
```

APK output:

```text
Builds\MyQuestionnaireVR-2D.apk
```

The build wrapper uses Unity 6000.2.7f2's bundled Android SDK, OpenJDK, and
Gradle launcher so Android Studio does not need to be installed for v1.

## Questionnaire Builder

The static config editor is here:

```text
tools\questionnaire-config-editor\index.html
```

Save generated configs under `QuestionnaireConfigs\`. The editor keeps the v1
contract: language selection, demographics, MAIA-2, pictographic selections,
and one custom slider block. It also shows participant-experience counts and
prints the matching APK generator command.

Generate a named APK from any config:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\generate-questionnaire-apk.ps1 `
  -ConfigPath .\QuestionnaireConfigs\examples\custom-presence-check.config.json `
  -RenderPreview
```

Outputs:

```text
Builds\<questionnaireId>-<questionnaireVersion>.apk
artifacts\apk-generator\<run-id>\generator-summary.json
```

The generator validates the config, writes Android assets, validates asset
counts, builds the APK, copies it to the named output, and can create the local
Android render preview in the same run.

Validate the builder itself:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-questionnaire-builder.ps1
```

The builder smoke test also emits a machine-readable quality report when an
output directory is supplied. The report covers language item-count parity,
participant burden, duplicate custom items, long wording, multiple negations,
double-barreled wording, neutral punctuation, and command availability for the
APK/render pipeline.

In the browser UI, use `Download config` for the APK input and `Download quality
report` for the study-design evidence that should travel with that config.

Publish the builder as a distributable static companion app:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\publish-questionnaire-builder.ps1
```

Outputs:

```text
Builds\QuestionnaireBuilder\index.html
Builds\QuestionnaireBuilder.zip
Builds\QuestionnaireBuilder-package-summary.json
```

Prove the browser builder can emit a config that goes directly through APK
generation and Android render validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-web-builder-output-apk.ps1
```

Add `-Serial <quest-serial>` to that command to install the builder-generated
APK on Quest, run English/Deutsch command replay/export, and attach a
foreground-linked Android render pack.

Run the full local ladder from builder smoke test through generated APK and
Android render preview:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-questionnaire-pipeline.ps1 `
  -ConfigPath .\QuestionnaireConfigs\examples\custom-presence-check.config.json `
  -SkipQuest
```

Run the full device-linked ladder when a Quest is connected:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-questionnaire-pipeline.ps1 `
  -ConfigPath .\QuestionnaireConfigs\examples\custom-presence-check.config.json `
  -Serial 2G0YC1ZG1002QL
```

## Android Render Preview

Use the local Android-fidelity renderer for routine visual iteration:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\render-questionnaire-visuals.ps1
```

For a custom questionnaire, pass the same config that will be built into the
APK:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\render-questionnaire-visuals.ps1 `
  -ConfigPath .\QuestionnaireConfigs\examples\custom-presence-check.config.json
```

It renders the shared native Android screen builders at `1280x800` and a narrow
stress size, then writes PNGs and `render-summary.json` under:

```text
artifacts\questionnaire-render-validation\<run-id>
```

To link a render pack to a healthy foreground Quest app after command replay has
already passed, add:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-validate.ps1 `
  -Serial 2G0YC1ZG1002QL `
  -Apk .\Builds\custom-presence-check-0.1.0.apk `
  -SkipBuild `
  -StopLegacyUnityApp `
  -LeaveForeground

powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\render-questionnaire-visuals.ps1 `
  -ConfigPath .\QuestionnaireConfigs\examples\custom-presence-check.config.json `
  -Serial 2G0YC1ZG1002QL `
  -CheckQuestForeground `
  -RequireQuestForeground `
  -LaunchBeforeForegroundCheck
```

The intended visual ladder is:

```text
static -> logic -> local UI -> Android render preview -> APK command replay/export -> foreground check + render pack -> final screenshot only when needed
```

## Quest Validation

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-validate.ps1 `
  -Serial 2G0YC1ZG1002QL `
  -StopLegacyUnityApp `
  -SkipBuild
```

For a generated questionnaire APK:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-validate.ps1 `
  -Serial 2G0YC1ZG1002QL `
  -Apk .\Builds\custom-presence-check-0.1.0.apk `
  -SkipBuild `
  -StopLegacyUnityApp `
  -LeaveForeground
```

## Manual Hardware Gate

Level 6 is a short operator-assisted boundary check for real Quest panel input.
It does not replay the whole questionnaire by hand; it records controller
trigger, hand pinch, visible Back, hardware back, keyboard focus, and
joystick-hover evidence. The script pushes `manual-hardware-gate.txt` into the
app files directory before launch, so the APK opens a validation-only panel
with `Target 1`, `Target 2`, `Keyboard`, visible `Back`, and `Done` controls.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-manual-hardware-gate.ps1 `
  -Serial 2G0YC1ZG1002QL `
  -Apk .\Builds\custom-presence-check-0.1.0.apk `
  -StopLegacyUnityApp
```

The script writes operator instructions, logcat, foreground state, a signoff
template, and `manual-hardware-gate-summary.json` under
`artifacts\manual-hardware-gate\<run-id>`. Add `-RequirePass` only after filling
the operator signoff JSON.

The full pipeline can include this same Level 6 gate when an operator is ready:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-questionnaire-pipeline.ps1 `
  -ConfigPath .\QuestionnaireConfigs\examples\custom-presence-check.config.json `
  -Serial 2G0YC1ZG1002QL `
  -RunManualHardwareGate `
  -OperatorSignoffPath .\artifacts\manual-hardware-gate\<run-id>\operator-signoff.json
```

Exports are written on-device under:

```text
/sdcard/Android/data/org.viscereality.questionnaires2d/files/QuestionnaireExports
```

## APK Chain Broker

For multi-APK experiments, prefer the standalone on-headset orchestrator APK as
the chain owner:

For the closed-APK versus rebuilt-source distinction, see
`docs\existing-apk-hooks.md`.
For the full experiment-chain recipe and current stress-test evidence, see
`docs\experiment-chain-workflow.md`.

```text
package: org.viscereality.orchestrator
activity: org.viscereality.orchestrator.ExperimentOrchestratorActivity
action: org.viscereality.orchestrator.BROKER
```

Build output:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-orchestrator-apk.ps1
```

```text
Builds\ViscerealityExperimentOrchestrator.apk
```

The questionnaire APK also keeps its own compatible broker for small
questionnaire-centered chains and backward compatibility:

```text
package: org.viscereality.questionnaires2d
activity: org.viscereality.questionnaires2d.QuestChainBrokerActivity
action: org.viscereality.questionnaires2d.BROKER
```

Both brokers accept `mq.brokerCommand` values:

```text
startPlan, continuePlan, clearPlan, startQuestionnaire, openApp, goHome, ping
```

The standalone orchestrator stores chain state under:

```text
/sdcard/Android/data/org.viscereality.orchestrator/files/ExperimentOrchestrator
```

The questionnaire-owned broker stores chain state under:

```text
/sdcard/Android/data/org.viscereality.questionnaires2d/files/ChainBroker
```

Recommended flow:

```text
scenario APK hook -> broker continuePlan -> questionnaire -> broker -> next scenario APK hook
```

Every scenario APK should expose a tiny hook Activity or equivalent launch
entry point. The broker can identify that app by package/activity and issue a
hook command using:

```text
intent action: org.viscereality.CHAIN_COMMAND
extra: mq.hookCommand=startScenario
extras: mq.chainId, mq.chainStepId, mq.chainStepIndex
callback extras: mq.brokerAction, mq.brokerPackage, mq.brokerActivity
```

Without a hook, the broker can foreground or launch an app, but it cannot
reliably tell that app which scene, trial, or internal state to enter. With a
hook in each app, the chain plan becomes the source of truth.

For existing APKs where we do not have or do not want to rebuild the Unity
source, build and install the hook-wrapper APK:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-hook-wrapper-apk.ps1
```

Output:

```text
Builds\ViscerealityChainHookWrapper.apk
```

The wrapper advertises the same discoverable hook action:

```text
package: org.viscereality.chainhookwrapper
activity: org.viscereality.chainhookwrapper.ChainHookActivity
action: org.viscereality.CHAIN_COMMAND
```

In a chain plan, target the wrapper and pass the old APK target through extras:

```json
{
  "id": "peripersonal-space-right-wrapper",
  "type": "scenario",
  "package": "org.viscereality.chainhookwrapper",
  "activity": ".ChainHookActivity",
  "action": "org.viscereality.CHAIN_COMMAND",
  "command": "launchTarget",
  "extras": {
    "targetPackage": "com.Viscereality.ViscerealityPeriPersonalSpaceRight",
    "targetActivity": "com.unity3d.player.UnityPlayerGameActivity",
    "mq.autoContinueDelayMs": 10000
  }
}
```

Use `mq.autoContinueDelayMs` only for automated validation or timed segments.
For real experimental logic, a source-level hook inside the Unity APK should
call the broker when the scenario is genuinely finished.

For Viscereality Unity source builds, the source-hook pieces are already staged
in the Unity project:

```text
C:\Users\cogpsy-vrlab\Documents\GithubVR\Viscereality\Viscereality\Assets\Scripts\ExperimentChain\QuestQuestionnaireChainBridge.cs
C:\Users\cogpsy-vrlab\Documents\GithubVR\Viscereality\Viscereality\Assets\Scripts\ExperimentChain\QuestExperimentChainHook.cs
C:\Users\cogpsy-vrlab\Documents\GithubVR\Viscereality\Viscereality\Assets\Plugins\Android\AndroidManifest.xml
```

Those source builds expose the same `org.viscereality.CHAIN_COMMAND`
action directly from the Unity activity. At the semantic end of a scenario, call
this from Unity:

```csharp
QuestExperimentChainHook.ContinueCurrentPlan();
```

The current Viscereality source tree also wires this into `ExperimentRun`: after
`ThankYou()`, it calls `QuestExperimentChainHook.ContinueCurrentPlan(...)` with
`mq.scenarioResultStatus`, `mq.scenarioVersion`, and
`mq.scenarioParticipantDataPath`. A rebuilt Peripersonal-style APK can therefore
advance the chain from real scenario completion instead of a wrapper timeout.

The Unity hook uses the callback broker extras supplied by the incoming chain
intent (`mq.brokerAction`, `mq.brokerPackage`, `mq.brokerActivity`). If the
standalone orchestrator APK owns the plan, the same hook returns there; if no
callback extras are present, it falls back to the questionnaire-owned broker.

Before rebuilding a source-hook Peripersonal-style APK, run the Unity preflight:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\unity-source-hook-preflight.ps1
```

The preflight checks that the Unity project has a real editor version, required
package manifest entries, package source metadata, free disk space, the chain
intent filter, and the hook scripts. The current wrapper route can launch
unchanged APKs, but a source-hook APK should not be treated as verified until
this preflight passes and the Unity project compiles.

For rebuilt source-hook APKs, generate a direct chain plan with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new-wrapper-chain-plan.ps1 `
  -TargetApk "C:\path\to\RebuiltScenario.apk" `
  -ScenarioId peripersonal-space-right `
  -ChainId peripersonal-space-right-source-hook-chain `
  -HookMode Source `
  -Order ScenarioThenQuestionnaire `
  -OutputPath .\QuestionnaireConfigs\examples\peripersonal-space-right-source-hook.local.chain-plan.json
```

Peripersonal Space Right examples:

```text
QuestionnaireConfigs\examples\peripersonal-space-right-then-questionnaire.chain-plan.json
QuestionnaireConfigs\examples\questionnaire-then-peripersonal-space-right.chain-plan.json
```

The checked-in Sussex example targets the compiled APK currently present at
`C:\Users\cogpsy-vrlab\Documents\GithubVR\SussexPolarController.apk`:

```text
QuestionnaireConfigs\examples\sussex-polar-controller-then-questionnaire.chain-plan.json
```

For any compiled scenario APK, first extract its package and launch Activity:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\get-apk-launch-info.ps1 `
  -Apk "C:\path\to\PeripersonalSpaceRight.apk"
```

Then generate a wrapper chain plan without hand-editing JSON:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new-wrapper-chain-plan.ps1 `
  -TargetApk "C:\path\to\PeripersonalSpaceRight.apk" `
  -ScenarioId peripersonal-space-right `
  -ChainId peripersonal-space-right-then-questionnaire `
  -HookMode Wrapper `
  -Order ScenarioThenQuestionnaire `
  -OutputPath .\QuestionnaireConfigs\examples\peripersonal-space-right-then-questionnaire.local.chain-plan.json
```

Then validate the wrapper chain on Quest. For the standalone orchestrator path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-orchestrator-wrapper-chain-validate.ps1 `
  -Serial 2G0YC1ZG1002QL `
  -TargetPackage "com.Viscereality.ViscerealityPeriPersonalSpaceRight" `
  -TargetActivity "com.unity3d.player.UnityPlayerGameActivity" `
  -ChainPlanPath .\QuestionnaireConfigs\examples\peripersonal-space-right-then-questionnaire.chain-plan.json
```

For the questionnaire-owned broker compatibility path:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-wrapper-chain-validate.ps1 `
  -Serial 2G0YC1ZG1002QL `
  -TargetApk "C:\path\to\PeripersonalSpaceRight.apk" `
  -ChainPlanPath .\QuestionnaireConfigs\examples\peripersonal-space-right-then-questionnaire.local.chain-plan.json
```

For stress-testing several installed legacy Viscereality APKs through the
standalone orchestrator and wrapper, run the installed-scenario batch validator:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-installed-scenario-batch-validate.ps1 `
  -Serial 2G0YC1ZG1002QL `
  -MaxTargets 3 `
  -Order Both `
  -SkipBuild
```

This discovers installed `com.Viscereality.*` packages, generates temporary
chain plans, runs scenario -> questionnaire and questionnaire -> scenario
orders, and writes compact evidence under:

```text
artifacts\qbatch\<run-id>\
```

The short `qbatch` path is intentional: questionnaire export filenames include
unique run ids, participant names, and config ids, so deeply nested Windows
paths can become too long for `adb pull`.

In this workspace, the Peripersonal Space Right Unity sidecar folder is present
under `Viscereality\Viscereality\APKs`. The installed headset APK was verified
as package `com.Viscereality.ViscerealityPeriPersonalSpaceRight`, launch
activity `com.unity3d.player.UnityPlayerGameActivity`, and was pulled for
metadata evidence to:

```text
Builds\PeripersonalSpaceRight-device-base.apk
```

No-human validation can show a Horizon OS controller-required launch check for
some controller-only immersive APKs. The validator records this as a warning in
`quest-wrapper-chain-validation-summary.json`,
`quest-orchestrator-wrapper-chain-validation-summary.json`, or
`quest-installed-scenario-batch-validation-summary.json`: it proves the wrapper
issued the target launch and the questionnaire export completed, but a human
controller gate or source-level hook is still needed to prove the target
scenario advanced past that system dialog.

The questionnaire always saves before returning to the broker. Final JSON/CSV
filenames include a unique run id, participant name, and questionnaire id. Draft
JSON is updated during the run under `QuestionnaireExports\in_progress`, and
completed runs append to `QuestionnaireExports\session-index.jsonl`.

Run the broker-chain device validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-broker-chain-validate.ps1 `
  -Serial 2G0YC1ZG1002QL `
  -Apk .\Builds\MyQuestionnaireVR-2D.apk `
  -SkipBuild
```

Run the direct source-hook proof. This installs a tiny scenario stub that
behaves like a rebuilt Viscereality APK with a real hook: the broker starts the
scenario hook directly, the hook calls back through the provided broker extras,
then the questionnaire runs and exports.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-source-hook-stub-apk.ps1

powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-source-hook-chain-validate.ps1 `
  -Serial 2G0YC1ZG1002QL `
  -SkipBuild
```

Evidence from this gate proves the source-hook route without the wrapper:
`SOURCE_HOOK_STUB_RECEIVED`, `SOURCE_HOOK_STUB_BROKER_CONTINUE`, broker
scenario/questionnaire/plan-complete markers, and the exact questionnaire
export counts.

Unity helpers are in:

```text
tools\unity\QuestQuestionnaireChainBridge.cs
tools\unity\README.md
```

## Optional LSL Control

The headset-owned broker remains the orchestrator. LSL is an optional command
source for starting or continuing that broker plan from the lab network.

Install the Python LSL dependency and run the host adapter:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\lsl-chain-bridge.ps1 `
  -Serial 2G0YC1ZG1002QL `
  -InstallDependencies
```

Send an example LSL command:

```powershell
python .\tools\lsl-send-command.py `
  --command-file .\QuestionnaireConfigs\examples\lsl-start-questionnaire.example.json
```

This v1 LSL path is a thin adapter: LSL JSON sample in, Android broker intent
on the Quest out. A future fully native LSL listener inside the headset would
need Android-native `liblsl` packaging and a foreground/background service
design, but the broker contract would stay the same.
