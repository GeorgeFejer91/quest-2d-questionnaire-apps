# APK Drop Folder

This folder holds the installable APKs requested for the Quest 2D questionnaire
work.

## Contents

| APK | Purpose | SHA-256 |
| --- | --- | --- |
| `demographic-questionnaire/MyQuestionnaireVR-2D.apk` | Demographic / MAIA-2 / pictographic questionnaire 2D panel app | `B35ADB7E61B1536D334E31254FE5900D901410509484996124ED2A91B6B54F60` |
| `temporal-experience-tracer/TemporalExperienceTracerVR-2D.apk` | Temporal experience tracer 2D panel app | `905F163894522F91879E6626CB310379CA5302194FADA539FF62EBCB245FC41A` |

## Install

```powershell
adb -s <serial> install -r -d .\apks\demographic-questionnaire\MyQuestionnaireVR-2D.apk
adb -s <serial> install -r -d .\apks\temporal-experience-tracer\TemporalExperienceTracerVR-2D.apk
```

Use `-g` only for apps that declare runtime permissions. These questionnaire
apps are ordinary 2D panel apps and should be validated through foreground
launch, command replay, export pull, and a short human input gate when used in a
real session.
