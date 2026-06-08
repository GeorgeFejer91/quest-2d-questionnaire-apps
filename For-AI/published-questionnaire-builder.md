# Published Questionnaire Builder Handoff

This documents the online/offline questionnaire builder work completed on
June 6, 2026.

## What Was Published

The questionnaire builder is now available as a GitHub Pages static site:

```text
https://georgefejer91.github.io/quest-2d-questionnaire-apps/questionnaire-builder/
```

The repository was made public because GitHub returned this blocker while the
repo was private:

```text
Your current plan does not support GitHub Pages for this repository.
```

GitHub Pages is enabled from:

```text
branch: main
path: /
```

The first published commit for the builder was:

```text
a96dcad524267dd1a3a34acb6b81575310f7c908
```

## Architecture

There are two modes that share the same source and local companion contract:

- Offline desktop mode: the user runs
  `MyQuestionnaireVR-2D/Start-QuestionnaireBuilderApp.cmd`. This starts the
  local companion service and opens the same HTML GUI in the local browser.
- Online connector mode: the user opens the hosted Pages GUI and runs
  `MyQuestionnaireVR-2D/Start-QuestionnaireBuilderOnlineConnector.cmd` locally.
  The local companion prints a pairing token; the user enters that token in the
  online GUI.

The hosted Pages GUI is the final product surface for study users, not a
software-development cockpit. Its visible workflow should stay minimal:

```text
download/connect local companion -> load/scan APK trigger catalog -> assign
questionnaire type per detected trigger block -> generate questionnaire APK ->
detect Quest -> install/load APK onto headset
```

Public naming should stay open-source and repo-branded: the page is "Quest
Questionnaire Builder", generated questionnaire IDs should use
`quest-questionnaire-*`, Android defaults should use `org.questquestionnaire.*`,
schemas should use `questquestionnaire.*`, and example stimulus packages should
use neutral placeholders such as `org.questquestionnaire.stimulusdemo`.

Block 1 is configurable. Demographics is a suggested preload/template, not a
hard-coded product step. After the hosted GUI loads a scenario APK or trigger
catalog, the generated questionnaire APK should become the front door
automatically: `questionnaireFirst`, editable block 1, and `openNext` into the
scanned Unity package/activity. Manifest trigger assignments remain empty until
the builder/user maps questionnaire elements to later Unity-triggered
questionnaire or tracer blocks.
The fixed V2 sequence is: generated 2D APK block 1 first, block 1 save and
handoff to Unity, 2D APK background wait, passive Unity `mq.triggerId`, then 2D
APK foreground recovery into the next configured protocol block.
The generated 2D questionnaire APK is the study logic owner. Unity/stimulus
APKs are passive trigger emitters: they present stimulus content and emit simple
trigger IDs, but do not choose questionnaire order, questionnaire type, scoring,
participant state, block progression, or export behavior. The hosted builder
must treat scanned Unity trigger catalogs as event manifests and keep
trigger-to-block interpretation in the generated questionnaire config/APK.
The public GUI should expose questionnaire upload through type-oriented CSV
templates rather than named-instrument templates. MAIA-2 is a preloaded
questionnaire/library option; reusable CSV template types should cover
slider/VAS, Likert, multiple choice, text entry, and temporal tracer
dimensions. Unsupported uploaded types must be rejected with clear messages
until the generated APK runtime and exporter support them end to end.
Custom questionnaire families should enter the public GUI through downloadable
templates and placeholder metafiles: CSV for item/scale metadata, and ZIP
templates for asset-backed formats such as pictographic scales where users
replace placeholder PNGs plus a manifest before reupload.

Development validators, direct handoff stress runners, replay/export runners,
readiness audits, manual signoff packet prep, raw logs, pipeline commands, and
other internal evidence tools may remain in the shared source for offline
engineering mode, but must be hidden from the hosted final-product page with
`data-dev-only`/hosted mode unless the user explicitly asks to make them part of
the product.

The hosted Pages site is intentionally static. It must not claim to directly
install software, write files, validate configs, or build APKs. Those actions
belong to the local companion at:

```text
http://127.0.0.1:8765
```

Privileged local actions require the `X-MQ-Builder-Token` header. The companion
generates the token locally on each PC. It is not tied to one machine, user
profile, or repository path.

`GET /api/status` is also the compatibility check. In hosted final-product
mode, the GUI should warn only about product-path capabilities it actually
needs, such as APK generation, dependency status/installation, Quest detection,
and APK install. Offline/developer mode may require the broader receipt
capability set for workflow validation and evidence tooling.

