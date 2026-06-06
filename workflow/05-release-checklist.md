# Release Checklist

## Before Building

- Confirm the questionnaire config is the intended study config.
- Validate language parity and participant-burden counts.
- Check long, double-barreled, or negated wording.
- Confirm package id, activity, and launch action are stable.
- Confirm panel sizing is appropriate for Quest: default `1280dp x 800dp`,
  minimum about `640dp x 480dp`.

## Before Installing On Quest

- Build from a clean project state.
- Copy the intended APK into `apks/`.
- Update `apks/checksums.sha256`.
- Run local render preview at `1280x800`.
- Run logic/unit tests where present.
- Inspect APK package/activity with `get-apk-launch-info.ps1` or ADB package
  tools when needed.

## Quest Smoke Test

- Record `adb devices -l`, model, Android version, size, density, and focus.
- Install with `adb install -r -d`.
- Launch by explicit component.
- Wait for a readiness marker or a stable foreground state.
- Run command replay when available.
- Pull exports from the app-specific external files directory.
- Confirm counts, run ids, and session metadata.
- Capture logcat and foreground final state.

## Manual Input Gate

Use a short human gate for the actual panel input boundary:

- controller pointer trigger,
- hand pinch,
- visible Back,
- Android/hardware Back,
- keyboard focus where relevant,
- save only after required completion.

For temporal tracing, specifically confirm:

- drawing starts only in the left gate,
- backtracking does not corrupt the trace,
- save stays disabled before the end gate,
- SVG/CSV/JSON exports match the completed trace.

## Chain Readiness

For wrapper-linked legacy Unity APKs:

- Treat target launch plus questionnaire export as routing/data-safety evidence.
- Add a human/manual completion gate if the scenario cannot call back.

For source-hook Unity APKs:

- Confirm the Unity app receives chain extras.
- Confirm the scenario calls back on semantic completion.
- Confirm the broker advances only after that callback.

## GitHub Hygiene

- Do not commit `.gradle`, `build`, `artifacts`, `Builds`, or `local.properties`.
- Do not commit Unity/scenario APKs over 100 MB to normal git history.
- Keep only curated installable questionnaire APKs in `apks/`.
- Run `git status -sb` before every commit.
- Run `git log --stat -1` after commit to confirm the right material landed.

