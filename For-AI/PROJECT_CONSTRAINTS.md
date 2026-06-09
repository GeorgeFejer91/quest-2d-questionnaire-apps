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

- Open-source naming must follow the repo product brand. Use "Quest 2D
  Questionnaire Apps" for the repository/product family, "Quest Questionnaire
  Builder" for the GUI surface, and `org.questquestionnaire.*` for Android
  package namespaces. Use `quest-questionnaire-*` for generated questionnaire
  IDs, `questquestionnaire.*` for schema/version tags, `custom_slider` for the
  generic uploaded slider block, and `slider_q###` for slider export columns.
  Do not reintroduce legacy project, lab, personal, organization, or unrelated
  Unity study names into source, docs, package IDs, app labels, examples, or
  generated defaults. Example stimulus APK placeholders should use neutral
  names such as `org.questquestionnaire.stimulusdemo`.
- These apps are native Android 2D panel apps for Meta Horizon OS, not Unity,
  Unreal, OpenXR, or immersive XR apps unless a future project direction
  explicitly changes that.
- Use stable wording: "2D panel app", "Android 2D app for Meta Horizon OS", or
  "2D panel app for Meta Horizon OS".
- Quest app switching should use explicit Android package/activity/action
  contracts and launch extras.
- For questionnaire-before-stimulus participant studies, prefer 2D-first
  launcher mode as the default front door: the questionnaire APK starts from
  Meta Home, saves configurable block 1, and `openNext`s into the configured
  Unity APK. The generated study APK may be config-pinned to one Unity
  package/activity, but the reusable Android source must stay builder/config
  driven rather than hard-coded to one Unity app. Keep later trigger/input
  ownership in Unity.
- Block 1 is not hard-coded to demographics or any other questionnaire.
  Demographics is a generic participant-field questionnaire type with a
  downloadable preload/template that users can edit, remove, or replace.
  Hosted/product mode must not preselect a named instrument or fixed
  questionnaire in Block 1; the block exists by default, but its elements are
  user-selected.
- The cleanest questionnaire-before-video flow is:
  `2D block 1 -> Unity Start experiment gate -> Unity video/stimulus`. In this
  shape, the first questionnaire block is not launched over a running Unity
  video at all. Unity should consume the block-completion extras, show a
  foreground start target, and only begin video after participant/operator
  input inside Unity.
- Generic Unity demo/stimulus APKs should pass the input-modality guardrail
  before headset trials: both Quest controller and hand OpenXR profiles enabled,
  optional hand tracking in the manifest, and no Horizon controller-required
  launch dialog unless controller-only input is an explicit study constraint.
- Background 2D apps, Android shell helpers, and ADB do not own raw controller
  input while a foreground immersive Unity/XR app owns focus.
- The generated 2D questionnaire APK is the study logic owner. Unity/stimulus
  APKs must stay passive: they may present stimulus content and emit simple
  trigger events, but they must not decide questionnaire order, questionnaire
  type, scoring, participant state, block progression, or export behavior. A
  Unity demo can prove the workflow with a single end trigger; the
  questionnaire APK interprets that trigger against its own protocol state and
  resumes the next configured block.
- The product path should use one Unity/stimulus APK plus one generated 2D
  questionnaire APK. The questionnaire APK owns current participant/session
  state, completed blocks, the next pending block, trigger-to-block mapping,
  save-before-handoff behavior, and export indexing. Unity may own stimulus
  timing and the physical moment a trigger fires, but not the study protocol.
- The V2 runtime sequence is always questionnaire-first: a normal launch starts
  block 1 in the generated 2D APK, block 1 completion saves state and launches
  the configured Unity/stimulus APK, the questionnaire APK remains backgrounded
  while listening for a passive Unity trigger, and the next foreground
  questionnaire block is chosen by the 2D APK protocol state. Unity never
  chooses "block 2" or any questionnaire module on return.
