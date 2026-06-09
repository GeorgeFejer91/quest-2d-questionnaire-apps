# Handoff: 2026-06-09 Two-APK V2 Builder State

This handoff captures the current project state before pushing to GitHub so the
work can continue on another PC.

## Product Direction Locked In

- The product path is exactly two APKs:
  - one generated 2D questionnaire APK,
  - one immersive Unity/stimulus APK.
- The participant starts the generated questionnaire APK from Meta Home.
- The questionnaire APK runs Block 1, saves state, launches Unity, waits in the
  background, and resumes the next configured block after Unity emits a passive
  trigger.
- Unity is passive. It may show stimulus content and emit `mq.triggerId` plus
  inert session/source/timing metadata. It must not choose questionnaire type,
  block order, scoring, participant state, exports, next package, or next
  activity.
- Direct Unity launches without fresh questionnaire-supplied
  `mq.triggerReceiver*` extras must not perform questionnaire handoff.

## Implemented Since The V2 Pivot

- Added the questionnaire-owned trigger protocol docs and constraints:
  - `docs/minimal-apk-trigger-protocol.md`
  - `docs/minimal-trigger-integration-guide.md`
  - `docs/trigger-transport-decision-record.md`
  - `For-AI/PROJECT_CONSTRAINTS.md`
  - `MyQuestionnaireVR-2D/For-AI/questionnaire-builder-gui-constraints.md`
- Added passive trigger schemas/examples:
  - `MyQuestionnaireVR-2D/QuestionnaireConfigs/trigger-catalog.schema.json`
  - `MyQuestionnaireVR-2D/QuestionnaireConfigs/trigger-questionnaire-mapping.schema.json`
  - `MyQuestionnaireVR-2D/QuestionnaireConfigs/examples/scenario-trigger-catalog.example.json`
  - `MyQuestionnaireVR-2D/QuestionnaireConfigs/examples/lsl-trigger.example.json`
- Added a concrete generated questionnaire config for the real three-circle
  Unity demo:
  - `MyQuestionnaireVR-2D/QuestionnaireConfigs/examples/quest-questionnaire-three-circle-protocol-demo.config.json`
- Added passive validation scripts:
  - `MyQuestionnaireVR-2D/tools/validate-passive-trigger-protocol.ps1`
  - `MyQuestionnaireVR-2D/tools/validate-two-apk-pair.ps1`
  - `MyQuestionnaireVR-2D/tools/validate-minimal-apk-trigger-protocol.ps1`
  - `MyQuestionnaireVR-2D/tools/quest-minimal-apk-trigger-protocol-validate.ps1`
  - `MyQuestionnaireVR-2D/tools/new-two-apk-live-validation-packet.ps1`
- Added the copy-first Unity passive trigger kit:
  - `MyQuestionnaireVR-2D/tools/unity/QuestQuestionnairePassiveTriggerBridge.cs`
  - `MyQuestionnaireVR-2D/tools/unity/passive-trigger-kit/`
- Updated the public three-circle Unity demo so it is a real immersive Unity
  APK with passive trigger catalog/bridge behavior:
  - green circle -> `trigger_1_complete`
  - blue circle -> `trigger_2_complete`
  - red circle -> `trigger_3_complete`
- Removed the public demo's legacy `org.questquestionnaire.CHAIN_COMMAND`
  activity filter. The questionnaire launches Unity explicitly by
  package/activity and supplies the trigger receiver extras.
- Added `QuestQuestionnaireUnityActivity.java` with `setIntent(intent)` in
  `onNewIntent()` so reused Unity activities do not keep stale receiver extras.
- Updated the builder GUI so local/scanned APKs, not GitHub catalog-only data,
  are the install source of truth. Trigger count creates Block 1 plus one return
  block per passive trigger.
- Added a local companion endpoint and developer/operator GUI control:
  - `POST /api/two-apk-live-packet`
  - capability `two-apk-live-validation-packet`
  - button text `Prepare two-APK packet`
  - receipt `twoApkLivePacketReceipt`
- Fixed the GUI minimal-protocol payload to use the actual staged/scanned Unity
  APK path instead of an undefined variable.

## Latest Local Validation Evidence

The current local companion was refreshed on `http://127.0.0.1:8776/` with
token `codex-online-test-token` for this machine session. Do not treat that
token as portable; it is a local runtime value.

Passed checks in this state:

- PowerShell parse check:
  - `MyQuestionnaireVR-2D/tools/start-questionnaire-builder-app.ps1`
- Builder smoke/GUI stress:
  - `MyQuestionnaireVR-2D/tools/validate-questionnaire-builder.ps1`
  - output folder: `output/validate-questionnaire-builder-two-apk-packet/`
  - status: pass
- Passive trigger protocol:
  - `MyQuestionnaireVR-2D/tools/validate-passive-trigger-protocol.ps1`
  - status: pass, 149 checks, 0 failed
