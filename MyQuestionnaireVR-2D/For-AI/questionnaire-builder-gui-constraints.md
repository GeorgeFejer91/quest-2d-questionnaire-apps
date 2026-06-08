# Questionnaire Builder GUI Constraints

The questionnaire builder source should stay shared across offline and online
entry points, but the hosted online GUI is the final user-facing product. Do
not let the public GitHub Pages page become a development validation cockpit.

Required modes:

- Offline desktop mode: the user double-clicks the desktop launcher, the local
  companion service starts on `127.0.0.1`, and the same HTML GUI opens in the
  local browser.
- Online connector mode: the user opens the hosted static GUI and connects it
  to the local companion service with a pairing token.

Do not fork the GUI into separate offline and online implementations. Prefer one
HTML/JavaScript UI with mode-specific visibility:

- Offline mode may auto-fill the local connector URL and pairing token because
  the local companion injects them when serving the page.
- Online mode must ask the user for the connector URL/token or use safe defaults
  such as `http://127.0.0.1:8765`.
- Online mode should show only the final-product path: download/connect the
  local companion, load or scan an APK trigger catalog, assign questionnaire
  types to detected trigger blocks, generate the questionnaire APK, detect a
  Quest, and install/load the APK onto the headset.
- Companion setup belongs before the APK gate. In hosted mode, dependency
  download/status/install controls, connector URL/token fields, and Quest
  detection must remain reachable before an APK trigger manifest is loaded.
  Keep only APK-dependent actions such as Generate APK and Install APK gated on
  the trigger catalog.
- Development-only controls such as workflow validation, direct handoff trials,
  replay/export stress runners, audit packets, raw logs, and pipeline commands
  may remain in the shared source for offline engineering, but must be hidden
  from the hosted final-product surface.

Workflow constraint:

- Keep all public and generated naming aligned with the open-source product
  brand. The GUI should present itself as "Quest Questionnaire Builder", emit
  generated IDs such as `quest-questionnaire-*`, use
  `org.questquestionnaire.*` package/action defaults, use `custom_slider` for
  the uploaded slider block, and avoid legacy project, organization, personal,
  lab, or unrelated Unity-study names in labels, sample configs, staged hosted
  HTML, and generated commands.
- The builder should present an APK-first sequence. A fresh session starts by
  loading an existing scenario APK, or a compact trigger catalog JSON, that
  declares questionnaire triggers.
- The hosted GUI should keep the trigger/block assignment, local dependency,
  APK generation, and Quest install controls visible. Questionnaire content
  editing and project settings may stay available in offline/developer mode,
  but should not be part of the public minimal flow unless needed by a study
  user.
- The product GUI must keep questionnaire content editing inside the generated
  block segments created by the APK scan. Do not expose separate "Build
  questionnaire content", "Set project and return behavior", validation
  pipeline, raw routing, raw config/JSON, or output review sections to normal
  users. Keep only basic status feedback beside the four product steps: load
  APK, build blocks, bake questionnaire APK, and load both APKs onto the Quest.
- Block segment count is `1 + scanned passive Unity trigger count`. Block 1 is
  always created after any valid scenario APK/catalog load, because completing
  block 1 launches the loaded Unity/stimulus APK by default. Each passive Unity
  trigger adds one later return block, so a one-trigger demo must show exactly
  Block 1 and Block 2.
- Visible block labels should stay media-neutral: Block 1 is `Before
  experiment/running APK`, return blocks are `After trigger N`, and default
  event IDs should use neutral passive trigger names such as
  `trigger_1_complete`.
- The visible block dropdown should only expose questionnaire element types
  whose templates can currently be uploaded and consumed by the builder/runtime.
  Keep future multiple-choice, text-entry, and temporal-tracer template ideas
  hidden until their imports are end-to-end supported.
- Trigger mappings are the source of block-builder structure: each enabled
  manifest trigger should become one questionnaire block, with completion
  returning to the calling scenario APK by default.
- The generated 2D questionnaire APK is the study logic owner. Unity/stimulus
  APKs must stay passive: they may present stimulus content and emit simple
  trigger events, but they must not decide questionnaire order, questionnaire
  type, scoring, participant state, block progression, or export behavior. A
  Unity demo can prove the workflow with a single end trigger; the
  questionnaire APK interprets that trigger against its own protocol state and
  resumes the next configured block.