- When the generated questionnaire APK launches Unity, it should pass
  `mq.triggerReceiverPackage`, `mq.triggerReceiverActivity`, and
  `mq.triggerReceiverAction`. Unity trigger code should read those launch
  extras and send only passive trigger metadata back to that receiver.
  Public/preloaded Unity demos in this repo must not include a hard-coded
  questionnaire package fallback; if they are launched directly without
  receiver extras, they should not perform questionnaire handoff. Reusable
  developer templates may document an explicit opt-in local fallback, but that
  is not the product-path study contract.
- Public Unity demos that use `launchMode="singleTop"` must make the newest
  Android launch intent visible to Unity bridge code by calling
  `setIntent(intent)` in `onNewIntent()`. Without that, a direct Meta Home
  launch can reuse stale `mq.triggerReceiver*` extras from a previous
  questionnaire-started session and appear interdependent.
- Prefer `mq.triggerId` as the Unity-to-questionnaire contract. `mq.blockId` and
  `mq.blockNumber` are optional developer fallbacks for diagnostics or explicit
  tests, not the normal Unity decision surface.
- The recommended copy-first Unity integration for V2 is
  `MyQuestionnaireVR-2D/tools/unity/QuestQuestionnairePassiveTriggerBridge.cs`.
  It emits `mq.triggerId` to the questionnaire-supplied `mq.triggerReceiver*`
  target and intentionally has no hard-coded questionnaire package fallback.
  Treat older `QuestQuestionnaireChainBridge`, ChainLink hooks, broker commands,
  and direct-panel launch helpers as legacy/advanced tooling, not the default
  public protocol.
- The questionnaire broker must understand passive `trigger` commands itself.
  External adapters such as LSL may forward `triggerId` into that broker, but
  they must not encode questionnaire type, next block, scoring, or export
  decisions. Repeated triggers should not replay completed blocks unless the
  generated protocol explicitly marks a step as repeatable.
- LSL `command=trigger` is a passive marker adapter only. The host bridge must
  reject questionnaire-routing fields such as `finishBehavior`, `nextPackage`,
  `questionnaireMode`, `blockId`, `blockNumber`, and chain-plan payloads on
  passive triggers. Legacy LSL commands may remain for advanced tooling, but
  they are not the public two-APK product path.
- The accepted transport decision lives in
  `docs/trigger-transport-decision-record.md`: Android intents are the default
  in-headset app switch; native in-APK LSL is possible but future/advanced, and
  any LSL path must feed the questionnaire-owned trigger broker without routing
  logic.
- Public/preloaded stimulus demos must represent the product contract with
  immersive Unity/stimulus APKs when used for headset demonstrations. Tiny
  native Android scenario APKs may exist as local scanner fixtures, but they
  must not be presented as the intended Unity participant experience. Repo demo
  preloads should scan a real local APK from the user's checkout/program and
  read its embedded trigger catalog before unlocking headset install.
- The public three-circle protocol demo has a matching generated questionnaire
  config at
  `MyQuestionnaireVR-2D/QuestionnaireConfigs/examples/quest-questionnaire-three-circle-protocol-demo.config.json`.
  Validate that pair with
  `MyQuestionnaireVR-2D/tools/quest-minimal-apk-trigger-protocol-validate.ps1`.
  Its default mode is dry-run/preflight only; use `-RunLive -Serial <serial>`
  only with explicit physical Quest operator intent.
- The local companion may expose that same gate as
  `POST /api/minimal-protocol` plus
  `GET /api/minimal-protocol-job?runId=...` for developer/offline validation.
  This endpoint must default to dry-run and its dry-run receipt should say
  `pass-with-physical-pending`; do not treat it as a live Quest product-path
  pass.
- Public builder surfaces should use repo/product-neutral names and links.
  Avoid personal owner names, legacy project brands, or old study labels in the
  GUI, packaged Pages output, downloadable launcher links, and companion
  status defaults. Prefer package-relative assets and `questquestionnaire`
  package/schema names.
- Unity example builds may need a short temporary build path on Windows because
  Unity/Gradle/CMake generated paths can exceed practical path limits under a
  deep Documents/GitHub checkout. The three-circle demo provides a short-path
  build helper and should publish the real Unity APK, not the scanner fixture,
  as the public three-trigger preload.

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
  the local companion and opens the same connected builder page from the local
  companion origin. The hosted static GitHub Pages page remains the published
  product entry point, but browser private-network rules may block hosted pages
  from calling loopback APIs directly.
