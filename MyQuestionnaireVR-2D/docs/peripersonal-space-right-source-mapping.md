# Peripersonal Space Right Source Mapping

This note records what is known about the installed Peripersonal Space Right APK
versus the local Unity source project.

## Verified Installed APK

The headset-installed APK used in validation is:

```text
com.Viscereality.ViscerealityPeriPersonalSpaceRight/com.unity3d.player.UnityPlayerGameActivity
```

The pulled APK copy is:

```text
Builds\PeripersonalSpaceRight-device-base.apk
```

The validated link mode for this compiled APK is:

```text
orchestrator -> chain wrapper -> Peripersonal Space Right -> manual/controller continue -> questionnaire 2D panel
```

## Local Unity Source Findings

The inspected Unity project is:

```text
C:\Users\cogpsy-vrlab\Documents\GithubVR\Viscereality\Viscereality
```

It has relevant peripersonal-looking scene/config candidates:

```text
Assets\Scenes\Pre Sussex\Space.unity
Assets\Scenes\Pre Sussex\SussexRadius.unity
Assets\Scenes\Pre Sussex\SussexSimpleOrbit.unity
Assets\Configs\Space.asset
Assets\Configs\PE_DirectConfig.asset
Assets\Configs\PE_SimpleLinearConfig.asset
Assets\Configs\PESussexSimpleConfig.asset
Assets\Configs\PE_AdvancedConfig.asset
```

Its Android manifest now exposes the source-hook action:

```text
org.mesmerprism.viscereality.CHAIN_COMMAND
```

The source-hook scripts are staged under:

```text
Assets\Scripts\ExperimentChain
```

`ExperimentRun.cs` already contains a real semantic chain continuation point:

```text
ExperimentRun.NotifyExperimentChainComplete()
  -> QuestExperimentChainHook.ContinueCurrentPlan(resultExtras)
```

That path sends:

```text
mq.scenarioResultStatus=complete
mq.scenarioVersion=<distribution version>
mq.scenarioParticipantDataPath=<local participant data path>
```

The hook also accepts validation-only auto-continue extras:

```text
mq.autoContinueDelayMs
mq.sourceAutoContinueDelayMs
```

Use those only for smoke tests. Production source-hook builds should continue
from the real scenario end event.

## Missing Exact Match

The current build profiles do not match the installed Peripersonal Space Right
package.

```text
Assets\Settings\Build Profiles\Meta Quest.asset
  package: com.Viscereality.ViscerealityAirres
  enabled scene: Assets/Scenes/Ballpit.unity

Assets\Settings\Build Profiles\Coupling.asset
  package: com.Viscereality.ViscerealityMergedEggspansionSphereMax
  enabled scene: Assets/Scenes/Coupling.unity
```

The project-level `EditorBuildSettings.asset` currently has an empty global
scene list. The local `APKs` sidecar folder exists but did not contain a source
build profile or APK file during this audit.

The current source-candidate audit found:

```text
status: source-hook-ready-exact-build-profile-missing
matching Peripersonal build profiles: 0
scenes with ExperimentRun: Assets\Scenes\Main Questionnaire.unity
best Peripersonal-looking scene: Assets\Scenes\Pre Sussex\Space.unity
```

So the source hook is implemented, but the exact Peripersonal Space Right
source/build mapping is still not proven.

Run the audit again with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\audit-unity-source-hook-candidates.ps1
```

## Source-Hook Candidate Build Path

A batchmode Unity build entrypoint is available in the source project:

```text
Assets\Editor\ExperimentChain\QuestSourceHookBuild.cs
```

The host wrapper is:

```text
tools\build-unity-source-hook-apk.ps1
```

Dry-run the build command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-unity-source-hook-apk.ps1 `
  -DryRun `
  -SkipPreflight `
  -SkipCandidateAudit
```

Build a candidate source-hook APK from the currently hooked experiment scene:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-unity-source-hook-apk.ps1 `
  -ScenePath "Assets\Scenes\Main Questionnaire.unity" `
  -PackageId "com.Viscereality.ViscerealityPeriPersonalSpaceRight.SourceHook" `
  -ProductName "Viscereality Peripersonal Source Hook Candidate"
```

For smoke validation, use:

```text
QuestionnaireConfigs\examples\peripersonal-source-hook-candidate-smoke.chain-plan.json
```

That plan uses `mq.sourceAutoContinueDelayMs` so the source hook can prove the
orchestrator handoff without waiting through a full experiment. For real
experiments, remove the auto-continue extra and rely on
`NotifyExperimentChainComplete()`.

## Practical Decision

For the already-built APK, use the closed-APK wrapper/manual-gate route. It is
validated and packaged in:

```text
Builds\ExperimentChainKit.zip
```

For a fully automatic semantic chain, create or recover a Unity build profile
for:

```text
package: com.Viscereality.ViscerealityPeriPersonalSpaceRight
scene: likely one of the Pre Sussex peripersonal scenes, to be confirmed
```

Then connect the real scenario completion event to:

```text
QuestExperimentChainHook.ContinueCurrentPlan()
```

That source rebuild would replace the operator/controller continue gate with an
internal completion signal.