- The V2 sequence is fixed at the workflow level: generated 2D APK block 1 runs
  first, the end of block 1 saves state and launches the configured Unity APK,
  the 2D APK stays backgrounded while waiting for Unity's passive trigger, and
  foreground recovery continues the next configured questionnaire block from
  the 2D APK protocol. Do not let Unity decide "block 2" or questionnaire
  module order.
- Treat Unity trigger catalogs as event manifests, not questionnaire plans. In
  V2 the GUI/questionnaire config maps trigger IDs to blocks; Unity should send
  `mq.triggerId` and optional session metadata only. `mq.blockId` and
  `mq.blockNumber` are developer fallbacks, not the normal study contract.
- Block 1 is configurable and must not be prefilled with demographics, MAIA-2,
  or any other fixed questionnaire. Demographics is a generic
  participant-field type with a CSV-backed preload/template, not a hard-coded
  product step. Loading any scenario APK/trigger catalog should automatically
  set the generated questionnaire APK to `questionnaireFirst` + editable empty
  block 1 + `openNext` to the scanned Unity package/activity. Do not reuse
  Unity demographics/recommended-mode metadata as a block 1 decision; keep
  manifest trigger assignments empty until the builder/user maps questionnaire
  elements to later Unity-triggered questionnaire/tracer blocks.
- Generated questionnaire-first APKs should be visibly named
  `Start Experiment | <target APK label>` in both the Meta Home app label and
  the first questionnaire panel heading. The target label should come from the
  scanned trigger catalog/target app label, falling back to the package name
  only when needed.
- CSV templates should be questionnaire-type templates, not named-instrument
  templates. Keep MAIA-2 as a preloaded questionnaire/library option under the
  generic Likert type; model the upload protocol around reusable types such as
  demographics/participant fields, slider/VAS, Likert, multiple choice, text
  entry, pictographic scales, and temporal tracer dimensions. Unsupported
  uploaded types must produce clear errors until the generated APK runtime and
  exporter support them end to end.
- Prefer template/metafile upload paths over building bespoke UI for every
  questionnaire family in V2. The user should be able to download a CSV,
  manifest, or ZIP with placeholders, replace the values/assets locally, upload
  it again, and let the GUI add the resulting questionnaire element to a block.
  Pictographic scales use this same rule with a ZIP template containing
  placeholder PNGs and a text/manifest file.
- The page should behave like a one-page website with a fixed left navigation
  rail and vertically stacked content sections. Do not arrange workflow panels
  side by side.
- Keep an always-visible Downloads group in the left rail for the companion
  software package and Windows launchers, because the hosted GUI needs that
  local companion for trusted PC actions.
- Section 1 should include a user-friendly "Load example APK" fallback with the
  GitHub folder URL for `example-scenario-apk/`.
- Device-state helpers in developer runners, such as `Wake before Quest
  verification`, must be explicit opt-in controls, disabled by default, and
  hidden from the hosted final-product path unless they become a user-facing
  requirement. When enabled for offline replay/export, 2D-first, or direct
  handoff jobs, the local companion must send only one bounded wake request
  before the shared readiness probe and record the wake attempt in the job
  summary/receipt.

Security and portability constraints:

- The pairing token must be generated by the local companion on the user's PC.
- The pairing token must be URL/header safe and not tied to any one machine,
  username, repository path, or browser profile.
- The local companion should allow localhost origins for the selected port and
  the configured hosted-page origin. Do not hard-code one developer's PC path.
- The hosted GUI must treat local actions as calls to the trusted local
  companion; it must not claim that GitHub Pages itself installs dependencies or
  runs APK builds.
- Mutating or privileged endpoints must require the pairing token.
- `GET /api/status` may be public enough to discover that the companion is
  reachable, but sensitive paths, generated file locations, and local tool
  details should only be exposed after token authorization.

Terminology:

- Use "desktop app", "local companion", "offline GUI", and "online connector"
  for the PC-side builder architecture.
- Use "2D panel app" for the Quest questionnaire APK.
- Avoid describing the questionnaire APK as an XR app unless a future runtime
  actually becomes immersive.