Render preview thumbnails are fetched from the companion through
`GET /api/artifact-preview?path=...`. That route must stay token-protected,
CORS-limited, PNG-only, and constrained to generated artifact roots. Do not
turn it into a general local file browser.
The GUI can show samples from both `generationReceipt` and `workflowReceipt`;
workflow receipts should expose questionnaire and temporal tracer
`samplePngs` when their local render gates run.
Evidence bundles are fetched from the companion through
`GET /api/evidence-bundle?summaryPath=...`. That route must stay
token-protected, constrained to generated artifact roots, and limited to
reviewable evidence file types such as JSON, TXT, LOG, CSV, and PNG.
When the visible receipt is a physical gate packet, the Evidence Bundle button
should download a portable zip rooted at that packet summary and include the
operator runbook, manual signoff template, manual signoff summary, and linked
audit evidence.
The hosted page should expose download links for the companion software package
and Windows launchers in the left rail at all times. Dependency check/install
controls are product-facing because the hosted page needs local PC software to
generate and load APKs.
Companion setup must not sit behind the APK gate in hosted final-product mode:
download links, dependency status/install controls, connector URL/token fields,
and Quest detection should be usable before an APK trigger catalog is loaded.
Keep only APK-dependent actions such as Generate APK and Install APK gated on
the loaded trigger manifest.

The old development controls still matter for engineering confidence. Keep
their implementation in offline/local mode and in validators, but do not expose
them as the public hosted workflow:

- direct handoff and 2D-first stress runners,
- replay/export runners,
- `Validate workflow`,
- `Run headset sequence`,
- `Audit readiness`,
- manual signoff and physical packet prep,
- evidence bundle downloads,
- raw JSON/log panes and pipeline command lists.

## Important Files

Source GUI:

```text
MyQuestionnaireVR-2D/tools/questionnaire-config-editor/index.html
```

Published static copy:

```text
questionnaire-builder/index.html
```

Local companion:

```text
MyQuestionnaireVR-2D/tools/start-questionnaire-builder-app.ps1
```

Desktop launchers:

```text
MyQuestionnaireVR-2D/Start-QuestionnaireBuilderApp.cmd
MyQuestionnaireVR-2D/Start-QuestionnaireBuilderOnlineConnector.cmd
```

Pages staging script:

```text
MyQuestionnaireVR-2D/tools/publish-questionnaire-builder-github-pages.ps1
```

Hosted publication validator:

```text
MyQuestionnaireVR-2D/tools/validate-hosted-questionnaire-builder.ps1
```

## Update Workflow

When changing the builder GUI:

1. Edit `MyQuestionnaireVR-2D/tools/questionnaire-config-editor/index.html`.
2. Run:

   ```powershell
   cd MyQuestionnaireVR-2D
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-questionnaire-builder.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\publish-questionnaire-builder-github-pages.ps1
   ```

3. Confirm `questionnaire-builder/index.html` was regenerated.
4. Commit and push to `main`.
5. Wait for GitHub Pages to finish building, then verify:

   ```text
   https://georgefejer91.github.io/quest-2d-questionnaire-apps/questionnaire-builder/
   ```

   Prefer the repeatable validator:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\MyQuestionnaireVR-2D\tools\validate-hosted-questionnaire-builder.ps1
   ```

   It checks that the editable source HTML, staged `questionnaire-builder`
   HTML, and hosted Pages HTML have matching normalized hashes and contain the
   expected runner controls/endpoints.

Do not manually edit only the staged `questionnaire-builder/index.html` copy;
that creates drift.

## Validation Already Run

During publication, these checks passed:

- `validate-questionnaire-builder.ps1`
- `validate-hosted-questionnaire-builder.ps1`
- PowerShell parser checks for the connector/build/publish scripts
- Local companion smoke test:
  - public `/api/status`
  - token-authorized `/api/status`
  - protected endpoint returned `401` without token
  - CORS/Private-Network preflight returned the expected headers
  - offline-served HTML injected local URL and token
  - authorized `/api/dependency-status`
  - authorized `/api/save-config`
- GitHub Pages returned the expected builder page content after publication.

## Non-Negotiable Constraint

Offline and online GUI behavior must stay identical or near-identical. The only
expected difference is the online pairing step required to connect the hosted
page to the local companion.