- The loopback page served by the local companion in `OnlineConnector` mode is
  still a final-product GUI surface. It should hide `data-dev-only` sections
  just like the hosted Pages entry point. Use `?developerMode=1` only when an
  engineer intentionally wants the local validation cockpit.

Keep both paths backed by the same HTML/JavaScript source and local companion
API. The hosted online GUI is the final user-facing product and should stay
minimal: download/connect the local companion, load or scan a scenario APK
trigger catalog, assign questionnaire types to detected trigger blocks,
generate the questionnaire APK, detect a Quest, and install/load the APK onto
the headset. Offline/local mode may expose development validation controls,
stress runners, audit packets, and raw logs, but those must be hidden from the
hosted final-product surface unless they become true user requirements.

After any GUI or website change, open the resulting website URL before the work
is considered done. For hosted GUI changes, regenerate the staged Pages copy,
commit, push, and verify the public URL so the change actually goes online.
The local companion default port is `8776`; avoid reusing `8765` as the default
because that origin has been contaminated by older local web apps/service-worker
caches on the lab PC and can show the wrong application.

The questionnaire builder is an APK-first workflow. The first user action in a
fresh build should be loading an existing scenario APK or trigger catalog with a
questionnaire trigger manifest. Downstream block building, questionnaire
editing, validation, export, and APK-generation controls may remain visible for
orientation, but they should be disabled until a trigger manifest or the
repository example APK catalog is loaded. Companion setup and dependency
controls are the exception: they must remain reachable before APK load because
the hosted product needs the local PC companion before it can scan, generate, or
install anything. Each enabled manifest trigger maps to a questionnaire block,
and questionnaire completion should default to returning to the calling scenario
APK.

