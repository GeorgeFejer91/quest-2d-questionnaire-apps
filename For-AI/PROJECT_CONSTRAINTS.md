# Project Constraints For AI Agents

These are living constraints for the whole repository. Update this file when
the user gives a project rule that future agents must preserve.

## Documentation-Only Boundary

`For-AI/` is documentation only. Do not place code, generated files, build
outputs, APKs, experiment exports, screenshots, logs, or private participant
data in this folder.

Use it for:

- project constraints,
- repeated instructions for agents,
- handoff notes,
- decisions that are easy to lose between sessions.

## Quest App Architecture

- These apps are native Android 2D panel apps for Meta Horizon OS, not Unity,
  Unreal, OpenXR, or immersive XR apps unless a future project direction
  explicitly changes that.
- Use stable wording: "2D panel app", "Android 2D app for Meta Horizon OS", or
  "2D panel app for Meta Horizon OS".
- Quest app switching should use explicit Android package/activity/action
  contracts and launch extras.
- 2D-first launcher mode is allowed for participant-facing studies: the
  questionnaire APK can default to demographics and `openNext` into Unity after
  saving block 1. Keep that behavior in builder config, not hard-coded source,
  and keep later trigger/input ownership in Unity.
- Background 2D apps, Android shell helpers, and ADB do not own raw controller
  input while a foreground immersive Unity/XR app owns focus.
- The questionnaire owns questionnaire state and exports. ChainLink or the
  orchestrator owns experiment order, block numbers, app switching, and metadata
  propagation.

## Browser Dashboard vs Local/Native Engine

The takeaways from similar dashboard-plus-companion projects mostly apply here.
The browser should improve ergonomics; it must not become the trusted
experiment engine.

For this repo, the boundary is:

- HTML builder/dashboard: decision surface, config editing, previews, status,
  trigger mapping, and user-friendly controls.
- Local companion on `127.0.0.1`: file access, dependency checks, validation,
  APK generation, render previews, local job execution, and other trusted PC
  actions.
- Installed Quest APKs: participant-facing questionnaire/tracing flow,
  response capture, timing-sensitive behavior, draft persistence, and final
  CSV/JSON/SVG exports.

Do not move validated participant timing, audio onset timing, tactile triggers,
response logging, or experiment data ownership into browser JavaScript. Browser
JavaScript is appropriate for forms, dashboards, previews, import/export
helpers, connection status, and status polling.

## Online And Offline GUI Parity

The questionnaire builder must keep both launch paths available:

- Offline/local GUI: `MyQuestionnaireVR-2D/Start-QuestionnaireBuilderApp.cmd`
  starts the local companion and opens the dashboard in the user's browser.
- Online connector GUI:
  `MyQuestionnaireVR-2D/Start-QuestionnaireBuilderOnlineConnector.cmd` starts
  the local companion while the hosted static GitHub Pages page connects to it.

Keep both paths functionally identical except for the online pairing step.
Do not add a builder feature to one path without keeping the other aligned.

After any GUI or website change, open the resulting website URL before the work
is considered done. For hosted GUI changes, regenerate the staged Pages copy,
commit, push, and verify the public URL so the change actually goes online.

The questionnaire builder is an APK-first workflow. The first user action in a
fresh build should be loading an existing scenario APK or trigger catalog with a
questionnaire trigger manifest. Downstream block building, questionnaire
editing, validation, export, dependency, and APK-generation controls may remain
visible for orientation, but they should be disabled until a trigger manifest or
the repository example APK catalog is loaded. Each enabled manifest trigger maps
to a questionnaire block, and questionnaire completion should default to
returning to the calling scenario APK.

The questionnaire builder layout should behave like a one-page website: a fixed
left navigation menu with vertically arranged links, and a single scrolling
content column where each workflow step is one section. Keep panels and control
groups stacked vertically. Do not reintroduce side-by-side dashboard columns for
the builder workflow. The left rail should include an always-visible Downloads
group for the accompanying local companion software and launchers, because the
hosted static GUI depends on that local companion for trusted PC actions.
Section 1 should also include a user-friendly "Load example APK" fallback that
loads `example-scenario-apk/questionnaire-trigger-catalog.json` from the repo
and displays the GitHub folder URL where the example APK and Unity project live.

The hosted GitHub Pages page is an interface only. It cannot directly install
packages, read arbitrary local files, run build tools, access hardware, or hold
private experiment data. Anything real must go through the local companion or
the installed Quest app.

## Local Companion Rules

- Bind local control APIs to `127.0.0.1`, not a public network interface.
- Allow CORS origins deliberately, including localhost and the configured
  hosted dashboard origin. Avoid broad access without a strong reason.
- Privileged endpoints must require the local pairing token.
- Make connection state obvious in the UI: connected/disconnected, backend URL,
  retry/connect action, and companion launch/download guidance.
- Use relative asset paths for hosted static dashboards so GitHub Pages project
  URLs keep working.
- Keep API compatibility visible. The backend should expose health/status and,
  when practical, version information so the frontend can warn about mismatches.
- Long-running work such as rendering, stress checks, or APK/session preparation
  should use backend jobs and status polling instead of blocking the page.
- UI preferences may live in browser `localStorage`; experiment parameters and
  participant data belong in config files, backend-owned files, or app exports.

## Validation And Release Hygiene

- Follow the validation ladder in `workflow/START_HERE.md` and
  `workflow/05-release-checklist.md`.
- Do not claim a Quest chain is experiment-ready from routing evidence alone
  when the foreground scenario cannot emit a real completion signal.
- Do not commit generated Gradle state, `Builds/`, `artifacts/`, `.gradle/`,
  `build/`, `local.properties`, or oversized Unity/scenario APKs.
- Curated release APKs belong in `apks/`, with `apks/checksums.sha256` updated
  when they change.
