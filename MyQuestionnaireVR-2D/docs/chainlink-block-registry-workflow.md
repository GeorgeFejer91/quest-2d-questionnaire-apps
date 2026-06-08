# ChainLink Block Registry Workflow

ChainLink is the on-headset APK switchboard for registered experiment blocks.
The web builder now emits:

- `experimentBlockRegistry`: numbered blocks embedded in the questionnaire config.
- `*.block-registry.json`: the same registry as a standalone artifact.
- `*.chain-plan.json`: an executable ChainLink plan built from the registry.

## Any-APK Workflow

ChainLink does not require a Peripersonal-specific target. Any launchable APK can
be registered as a target block when you know its Android package and launch
activity.

Generate a plan from an APK file:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\new-chainlink-plan.ps1 `
  -TargetApk .\Builds\MyScenario.apk `
  -TargetLabel "My Scenario" `
  -PictographicRepeats 3 `
  -OutputPath .\QuestionnaireConfigs\examples\my-scenario.chain-plan.json
```

Or generate a plan when the APK is already installed / you already know the
component:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\new-chainlink-plan.ps1 `
  -TargetPackage com.example.scenario `
  -TargetActivity com.unity3d.player.UnityPlayerGameActivity `
  -TargetLabel "Example Scenario" `
  -PictographicRepeats 3
```

The generator writes `questquestionnaire.chainlink.plan.v1` with numbered registered
blocks. ChainLink executes those blocks by reading `package`, `activity`,
`action`, and `extras`; it does not special-case the package name.

## Example Peripersonal Workflow

The default builder settings produce:

1. `001_baseline_questionnaire`: language, demographics, and MAIA-2 only.
2. `002_target_apk_start`: launch or resume the registered target APK.
3. `003_pictographic_01`: controller-triggered pictographic questionnaire block.
4. `004_resume_target_apk_01`: resume the target APK.
5. `005_pictographic_02`: second controller-triggered pictographic block.
6. `006_resume_target_apk_02`: resume the target APK.

Increase `Pictographic repeats` in the builder to add more registered
pictographic/resume pairs.

## How ChainLink Starts Other APKs

ChainLink starts target APKs through Android intents.

Preferred deterministic route:

```text
package = <target-package>
activity = <target-launch-activity>
flags = FLAG_ACTIVITY_REORDER_TO_FRONT | FLAG_ACTIVITY_SINGLE_TOP
```

Fallback route:

```text
PackageManager.getLaunchIntentForPackage(package)
```

Hook route for source-controlled apps:

```text
action = org.questquestionnaire.CHAIN_COMMAND
extras:
  mq.command = nextBlock
  mq.chainId = ...
  mq.blockNumber = ...
```

## Controller Trigger Boundary

Android only delivers the controller button event to the focused foreground
app/panel. That means:

- ChainLink can respond to controller button events while the ChainLink panel
  has focus.
- The 2D questionnaire can respond while the questionnaire panel has focus.
- The foreground immersive APK must contain a small hook if a controller button
  should call ChainLink while the immersive scenario is foreground.
- For Peripersonal Space source builds, use
  `auto-unused-non-breath-tracking` as the generated-plan default. The source
  hook then auto-selects an unused button and prefers the controller not used
  by `ControllerPoseProxy` for breath tracking when that controller has a free
  button.

The hook should call:

```text
action = org.questquestionnaire.chainlink.COMMAND
package = org.questquestionnaire.chainlink
activity = org.questquestionnaire.chainlink.ChainLinkActivity
extra mq.command = nextBlock
```

For closed APKs without source hooks, ChainLink can launch/resume any launchable
APK, but it cannot receive that APK's internal controller events while the APK
owns focus. Use a source rebuild, wrapper/manual gate, ADB validation command,
or LSL bridge as the event source.

## Unity Foreground Hook

For Unity APKs you can rebuild, copy the Unity package from:

```text
tools\unity\
```

Use:

- `QuestQuestionnaireChainBridge.cs` for Android intent calls.
- `ChainLinkControllerHook.cs` for a drop-in left-controller trigger component.

Attach `ChainLinkControllerHook` to a GameObject in the foreground scene. When
the configured left-controller button is pressed, it sends:

```text
action = org.questquestionnaire.chainlink.COMMAND
component = org.questquestionnaire.chainlink/.ChainLinkActivity
mq.command = nextBlock
mq.triggerSource = unity-left-controller
mq.triggerTimestampUtc = <UTC ISO-8601 timestamp>
mq.triggerTimestampUnixMs = <milliseconds since epoch>
```

For source-hooked Peripersonal builds, prefer the built-in
`QuestExperimentChainHook` bootstrap. It reads `mq.controllerButton` from the
ChainLink plan, accepts values like `left-controller-secondary`,
`right-controller-grip`, `Y`, or `B`, and otherwise auto-selects an unused
scene button. Use `auto-unused-non-breath-tracking` to force runtime
auto-selection.

Use this capability label in experiment records:

```text
foregroundHooked = controller press comes from the active Unity APK
launchOnly = ChainLink can launch/resume the APK, but needs another event source
```

## Data Contract

Every questionnaire invocation gets a unique run id and append-only files under:

```text
/sdcard/Android/data/org.questquestionnaire.questionnaires2d/files/QuestionnaireExports
```

Each export includes:

- `questionnaireMode`: `baseline`, `pictographic`, or `full`
- `blockNumber`, `blockId`, `saveNamespace`
- per-answer `responseTimestampUtc`
- per-answer `responseTimestampUnixMs`
- normal numeric response values, such as MAIA-2 `0..5` scores and pictographic choices

Baseline and every repeated pictographic block are separate files. Filenames
include the run id and save namespace, so repeated calls never overwrite
earlier responses.

## Build Commands

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-apk.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-chainlink-apk.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\new-chainlink-plan.ps1 -TargetApk .\Builds\MyScenario.apk
```

Outputs:

```text
Builds\MyQuestionnaireVR-2D.apk
Builds\QuestQuestionnaireChainLink.apk
```

## ChainLink Stress Harness

Use the direct ChainLink stress script to validate numbered blocks and simulated
foreground-hook commands.

Consolidated local setup validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\validate-experiment-setup.ps1 `
  -SkipPublish
```

The expected status without a connected Quest is `host-ready-device-pending`.
When ADB is online, add `-Serial <quest-serial> -RunLiveDeviceBatch` to include
the live device stress step.

Before any live headset run, capture ADB readiness:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\quest-adb-readiness.ps1 `
  -RestartServer `
  -WaitSeconds 30 `
  -RequireOnline
```

Batch dry run across every launchable non-core APK in `Builds`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\stress-chainlink-scenario-batch.ps1 `
  -DryRun `
  -PictographicRepeats 2
```

Dry run without a headset:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\quest-chainlink-plan-validate.ps1 `
  -DryRun `
  -TargetApk .\Builds\PeripersonalSpaceRight-device-base.apk `
  -PictographicRepeats 2
```

Device run once the Quest is visible to ADB:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\quest-chainlink-plan-validate.ps1 `
  -Serial <quest-serial> `
  -TargetApk .\Builds\PeripersonalSpaceRight-device-base.apk `
  -PictographicRepeats 2 `
  -SkipBuild
```

The script installs ChainLink and the questionnaire, starts the generated plan,
lets baseline/questionnaire blocks auto-complete, sends timestamped
`mq.command=nextBlock` intents as a Unity hook stand-in, pulls device evidence,
and checks that baseline and repeated pictographic exports are unique,
timestamped, and append-only.