The questionnaire builder layout should behave like a one-page website: a fixed
left navigation menu with vertically arranged links, and a single scrolling
content column where each workflow step is one section. Keep panels and control
groups stacked vertically. Do not reintroduce side-by-side dashboard columns for
the builder workflow. The left rail should include an always-visible Downloads
group for the accompanying local companion software and launchers, because the
hosted static GUI depends on that local companion for trusted PC actions.
Hosted mode should hide developer-only pipeline sections marked with
`data-dev-only`. Companion download links, dependency status/install controls,
connector URL/token fields, and Quest detection should be reachable before an
APK is loaded; only APK-dependent actions such as generating or installing the
questionnaire APK should remain gated on the trigger manifest. Sequential
workflow gating must not lock the connector URL, pairing token, Check backend,
Quest serial, or Detect Quest controls.
The visible product GUI should expose only the user workflow: load/scan the
scenario APK, build questionnaire elements inside the detected block segments,
bake the generated questionnaire APK, and load the staged scenario APK plus the
generated questionnaire APK onto the Quest. Do not expose standalone
"questionnaire content", "project and return behavior", validation pipeline,
raw config/JSON, raw routing, block id/save namespace, or review/output stages
in the product surface. Those controls may remain hidden as developer-only DOM
or scripts when necessary for tests and internal workflows.
The product workflow should be sequential and visibly gated: load/scan APK is
segment 0, Block 1 is segment 1, later return blocks follow the trigger order,
and users should not be able to bake until every block has at least one
questionnaire element. Headset install should remain unavailable until a
questionnaire APK was baked and a local scenario APK file is staged. Long
operations such as bake and Quest install should show local status/progress in
the section where the user clicked.
Block segment count is derived as `1 + scanned passive Unity trigger count`.
Block 1 always exists after any valid scenario APK/catalog is loaded because
completion of block 1 launches the loaded Unity/stimulus APK by default. Each
passive Unity trigger adds exactly one later return block unless the builder
explicitly supports a future repeat/branching protocol.
Visible product labels should describe the chain generically, not the current
demo media. Use `Before experiment/running APK` for Block 1 and `After trigger
N` for return blocks. Do not expose "before video", "after video", or
video-specific event IDs in the builder defaults; a real catalog can still use
a video as its stimulus content while its triggers remain passive IDs.
Only expose questionnaire element types in the product block dropdown when the
current builder/runtime can accept their upload template end to end. Template
ideas for future multiple-choice, text-entry, or temporal-tracer imports may
remain in hidden developer code, but normal users should see only currently
usable CSV/ZIP-backed elements.
Section 1 should also include a user-friendly "Load example APK" fallback that
points at local packaged example APK candidates and displays the GitHub folder
URL where the example APK and Unity project live.
When the local companion is connected, preloaded/repo examples must scan and
stage an actual local example APK from the user's downloaded repo/program. The
GUI must derive trigger count from the embedded trigger catalog inside that APK,
not from a hardcoded GitHub/raw JSON catalog. Catalog-only previews are
non-installable and must not unlock the Quest install path.
In hosted final-product mode, loading any scenario APK/trigger catalog should
automatically make the generated questionnaire APK the front door:
`questionnaireFirst`, editable block 1, `openNext` to the scanned Unity
package. Do not treat Unity trigger metadata as questionnaire decisions. Use a
stable generic product start id such as `study_start_block_1`; leave manifest
trigger assignments empty until the builder/user maps questionnaire elements
to later Unity-triggered return blocks.
Generated questionnaire-first APKs should also be named for the operator-facing
sequence in Meta Home and in the first panel heading:
`Start Experiment | <target APK label>`. Derive `<target APK label>` from the
scanned trigger catalog/experiment target label, falling back to the target
package only when no human-readable label exists.
The Bake step must expose a user-editable generated questionnaire APK app name.
The automatic default remains `Start Experiment | <target APK label>`, but a
manual value must become `config.appDisplayName` and the Android app label.
Questionnaire CSV templates should be type-oriented, inspired by tools such as
Qualtrics: demographics/participant fields, slider/VAS, Likert, multiple
choice, text entry, pictographic scales, and temporal tracer dimensions are
template categories. Named instruments such as MAIA-2 are preloaded
questionnaire examples/library content under a generic type, not top-level GUI
questionnaire types or the definition of Likert. Until the APK runtime supports
a type end to end, the GUI must fail unsupported uploaded type rows loudly
instead of silently converting them into the wrong questionnaire.
Model questionnaire elements according to their runtime shape. Self-contained
elements such as temporal experience tracer dimensions are configured as
individual units with their own parameters; users add another unit when they
want another tracer page. Likert questionnaires are long-form elements: many
items can live inside one questionnaire element with a scrollable participant
screen, and generated config must preserve whether score options render
vertically or horizontally under each item.
In the visible block builder, selected questionnaire elements should render as
self-contained page cards. The next possible page should be a separate empty
page card underneath the existing cards, not an add-control row visually
attached to the current questionnaire page.
The builder should prefer downloadable templates and placeholder metafiles over
bespoke UI for every custom questionnaire type. Users download a CSV, manifest,
or ZIP placeholder, replace items/assets/parameters locally, reupload it, and
the GUI generates the matching APK config. Pictographic scales should support a
ZIP template with placeholder PNG assets plus a text/manifest file that users
replace before reupload.

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
- Quest verification must start with the shared ADB readiness probe against an
  explicit physical headset serial. Ignore offline emulators as proof of Quest
  readiness. If ADB is online but product-path readiness is blocked because the
  headset is asleep/display-off, use at most one explicit
  `-WakeBeforeReadiness` recovery, record the `wakeAttempt`, rerun readiness,
  and proceed to replay/export or handoff only once `productPathStatus` is
  `ready`. If the headset remains asleep or a Horizon controller launch-check
  dialog is focused, mark the physical gate blocked/pending and ask the headset
  operator to clear it.
- Do not claim a Quest chain is experiment-ready from routing evidence alone
  when the foreground scenario cannot emit a real completion signal.
- Do not commit generated Gradle state, `Builds/`, `artifacts/`, `.gradle/`,
  `build/`, `local.properties`, or oversized Unity/scenario APKs.
- Curated release APKs belong in `apks/`, with `apks/checksums.sha256` updated
  when they change.
