# MyQuestionnaireVR-2D

Native Android 2D panel app for Meta Horizon OS, recreating the questionnaire
workflow from `MyQuestionnaireVR`.

This project intentionally does not use Unity, OpenXR, Meta XR SDK, or a VR
canvas. It launches as a regular 2D panel in Horizon OS / Meta Home and uses
standard Android panel input from controllers, hands, keyboard, mouse, or touch.
It is a 2D panel app, not a full immersive XR app.

## AI Agent Notes

Before making code changes, AI agents should read
[../For-AI/START_HERE.md](../For-AI/START_HERE.md). That root folder records
evolving project constraints, including the requirement that the offline desktop
GUI and online connector GUI stay functionally identical except for the pairing
mechanism to the local companion program. For app-specific notes, also read
[For-AI/README.md](For-AI/README.md).

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

For the offline desktop app workflow, double-click this file from Windows
Explorer:

```text
Start-QuestionnaireBuilderApp.cmd
```

Or start the local app backend explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\start-questionnaire-builder-app.ps1
```

The launcher opens the questionnaire builder HTML at `http://127.0.0.1:8765/`.
All user input stays in the browser UI. The local backend saves configs under
`QuestionnaireConfigs\generated\`, runs the PowerShell validator, and can run
APK generation from the `Windows App Runner` panel.

For the online connector workflow, start the local companion first:

```text
Start-QuestionnaireBuilderOnlineConnector.cmd
```

That opens the hosted static builder page and prints a local pairing token. In
the page's `Windows App Runner` panel, keep the connector URL as
`http://127.0.0.1:8765`, enter the pairing token, then use the same controls as
offline mode. The online page is only a static GUI. File access, dependency
checks, config validation, APK generation, and render previews are performed by
the local companion running on the user's PC.

The offline and online GUI paths should stay functionally identical except for
the online pairing step. Do not add features to one path without keeping the
other path aligned.

The static config editor can still be opened directly when backend actions are
not needed:

```text
tools\questionnaire-config-editor\index.html
```

The editor keeps the v1 contract: language selection, demographics, MAIA-2,
pictographic selections, and one custom slider block. It also scans Unity APK
trigger catalogs, maps trigger event IDs to questionnaire blocks, shows
participant-experience counts, and prints the matching APK generator command.
The builder UI is APK-first: downstream block-building, questionnaire editing,
validation, local dependency, export, and APK-generation controls remain
disabled until an existing scenario APK, trigger catalog JSON, or the repository
example APK catalog is loaded. The public example folder lives at
`../example-scenario-apk/`; place the finished example APK under
`../example-scenario-apk/apk/` and the matching Unity project or build folder
under `../example-scenario-apk/unity-project/`.

For a demographics-before-stimulus participant run, make the questionnaire APK
the front door. Load the Unity trigger catalog and use `Use 2D-first launcher
defaults` in `Experiment handoff`. The generated config packages a
normal-launch default that runs demographics, saves the first block, and opens
the configured Unity APK through `finishBehavior=openNext`. That generated APK
is effectively pinned to the chosen Unity package/activity, while the reusable
Android source stays builder/config driven. Later Unity-triggered blocks still
return to Unity with `resumeCaller`; this does not replace the Unity
input-modality requirement that generic stimulus APKs support both hands and
controllers.

The repository includes a small 2D-first demo config that can run the full
offline APK/render/preflight spine without relying on generated smoke-test
artifacts:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-builder-to-quest-workflow.ps1 `
  -ConfigPath .\QuestionnaireConfigs\examples\awe-great-dictator-2d-first-demo.config.json `
  -RunQuestDirectHandoff `
  -DryRunQuestDirectHandoff `
  -SkipInstall
```

After that APK exists, preflight the participant-facing 2D-first front door
without touching the headset:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-2d-first-launcher-validate.ps1 `
  -DryRun
```

When an awake/worn headset is available, run the live front-door gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-2d-first-launcher-validate.ps1 `
  -Serial <quest-serial> `
  -WaitForReadySeconds 30
```

The live validator launches the questionnaire APK first, command-replays the
demographics block, verifies the questionnaire export and `openNext` handoff,
and observes Unity focus. After the initial questionnaire launch, it does not
use ADB to foreground Unity.
The builder runner exposes the same gate as `Run 2D-first launch`; with
`Preflight only` checked it dry-runs the packaged 2D-first contract, and with
that toggle cleared it performs the live participant-front-door Quest trial.

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

