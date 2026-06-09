# Trigger Transport Decision Record

Status: accepted for V2 product path

Date: 2026-06-09

## Decision

Use Android intents as the default transport between the immersive
Unity/stimulus APK and the generated Quest 2D questionnaire APK.

Use LSL only as an optional marker input adapter into the same
questionnaire-owned trigger broker/state machine. LSL must not become a second
study-flow engine.

## Product Shape

The public product path has exactly two APKs:

```text
generated 2D questionnaire APK
  -> launches one immersive Unity/stimulus APK
  -> Unity emits passive mq.triggerId events
  -> the same questionnaire APK resumes and decides the next block
```

The participant starts the questionnaire APK. The questionnaire APK owns:

- participant/session state
- block order
- trigger-to-block mapping
- repeat rules
- questionnaire type selection
- scoring
- exports
- foreground/background recovery state

Unity owns only stimulus presentation and the physical timing of trigger
emission. Unity must not decide questionnaire routing.

## Why Android Intents Are The Default

Android intents are the platform app-to-app lifecycle primitive. They can carry
`mq.triggerId`, target a package/activity, and bring the existing questionnaire
activity forward with `SINGLE_TOP`/`REORDER_TO_FRONT`.

This keeps the Unity integration tiny:

```csharp
QuestQuestionnairePassiveTriggerBridge.EmitTrigger("trigger_1_complete");
```

The generated questionnaire APK supplies the receiver target when it launches
Unity:

```text
mq.triggerReceiverPackage
mq.triggerReceiverActivity
mq.triggerReceiverAction
```

Public Unity demos must read those launch extras and must not contain a
hard-coded questionnaire package fallback. If they are opened directly from
Meta Home without receiver extras, they continue as stimulus demos and ignore
questionnaire handoff.

## LSL Assessment

Native LSL inside the questionnaire APK is technically possible. The LSL
project documents Android builds and Java/AAR integration. However, it is not
the simplest default product path because it adds:

- Android SDK/NDK/CMake/AAR packaging work
- Wi-Fi discovery and stream reliability concerns
- headset-side background listening lifecycle concerns
- the same Android foregrounding constraints that intents already solve more
  directly

Android also restricts background activity launches. A background questionnaire
listener that receives an LSL marker would still need an allowed foregrounding
route before it can reliably bring a 2D panel forward. Therefore native LSL is
a future/advanced transport, not the default v2 chain.

The v2-supported LSL route is host-side:

```text
external LSL marker
  -> host LSL bridge
  -> Android broker intent command=trigger
  -> generated questionnaire APK interprets mq.triggerId
```

The bridge accepts only passive trigger/session/source/timing fields for
`command=trigger`. It rejects questionnaire routing fields such as `blockId`,
`questionnaireType`, `finishBehavior`, `nextPackage`, scoring fields, export
fields, and participant-state fields.

## Minimal Contract

Unity/stimulus APK:

- embeds a trigger catalog with trigger ids only
- reads questionnaire receiver extras supplied by the questionnaire launch
- emits `mq.triggerId` plus optional inert metadata
- remains immersive/OpenXR when it is a Unity Quest app
- does not choose questionnaire type, block, scoring, repeat, or export policy

Questionnaire APK:

- launches Unity after the configured questionnaire block
- saves before handoff
- interprets returned `mq.triggerId` against its own protocol state
- resumes the next pending block or configured trigger-mapped block
- owns all exports

LSL adapter:

- is optional
- maps lab markers to passive `triggerId` events
- feeds the same questionnaire-owned trigger broker
- must not encode study routing

## Source References

- Android background activity launch restrictions:
  https://developer.android.com/guide/components/activities/secure-bal
- Android activity launch modes and `onNewIntent`:
  https://developer.android.com/guide/topics/manifest/activity-element.html
- LSL Android build notes:
  https://labstreaminglayer.readthedocs.io/dev/build_android.html
- LSL overview and supported platforms:
  https://labstreaminglayer.readthedocs.io/info/intro.html

## Validation

Before publishing a demo or package, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MyQuestionnaireVR-2D\tools\validate-passive-trigger-protocol.ps1

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\MyQuestionnaireVR-2D\tools\validate-minimal-apk-trigger-protocol.ps1 `
  -SkipQuestionnaireApkBuild
```

These local validators prove the software contract. Live Quest install,
participant launch, Unity focus, physical trigger emission, questionnaire
return, and export pull remain separate physical evidence gates.
