# Project Goals

`MyQuestionnaireVR-2D` builds a reusable Meta Quest 2D questionnaire panel app
and the PC tooling needed to configure, validate, build, and test questionnaire
APKs.

Core goals:

- Support cross-package Quest handoff: a foreground Unity/XR app triggers a
  separate reusable 2D questionnaire APK, the questionnaire receives normal
  Quest panel input, then returns to the caller without ADB, force-stop,
  package killing, or Meta menu navigation in the product path.
- Support trigger-based questionnaire routing: Unity or another app can emit
  trigger event IDs such as `1`, `2`, `3`, etc.; each trigger maps to exactly
  one questionnaire block or block sequence defined by the builder config.
- Let researchers import an APK trigger catalog or compact trigger JSON,
  inspect the available trigger IDs, and map each trigger to questionnaire
  blocks in an interactive GUI.
- Keep the questionnaire runtime native Android 2D panel based, not Unity or
  OpenXR, unless the project direction explicitly changes.
- Preserve evidence-oriented validation: configs, trigger mappings, generated
  APKs, render previews, and Quest runs should leave machine-readable artifacts.

Current preferred architecture:

- A desktop launcher starts a local Windows companion service and opens the
  questionnaire builder HTML GUI in the user's normal local browser.
- The same HTML GUI is also hosted as a static online site via GitHub Pages.
- The online GUI connects to the locally installed companion service when the
  user enters the locally printed pairing token.
- The local companion owns trusted actions: file writes, dependency checks,
  config validation, APK generation, render previews, and future local tooling.
- A hosted static webpage must not directly install software, execute local
  programs, or assume server-side code is available.
