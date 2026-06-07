# Unity Quest Video Validation Lessons

Use this note when building or validating Unity APKs that play packaged video
stimuli on Meta Quest.

## Validate Real Video Playback, Not A Static Texture

Problem: a renderer that only draws a static texture on a curved mesh can pass
even when Unity's `VideoPlayer` cannot prepare, decode, advance frames, or write
to the target `RenderTexture`.

Solution: add app-owned markers around the real pipeline:
`VIDEO_PREPARE_START`, `VIDEO_PREPARED`, `VIDEO_FIRST_FRAME`,
`VIDEO_NONBLACK_FRAME`, `VIDEO_FRAME_ADVANCING`, `VIDEO_LOOP_POINT`, and
`VIDEO_ERROR`. Capture render metrics from the actual `RenderTexture`, and fail
if the frame remains black, hashes never change, or `VideoPlayer.errorReceived`
fires.

## Treat StreamingAssets Copying As Diagnostic

The desired product behavior is a packaged video inside the APK. If direct
`Application.streamingAssetsPath` playback fails on Quest, test a
`PersistentCopy` mode only to diagnose whether Android's APK-internal
`jar:file://...!/assets/...` path is the failure. Do not present the copied
file as a user-facing media dependency.

## Batchmode Editor Gates Can Lie

Unity batchmode edit-time `VideoPlayer.Prepare()` and hand-rolled
`EditorApplication.EnterPlaymode()` loops can time out or fail to enter Play
Mode even with a valid H.264/AAC MP4. Prefer Unity Test Runner for a local
PlayMode render gate, and do not pass `-quit` to `-runTests`. After adding test
assemblies or packages, expect one Unity launch to compile and exit before a
second run can produce test results.

## Wait For The Real Unity Process

On Windows, launching Unity from PowerShell can make the wrapper return before
the editor/build process finishes writing logs. Use a process handle
(`Start-Process -PassThru` plus `WaitForExit`) and inspect Unity's own build
log before trusting a build result.

## Keep Unity Player Builds Minimal

Do not keep `com.unity.feature.development` in a simple Quest stimulus APK. It
can pull Code Coverage and other editor-only packages into player-build
analysis, producing noisy `System.Numerics` messages. Use only the packages
needed for the app and any explicit validation tests.

Generated XR Simulation assets under `Assets/XR/Temp`,
`Assets/XR/UserSimulationSettings`, and
`Assets/XR/Resources/XRSimulationRuntimeSettings.asset` can be created by
failed local PlayMode attempts. Remove or ignore those generated files before
Android builds, because Unity's XR Simulation build processor may otherwise
trip over duplicate move targets.

## Inspect The Merged APK Manifest

After every Unity Quest build, inspect the APK with `aapt dump badging` and
`aapt dump xmltree`. Confirm:

- `android:exported="true"` on launcher activities with intent filters.
- The expected package id, label, and enabled launch activity.
- The video asset exists once under `assets/videos/`.
- No accidental `.dbg` payloads are packaged.
- No accidental requirements such as eye tracking are present in the merged
  manifest for a simple video stimulus.

## Distinguish Quest Launch Gates From Video Failures

The Horizon OS log markers
`RequiresControllersLaunchInterceptor`,
`LaunchCheckControllerRequiredDialogActivity`, or
`common_system_dialog_app_launch_blocked_controller_required` mean Unity did
not start. If these appear before `VIDEO_PREPARE_START`, classify the run as
blocked before Unity rather than as a video playback failure.

ADB screenshots and UIAutomator may return black or no root node for protected
system dialogs. Record logcat and foreground evidence. Waking the headset with
`KEYCODE_WAKEUP` can clear sleep state, but it does not replace a physical
controller/hardware gate when Horizon requires controllers.