- Two-APK pair audit:
  - `MyQuestionnaireVR-2D/tools/validate-two-apk-pair.ps1`
  - status: pass, 27 checks, 0 failed
- Unity input modality guardrail:
  - `MyQuestionnaireVR-2D/tools/validate-unity-input-modality.ps1`
  - status: pass, 22 checks, 0 failed
- Local companion runtime endpoint:
  - `POST /api/two-apk-live-packet`
  - status: `ready-for-operator`
  - summary:
    `MyQuestionnaireVR-2D/artifacts/two-apk-live-validation-packet/builder-two-apk-live-validation-packet-20260609T061144Z/two-apk-live-validation-packet-summary.json`
  - pair audit: pass
  - dry-run preflight: pass
  - operator signoff: pending
- Evidence bundle route:
  - output: `output/two-apk-live-packet-evidence-bundle.zip`
  - status: ok
  - contained 21 linked evidence entries
- In-app browser DOM check:
  - current URL: `http://127.0.0.1:8776/`
  - title: `Quest 2D Panel Questionnaire Builder`
  - connector URL filled: `http://127.0.0.1:8776`
  - token filled: yes
  - `Prepare two-APK packet` control present in developer/operator surface

Published/staged artifacts were regenerated locally:

- `MyQuestionnaireVR-2D/Builds/QuestionnaireBuilder.zip`
  - SHA256 `2293AA11C742538B1C1592A55B1C5F0EE754179897E1409D9B1E9D87953F0981`
- `questionnaire-builder/` staged Pages copy was regenerated.

Important packaging note:

- The generated `questionnaire-builder/QuestionnaireBuilder.zip` is about
  193 MB and the staged `aesthetic-chills-1-trigger-demo.apk` is about 181 MB.
  These exceed GitHub's normal single-file limit and should not be committed to
  the source repo without a deliberate Git LFS/release-asset plan. Regenerate
  them locally with `publish-questionnaire-builder.ps1` instead.

## Still Missing Before Calling The Product Complete

Physical Quest product-path validation is still pending. Dry-run packets and
software audits do not close these gates.

Required live headset gates:

- Install the generated questionnaire APK and the immersive Unity APK on an
  explicit Quest serial.
- Start the generated questionnaire APK from Meta Home.
- Do not start Unity from Meta Home.
- Confirm Block 1 displays, saves, and launches Unity.
- Confirm Unity appears as a fully immersive foreground app, not a 2D panel.
- Confirm no Horizon controller-required launch dialog appears for generic
  demos.
- Fire the Unity trigger from within the foreground immersive Unity app.
- Confirm the questionnaire resumes the mapped next block from its own protocol
  state.
- Confirm repeated triggers do not replay completed blocks unless repeatable
  behavior is explicitly configured.
- Pull exports from the generated questionnaire APK directory and verify
  session/block/export indexing.
- Confirm no Meta menu navigation, ADB foreground switching, force-stop, or
  package killing was used to repair the flow after participant start.
- Confirm Unity does not remain frozen after questionnaire return in any
  product-path trial.

Recommended next validation order:

1. Re-run the local software preflight after pulling on the next PC:
   `powershell -NoProfile -ExecutionPolicy Bypass -File MyQuestionnaireVR-2D/tools/validate-questionnaire-builder.ps1 -ProjectPath MyQuestionnaireVR-2D`
2. Regenerate the builder package locally if needed:
   `powershell -NoProfile -ExecutionPolicy Bypass -File MyQuestionnaireVR-2D/tools/publish-questionnaire-builder.ps1 -ProjectPath MyQuestionnaireVR-2D`
3. Build or verify the real three-circle Unity APK:
   `example-scenario-apk/unity-project/three-circle-trigger-demo/build-android-shortpath.ps1`
4. Prepare a fresh two-APK packet on that machine:
   `powershell -NoProfile -ExecutionPolicy Bypass -File MyQuestionnaireVR-2D/tools/new-two-apk-live-validation-packet.ps1 -ProjectPath MyQuestionnaireVR-2D`
5. Run the physical Quest live gate only with explicit operator intent:
   `powershell -NoProfile -ExecutionPolicy Bypass -File MyQuestionnaireVR-2D/tools/quest-minimal-apk-trigger-protocol-validate.ps1 -ProjectPath MyQuestionnaireVR-2D -RunLive -Serial <quest-serial> -SkipQuestionnaireBuild`
6. Fill and validate the generated `operator-signoff.json` only after the real
   headset observations are complete.

## Git Push Scope

For portability, commit source, docs, configs, scripts, Unity project source,
small fixtures, and staged `questionnaire-builder/index.html`/manifest updates.
Do not commit generated `output/`, `.codex-remote-attachments/`, or oversized
untracked staged package assets unless the user explicitly switches to Git LFS
or release assets.
