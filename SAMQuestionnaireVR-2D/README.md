# SAMQuestionnaireVR-2D

Native Android 2D panel app for Meta Horizon OS / Quest that collects valence
and arousal for the previous session using two related instruments:

- Self-Assessment Manikin (SAM), five manikin choices per valence/arousal row.
- Affective Slider-style continuous valence and arousal sliders, exported on a
  0-100 scale.

Participant-facing prompts ask the participant to rate how they felt during the
previous session.

This is a standalone panel APK. It does not use Unity, OpenXR, or a VR canvas.

## App Contract

- Package: `org.questquestionnaire.sam2d`
- Activity: `.MainActivity`
- Intent action: `org.questquestionnaire.sam2d.RUN`
- Debug APK output: `Builds\SAMQuestionnaireVR-2D.apk`
- Device exports:
  `/sdcard/Android/data/org.questquestionnaire.sam2d/files/SamQuestionnaireExports`

Launch extras follow the shared Quest questionnaire style:

```text
mq.sessionId
mq.invocationId
mq.participantId
mq.participantName
mq.language
mq.experimentId
mq.scenarioId
mq.trialId
mq.triggerId
mq.blockId
mq.blockNumber
mq.finishBehavior
mq.callerPackage
mq.callerActivity
mq.nextPackage
mq.nextActivity
mq.returnPendingIntent
```

Command replay validation accepts:

```text
mq.autoSam=true
mq.autoSamValence=<1..5>
mq.autoSamArousal=<1..5>
mq.capturePanel=true
mq.capturePanelStage=all|sam|affective-slider|saved
```

Quest validation uses a validation-only broadcast receiver:

```text
org.questquestionnaire.sam2d.SELF_VALIDATE
```

The receiver renders the SAM and Affective Slider screens with the app's
Android views/assets into PNG files, self-validates PNG dimensions/nonblank
pixels, logs `SAM_PANEL_CAPTURE_PASS`, then exports the normal JSON/CSV result.
This avoids depending on Quest compositor screenshots when Guardian, lock, or
camera overlays own the hardware display.

## Assets

SAM SVGs are sourced from:

```text
https://github.com/hexa-/SAM-vectors
```

The copied source marks the vectors as `CC0-1.0`. The app keeps the individual
source SVGs and generated, self-contained row-grid SVGs under:

```text
app\src\main\assets\sam
```

Regenerate them with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\sync-sam-assets.ps1
```

## Build And Validate

Validate assets:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-sam-assets.ps1
```

Run unit tests:

```powershell
.\gradlew.bat --no-daemon :app:testDebugUnitTest
```

Render local Android previews:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\render-sam-visuals.ps1
```

Build the APK:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-apk.ps1
```

Run Quest command replay/export validation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\quest-validate.ps1 `
  -Serial <quest-serial> `
  -SkipBuild
```

The Quest validator also pulls and validates the app-rendered panel PNGs:

```text
*_screen_sam-selected.png
*_screen_affective-slider-selected.png
*_screen_saved.png
```

## Export Contract

Each completed run writes JSON, CSV, and `session-index.jsonl`.

The JSON and CSV include `ratingTarget=previous_session`.

SAM fields include:

```text
sam_valence_raw_1_5
sam_valence_normalized_0_1
sam_arousal_raw_1_5
sam_arousal_normalized_0_1
```

Affective Slider fields include:

```text
as_valence_raw_0_100
as_valence_normalized_0_1
as_arousal_raw_0_100
as_arousal_normalized_0_1
```

The JSON export also records SVG asset provenance and grid hashes.
