# Three Circle Trigger Demo

This is a tiny Unity source demo for the Quest Questionnaire Builder preload
library. It shows three simple scenes:

1. `01_GreenCircle`
2. `02_BlueCircle`
3. `03_RedCircle`

Each scene draws one large colored circle. A click, tap, Space/Enter key press,
or Quest controller trigger/primary/grip press emits a passive
`mq.triggerId`, then advances to the next scene:

```text
green circle -> trigger_1_complete -> blue circle -> trigger_2_complete -> red circle -> trigger_3_complete
```

The generated 2D questionnaire APK decides which questionnaire block each
trigger resumes. This Unity demo only displays stimulus content and emits
passive trigger ids.

## Catalog

The builder-discoverable trigger catalog lives at:

```text
Assets/StreamingAssets/mq/questionnaire-trigger-catalog.json
```

The hosted builder also embeds this same catalog as a preloaded example.

## Build Notes

Open this folder as a Unity project. The editor setup script registers the
three scenes and sets the Android package id to:

```text
org.questquestionnaire.circletriggerdemo
```

Before building for Quest, use the same Quest/OpenXR settings as other generic
stimulus demos: Android target, ARM64, controller and hand interaction profiles,
and optional hand tracking metadata. Do not commit Unity `Library/`, `Temp/`,
`Logs/`, `UserSettings/`, or built APK outputs.