Stage the same HTML GUI into a local GitHub Pages checkout:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\publish-questionnaire-builder-github-pages.ps1
```

By default this writes `questionnaire-builder\index.html` into the parent
`quest-2d-questionnaire-apps` repository when this project is nested there.
Commit and push that folder from the Pages repository to publish the hosted GUI
at:

```text
https://georgefejer91.github.io/quest-2d-questionnaire-apps/questionnaire-builder/
```

After pushing a hosted GUI change, prove that the source GUI, staged Pages copy,
and live GitHub Pages URL still match and expose the runner controls:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-hosted-questionnaire-builder.ps1
```

Prove the browser builder can emit a config that goes directly through APK
generation and Android render validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-web-builder-output-apk.ps1
```

Add `-Serial <quest-serial>` to that command to install the builder-generated
APK on Quest, run English/Deutsch command replay/export, and attach a
foreground-linked Android render pack.

Prove the hosted/offline GUI's publication and local companion API path itself.
This checks source/staged/live GitHub Pages parity, starts the companion,
checks pairing-token enforcement, saves and validates the generated handoff
config through HTTP, and drives `/api/generate-apk` so the PC software creates
the APK and local render evidence. It also proves
`/api/artifact-preview` can return token-protected sample render PNGs from both
the APK-generation receipt and the full workflow receipt for GUI inspection.
It proves `/api/evidence-bundle` can package the workflow summary, nested JSON
receipts/logs, and render PNG evidence into a token-protected zip for review.
It calls `/api/quest-readiness` for a read-only ADB device check with separate
product-path readiness, dry-runs `/api/install-apk` so the install job contract
is covered without changing the headset, dry-runs `/api/quest-replay` so
replay/export orchestration is covered without launching the app, dry-runs
`/api/direct-handoff` with the real questionnaire, tracer, and Unity APKs so
direct PendingIntent package/catalog preflight is covered without launching
the headset, then calls `/api/validate-workflow` and polls `/api/workflow-job`
so the companion proves the same builder-to-Quest evidence matrix that the
GUI's `Validate workflow` button runs without blocking the browser:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-builder-companion-workflow.ps1
```

Use `-SkipApkBuild` only for faster diagnostics when APK assembly has already
been covered by another gate.

Summarize the full Universal Quest Handoff evidence state from the current
artifact receipts:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\audit-universal-handoff-readiness.ps1
```

The audit reports which original workflow requirements are proven, which
artifact proves each one, and which physical gates still prevent completion.
It includes the hosted GUI, local companion contract, demo Unity APK/catalog,
generated questionnaire APK, 2D-first launcher APK/render/preflight evidence,
evidence bundle, direct PendingIntent preflight, and real Quest handoff
evidence.
Use `-RequireComplete` only when the live 2D-first launcher trial, 10 clean
real Quest direct-handoff trials, and manual headset pass are expected to be
present; otherwise a
`pass-with-physical-pending` status is the correct overnight state.

Create the structured manual headset signoff artifact after a supervised
product-path run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new-direct-handoff-manual-signoff.ps1
```

The script writes operator instructions and an
`operator-signoff-template.json` under
`artifacts\direct-handoff-manual-signoff\<run-id>`. After the operator has
filled and saved that template as `operator-signoff.json`, validate it with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new-direct-handoff-manual-signoff.ps1 `
  -OperatorSignoffPath .\artifacts\direct-handoff-manual-signoff\<run-id>\operator-signoff.json `
  -RequirePass
```

`audit-universal-handoff-readiness.ps1` consumes the resulting
`direct-handoff-manual-signoff-summary.json`; a loose verbal signoff is not
enough to close the manual headset gate.

Run the full builder-to-Quest evidence spine for a saved GUI config:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-builder-to-quest-workflow.ps1 `
  -ConfigPath .\QuestionnaireConfigs\generated\viscereality-maia2.config.json `
  -RunQuestReadiness `
  -Serial <quest-serial>
