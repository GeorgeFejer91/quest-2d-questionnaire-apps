# Three Circle Trigger Demo

This is a tiny Unity source demo for the Quest Questionnaire Builder preload
library. It shows three simple scenes:

1. `01_GreenCircle`
2. `02_BlueCircle`
3. `03_RedCircle`

Each scene draws one large colored circle in the foreground Unity app. A click,
tap, Space/Enter key press, or Quest controller trigger/primary/grip press
emits a passive `mq.triggerId`, then advances to the next scene:

```text
green circle -> trigger_1_complete -> blue circle -> trigger_2_complete -> red circle -> trigger_3_complete
```

The participant starts the generated 2D questionnaire APK first. That APK owns
study flow, launches this immersive Unity APK after its configured Block 1, and
decides which questionnaire block each returned trigger resumes. This Unity
demo only displays stimulus content and emits passive trigger ids plus inert
session/timestamp metadata; it does not choose questionnaire type, block order,
scoring, export behavior, or resume policy.

When launched by the questionnaire APK, the demo reads
`mq.triggerReceiverPackage`, `mq.triggerReceiverActivity`, and
`mq.triggerReceiverAction` from its Android launch intent and returns passive
`mq.triggerId` events to that receiver. If the demo is opened directly without
those receiver extras, trigger input is ignored for questionnaire handoff. That
keeps the public demo from depending on any hard-coded questionnaire app or
Unity-side study routing. The bridge allow-lists outgoing passive metadata, so
scene code cannot smuggle questionnaire routing fields through the trigger
payload.

The enabled Android activity is
`org.questquestionnaire.circletriggerdemo.QuestQuestionnaireUnityActivity`, a
thin subclass of Unity's `UnityPlayerGameActivity`. Its only purpose is to call
`setIntent(intent)` in `onNewIntent()`, so a direct Meta Home launch cannot
reuse stale questionnaire receiver extras from an earlier questionnaire-started
session.

## Catalog

The builder-discoverable trigger catalog lives at:

```text
Assets/StreamingAssets/mq/questionnaire-trigger-catalog.json
```

The hosted builder also embeds this same catalog as a preloaded example.

## Build Notes

Open this folder as a Unity project, or run the short-path build helper from
the repo root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File example-scenario-apk\unity-project\three-circle-trigger-demo\build-android-shortpath.ps1
```

The helper mirrors the source project to `C:\qq3demo` before invoking Unity.
That avoids Windows path-length failures in Unity/Gradle generated CMake paths
when this repo lives under a long Documents/GitHub folder. The final APK is
copied back to `Builds\QuestQuestionnaireThreeCircleTriggerDemo.apk`.

The editor setup script registers the three scenes and sets the Android package
id to:

```text
org.questquestionnaire.circletriggerdemo
```

Before building for Quest, use the same Quest/OpenXR settings as other generic
stimulus demos: Android target, ARM64, controller and hand interaction profiles,
and optional hand tracking metadata. Do not commit Unity `Library/`, `Temp/`,
`Logs/`, `UserSettings/`, or built APK outputs.
