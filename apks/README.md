# APK Drop Folder

This folder holds the installable APKs requested for the Quest 2D questionnaire
work.

## Contents

| APK | Purpose | SHA-256 |
| --- | --- | --- |
| `demographic-questionnaire/MyQuestionnaireVR-2D.apk` | Demographic / MAIA-2 / pictographic questionnaire 2D panel app | `1605FBC579713A553B014500BE71E0AE43E0556AEB4C22B66A2D6142F30529A7` |
| `sam-questionnaire/SAMQuestionnaireVR-2D.apk` | Five-item SAM valence/arousal plus Affective Slider 2D panel app | `D8110A8BED6670D3EE177E64A991C1A130757556088DFCE22B987B7F9BBDC704` |
| `temporal-experience-tracer/TemporalExperienceTracerVR-2D.apk` | Temporal experience tracer 2D panel app | `4A0A2CC1754F536861285BD105669ACE16E97AFCF3A7274EE696FD5C67FD041C` |

## Install

```powershell
adb -s <serial> install -r -d .\apks\demographic-questionnaire\MyQuestionnaireVR-2D.apk
adb -s <serial> install -r -d .\apks\sam-questionnaire\SAMQuestionnaireVR-2D.apk
adb -s <serial> install -r -d .\apks\temporal-experience-tracer\TemporalExperienceTracerVR-2D.apk
```

Use `-g` only for apps that declare runtime permissions. These questionnaire
apps are ordinary 2D panel apps and should be validated through foreground
launch, command replay, export pull, and a short human input gate when used in a
real session.