```

This validates the config, generates or locates the questionnaire APK, creates
local questionnaire and tracer render evidence, checks the Unity
`mq.returnPendingIntent` bridge contract, dry-runs APK package/activity/catalog
preflight, records Quest ADB versus product-path readiness, and records which
Quest gates remain pending or blocked. The workflow and companion validators
snapshot and restore packaged questionnaire assets they temporarily refresh for
APK-generation checks, so successful stress runs should not leave tracked
Android asset files dirty.

In the builder runner, `Run direct handoff` defaults to `Preflight only`. That
mode sends `dryRun=true` and `skipInstall=true` to `/api/direct-handoff`, uses
the real questionnaire, temporal tracer, and Unity APK package/catalog
contract, and does not launch the headset. The same toggle also makes
`Validate workflow` include the aggregate direct handoff dry-run matrix row
without performing installation or launch side effects; it does not require a
Quest serial. Clear `Preflight only`, then use `Ready wait (s)` before
`Run direct handoff` or `Validate workflow` when collecting supervised or
unattended Quest evidence. The value is bounded to 0-28800 seconds and does
not bypass product-path readiness: if the headset stays asleep or Horizon
keeps the launch-check dialog focused, the run remains `blocked` with
readiness samples instead of launching Unity. If the headset or display falls
asleep after the product path has already begun, the direct handoff validator
now records a blocked product-path evidence window instead of treating missing
markers as a direct handoff failure when no fatal app logs are present.
For unattended development attempts, `Wake before readiness` can be enabled
after clearing `Preflight only`; the companion passes this to the direct
handoff validator as `-WakeBeforeReadiness`, records it in the summary and job
receipt, and still leaves the usual readiness and product-path gates in force.
Do not treat that wake event as a replacement for the required manual headset
pass.

One live Quest direct-handoff pass was captured on 2026-06-07 in
`artifacts\quest-direct-handoff\20260607T111059Z`: the questionnaire returned
to Unity, Unity resumed video and logged non-black frames, the video-complete
trigger launched Temporal Tracer, the tracer exported SVG/CSV/JSON evidence,
and Unity received the final completion callback. This proves one product-path
trial only; the decision gate still requires 10 clean trials plus a manual
headset pass before direct PendingIntent is approved as the default production
strategy. Direct handoff trial summaries now include `mediaLiveness` and
`failureReasons` so a returned-but-frozen Unity video is reported explicitly as
missing playback/frame evidence after panel completion, not just as a generic
handoff failure.

For source Unity stimulus APKs, prefer a foreground `Start experiment` gate
before trigger 1. The demo Unity app waits for participant/operator input in
Unity, launches the first questionnaire only after that input, and starts the
video only after the matching questionnaire result returns. The direct handoff
validator passes `mq.validationAutoStart=true` so unattended validation runs
can bypass this human gate with an auditable `AWE_START_GATE_AUTO_START`
marker; manual headset passes should launch the app normally and click the
start target.

For demo/stimulus Unity APKs, keep input modality broad by default: enable
Quest controller interaction profiles and hand interaction profiles together,
and declare optional Quest hand tracking in the manifest. A Horizon
controller-required launch dialog should be treated as a preflight issue for
these generic workflow APKs unless the experiment deliberately requires
controller-only input.

Use `Run headset sequence` in the builder runner for the ordered GUI path:
save config, validate config, generate the APK with unit tests and a local
render preview, detect Quest readiness, install the generated APK, run
replay/export, run the 2D-first launcher gate, and then run direct handoff
preflight or live trials according to the existing `Preflight only` and
optional `Wake before readiness` toggles. This button reuses the same
companion endpoints as the individual controls; it is an orchestration
convenience, not a different validation path.
Use `Audit readiness` after a sequence or stress run to ask the companion for
the Universal Handoff requirement matrix. It reports proven offline gates,
remaining physical headset gates, and an auditable summary path that can be
included in an evidence bundle.
Use `Prepare manual signoff` to keep the final headset observation gate inside
the same GUI workflow. With no operator JSON path it asks the local companion
to write headset instructions and `operator-signoff-template.json` under
`artifacts\direct-handoff-manual-signoff\`. After a supervised product-path
run, fill that template as `operator-signoff.json`, enter that path in the
runner, and click the same button to validate it. A prepared template is still
pending evidence; only a filled signoff tied to a real non-dry-run direct
handoff summary can close the manual gate.
Use `Prepare physical packet` when offline evidence is ready but headset gates
remain. It runs or consumes the readiness audit, prepares a manual signoff
template, and writes a runbook plus
`universal-handoff-physical-gate-packet-summary.json` under
`artifacts\universal-handoff-physical-gate-packet\`. The packet is not a live
Quest pass; it is the operator handoff for the 2D-first front-door trial, 10
clean direct handoff trials, manual signoff, and final completion audit. If an
audit or physical packet receipt is already visible in the runner, the button
uses that visible audit summary path for the packet.

Run the full local ladder from builder smoke test through generated APK and
Android render preview:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-questionnaire-pipeline.ps1 `
  -ConfigPath .\QuestionnaireConfigs\examples\custom-presence-check.config.json `
  -SkipQuest
```

