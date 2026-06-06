# For-AI Changelog

Record changes that affect future AI-agent behavior or project constraints.
Use absolute dates.

## 2026-06-06

- Established the root `For-AI/` folder as the canonical AI-agent documentation
  hub.
- Added first-read instructions through root `AGENTS.md` and
  `For-AI/START_HERE.md`.
- Recorded the browser/dashboard versus local companion/Quest APK boundary,
  including online/offline GUI parity and localhost companion rules.
- Recorded standing GitHub hygiene: after large coherent validated changes,
  commit and push when credentials and permissions are available.
- Made the questionnaire builder APK-first: fresh sessions must load a scenario
  APK or trigger catalog before downstream block editing, local dependency,
  validation, export, and APK-generation controls become active.
- Constrained the questionnaire builder UI to a vertically stacked one-page
  website with a fixed left navigation rail, including always-visible downloads
  for the local companion software and launchers.
- Added the `example-scenario-apk/` folder and a "Load example APK" builder
  fallback for users who do not yet have their own trigger-enabled APK.
