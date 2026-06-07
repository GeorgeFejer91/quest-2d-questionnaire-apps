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

There are two user-facing modes that must remain functionally aligned:

- Offline desktop mode: the user runs
  `MyQuestionnaireVR-2D/Start-QuestionnaireBuilderApp.cmd`. This starts the
  local companion service and opens the same HTML GUI in the local browser.
- Online connector mode: the user opens the hosted Pages GUI and runs
  `MyQuestionnaireVR-2D/Start-QuestionnaireBuilderOnlineConnector.cmd` locally.
  The local companion prints a pairing token; the user enters that token in the
  online GUI.

The hosted Pages site is intentionally static. It must not claim to directly
install software, write files, validate configs, or build APKs. Those actions
belong to the local companion at:

```text
http://127.0.0.1:8765
```

Privileged local actions require the `X-MQ-Builder-Token` header. The companion
generates the token locally on each PC. It is not tied to one machine, user
profile, or repository path.

`GET /api/status` is also the compatibility check. It advertises the companion
`apiVersion`, `receiptSchemaVersion`, and capabilities such as
`generate-apk-receipt`, `artifact-preview`, `workflow-receipt`, and
`runner-job-receipts` so the hosted GUI can warn when a user connects an older
local companion package.

Render preview thumbnails are fetched from the companion through
`GET /api/artifact-preview?path=...`. That route must stay token-protected,
CORS-limited, PNG-only, and constrained to generated artifact roots. Do not
turn it into a general local file browser.

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

Do not manually edit only the staged `questionnaire-builder/index.html` copy;
that creates drift.

## Validation Already Run

During publication, these checks passed:

- `validate-questionnaire-builder.ps1`
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