Run the universal Quest handoff local stress ladder for the Chaplin/Awe demo
contract. This validates builder trigger mapping, generated handoff config,
questionnaire local render, temporal tracer assets, and temporal tracer local
render without requiring a headset:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-universal-handoff-workflow.ps1 `
  -SkipApkBuild `
  -SkipUnity
```

Add `-RunQuest -Serial <quest-serial>` only when a headset is attached and you
are ready to collect the direct PendingIntent handoff evidence described in
`..\examples\session-recipe.xr-questionnaire-panel-handoff.json`.

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
/sdcard/Android/data/org.mesmerprism.viscereality.questionnaires2d/files/QuestionnaireExports
```

## APK Chain Broker

For multi-APK experiments, prefer the standalone on-headset orchestrator APK as
the chain owner:

For the closed-APK versus rebuilt-source distinction, see
`docs\existing-apk-hooks.md`.
For the full experiment-chain recipe and current stress-test evidence, see
`docs\experiment-chain-workflow.md`.

```text
package: org.mesmerprism.viscereality.orchestrator
activity: org.mesmerprism.viscereality.orchestrator.ExperimentOrchestratorActivity
action: org.mesmerprism.viscereality.orchestrator.BROKER
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
package: org.mesmerprism.viscereality.questionnaires2d
activity: org.mesmerprism.viscereality.questionnaires2d.QuestChainBrokerActivity
action: org.mesmerprism.viscereality.questionnaires2d.BROKER
```

Both brokers accept `mq.brokerCommand` values:

```text
startPlan, continuePlan, clearPlan, startQuestionnaire, openApp, goHome, ping
```

The standalone orchestrator stores chain state under:

```text
/sdcard/Android/data/org.mesmerprism.viscereality.orchestrator/files/ExperimentOrchestrator
```

The questionnaire-owned broker stores chain state under:

```text
/sdcard/Android/data/org.mesmerprism.viscereality.questionnaires2d/files/ChainBroker
```

Recommended flow:

```text
scenario APK hook -> broker continuePlan -> questionnaire -> broker -> next scenario APK hook
```

Every scenario APK should expose a tiny hook Activity or equivalent launch
entry point. The broker can identify that app by package/activity and issue a
hook command using:

```text
intent action: org.mesmerprism.viscereality.CHAIN_COMMAND
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
package: org.mesmerprism.viscereality.chainhookwrapper
activity: org.mesmerprism.viscereality.chainhookwrapper.ChainHookActivity
action: org.mesmerprism.viscereality.CHAIN_COMMAND
```

In a chain plan, target the wrapper and pass the old APK target through extras:

```json
{
  "id": "peripersonal-space-right-wrapper",
  "type": "scenario",
  "package": "org.mesmerprism.viscereality.chainhookwrapper",
  "activity": ".ChainHookActivity",
  "action": "org.mesmerprism.viscereality.CHAIN_COMMAND",
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

Those source builds expose the same `org.mesmerprism.viscereality.CHAIN_COMMAND`
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
For direct `mq.returnPendingIntent` handoffs, the reusable
`tools\unity\QuestQuestionnaireChainBridge.cs` now creates trigger/block-aware
return tokens and exposes `ClearQuestionnaireResult()`. Call that method after
handling the expected `mq.resultStatus=complete` and `mq.triggerId` so a later
Unity focus callback cannot replay stale result extras and leave media or
experiment progression stuck.

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
some controller-only immersive APKs. For generic demo/stimulus APKs, fix the
Unity input modality first so the APK supports hands and controllers. Only
controller-only experiment APKs should keep this dialog as an expected human
hardware gate. The validator records this as a warning in
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
