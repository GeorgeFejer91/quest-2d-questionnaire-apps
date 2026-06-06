# Architecture

## 2D Panel App, Not XR App

The successful pattern is a native Android app that opens as a flat, resizable
Horizon OS panel. It does not use Unity, OpenXR, Meta XR SDK, passthrough, or an
immersive canvas.

Use this wording consistently:

- 2D panel app
- Android 2D app for Meta Horizon OS
- 2D questionnaire panel for Quest

Avoid calling these apps XR apps unless they later become immersive. The point
is that Horizon OS already knows how to show standard Android activities as
panels, route controller/hand/touch/keyboard input to them, and resize them.

## Manifest Shape

Quest panel apps should declare that touchscreen and faketouch are not required
so the app is installable and usable on a headset:

```xml
<uses-feature android:name="android.hardware.touchscreen" android:required="false" />
<uses-feature android:name="android.hardware.faketouch" android:required="false" />
```

The main activity should be exported when it is launched by another app, use
`singleTop` when repeated intent launches should update/reset state, and be
resizeable:

```xml
android:exported="true"
android:launchMode="singleTop"
android:resizeableActivity="true"
```

Use the `<layout>` manifest element to give Horizon OS a sane default panel
size. The working size for these apps is `1280dp x 800dp` with a minimum around
`640dp x 480dp`.

## Intent Contract

Every app should expose a stable explicit component and a stable action:

- Demographic questionnaire:
  - package `org.viscereality.questionnaires2d`
  - activity `.MainActivity`
  - action `org.viscereality.questionnaires2d.RUN`
- Temporal tracer:
  - package `org.viscereality.temporaltracer2d`
  - activity `.MainActivity`
  - action `org.viscereality.temporaltracer2d.RUN`

Use explicit component launches when chaining experiment APKs. Implicit actions
are useful for discovery and compatibility, but explicit package/activity pairs
make validation and recovery much easier.

## Launch Extras

Pass session context in Android intent extras. Keep names stable across
questionnaire apps:

```text
mq.sessionId
mq.participantId
mq.participantName
mq.language
mq.experimentId
mq.scenarioId
mq.trialId
mq.blockId
mq.blockNumber
mq.finishBehavior
mq.callerPackage
mq.callerActivity
mq.nextPackage
mq.nextActivity
```

The active questionnaire app should save first, then honor `finishBehavior`.
Useful finish behaviors are:

- `staySaved`: save and remain on the final panel.
- `resumeCaller`: save, then launch `mq.callerPackage` / `mq.callerActivity`.
- `openNext`: save, then launch `mq.nextPackage` / `mq.nextActivity`.

## Input Boundary

2D panel apps can receive ordinary Android routed input: controller pointer
clicks, hand pinch, touch, mouse, keyboard, and Android back. They should not be
designed as background listeners for raw Meta Touch controller actions while a
different immersive app owns focus.

If a Unity/OpenXR scenario needs to advance the experiment on a controller
button, that logic belongs inside the foreground Unity app. The Unity app should
then call the broker/orchestrator with an explicit Android intent.

