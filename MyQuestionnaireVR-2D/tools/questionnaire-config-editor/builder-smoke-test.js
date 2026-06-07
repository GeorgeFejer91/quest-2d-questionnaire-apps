const fs = require("fs");
const path = require("path");
const vm = require("vm");

const root = path.resolve(__dirname, "..", "..");
const htmlPath = path.join(__dirname, "index.html");
const csvPath = path.join(root, "QuestionnaireConfigs", "examples", "two-item-slider-template.csv");
const outputDirArgIndex = process.argv.indexOf("--output-dir");
const outputDir = outputDirArgIndex >= 0 ? path.resolve(process.argv[outputDirArgIndex + 1] || "") : "";

function fail(message) {
  throw new Error(message);
}

function assert(condition, message) {
  if (!condition) {
    fail(message);
  }
}

function decodeAttribute(value) {
  return String(value || "")
    .replace(/&quot;/g, "\"")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">");
}

class Element {
  constructor(document, tagName, id = "") {
    this.document = document;
    this.tagName = tagName.toUpperCase();
    this.id = id;
    this.value = "";
    this.type = "";
    this.className = "";
    this.disabled = false;
    this.checked = false;
    this.children = [];
    this.listeners = {};
    this._innerHTML = "";
    this._textContent = "";
    if (id) {
      this.document.elements.set(id, this);
    }
  }

  set innerHTML(value) {
    this._innerHTML = String(value || "");
    this.children = [];
    const idRegex = /<([a-zA-Z0-9-]+)([^>]*)\bid="([^"]+)"([^>]*)>/g;
    let match;
    while ((match = idRegex.exec(this._innerHTML)) !== null) {
      const tagName = match[1];
      const attributes = `${match[2]} ${match[4]}`;
      const child = new Element(this.document, tagName, match[3]);
      const valueMatch = attributes.match(/\bvalue="([^"]*)"/);
      if (valueMatch) {
        child.value = decodeAttribute(valueMatch[1]);
      }
      child.checked = /\bchecked\b/.test(attributes);
      this.appendChild(child);
    }
  }

  get innerHTML() {
    return this._innerHTML;
  }

  set textContent(value) {
    this._textContent = String(value || "");
  }

  get textContent() {
    return this._textContent + this.children.map(child => child.textContent).join("");
  }

  appendChild(child) {
    this.children.push(child);
    return child;
  }

  addEventListener(type, listener) {
    this.listeners[type] = listener;
  }

  click() {
    if (this.listeners.click) {
      this.listeners.click({ target: this });
    }
  }
}

class FakeDocument {
  constructor(html) {
    this.elements = new Map();
    const idRegex = /<([a-zA-Z0-9-]+)([^>]*)\bid="([^"]+)"([^>]*)>/g;
    let match;
    while ((match = idRegex.exec(html)) !== null) {
      const element = new Element(this, match[1], match[3]);
      const attributes = `${match[2]} ${match[4]}`;
      const valueMatch = attributes.match(/\bvalue="([^"]*)"/);
      if (valueMatch) {
        element.value = decodeAttribute(valueMatch[1]);
      }
      element.checked = /\bchecked\b/.test(attributes);
    }
  }

  getElementById(id) {
    const element = this.elements.get(id);
    if (!element) {
      fail(`Missing fake DOM element: ${id}`);
    }
    return element;
  }

  createElement(tagName) {
    return new Element(this, tagName);
  }

  addEventListener() {
  }
}

function loadEditor() {
  const html = fs.readFileSync(htmlPath, "utf8");
  const scriptMatch = html.match(/<script>([\s\S]*?)<\/script>/);
  assert(scriptMatch, "Could not find inline editor script.");

  const document = new FakeDocument(html);
  const context = {
    console,
    document,
    structuredClone,
    navigator: { clipboard: { writeText: async () => undefined } },
    Blob: class Blob {},
    URL: { createObjectURL: () => "blob:fake", revokeObjectURL: () => undefined },
    FileReader: class FileReader {},
    setTimeout,
    clearTimeout
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(`${scriptMatch[1]}\nthis.__api = { buildConfig, validate, qualityReport, applyCsvText, applyTriggerCatalog, applyQuestionnaireFirstDefaults, refresh, buildExperimentBlockRegistry, buildChainPlan, directHandoffWorkflowOptions, workflowValidationPayload, runHeadsetSequenceWithApp, physicalGatePacketPayloadFromEvidence, manualSignoffReceiptText, physicalGatePacketReceiptText };`, context, {
    filename: htmlPath
  });
  return { context, document, html };
}

function assertOrderedText(text, tokens, label) {
  let offset = -1;
  tokens.forEach(token => {
    const index = text.indexOf(token, offset + 1);
    assert(index > offset, `${label} should contain ${token} after offset ${offset}.`);
    offset = index;
  });
}

const { context, document, html } = loadEditor();
const initial = context.__api.buildConfig();
const initialQuality = context.__api.qualityReport(initial);
assert(initial.schemaVersion === "my-questionnaire-vr.config.v1", "Default schema version mismatch.");
assert(initial.questionnaireId === "viscereality-maia2", "Default questionnaire id mismatch.");
assert(initial.blocks.some(block => block.id === "maia2"), "Default config should include MAIA-2.");
assert(initial.blocks.some(block => block.id === "pictographic"), "Default config should include pictographic scales.");
assert(initial.chainDefaults.finishBehavior === "resumeCaller", "Default chain finish behavior mismatch.");
assert(initial.experimentBlockRegistry.schemaVersion === "viscereality.chainlink.block-registry.v1", "Default block registry schema mismatch.");
assert(initial.experimentBlockRegistry.blocks[0].number === "001", "Default registry should start at block 001.");
assert(initial.experimentBlockRegistry.blocks.some(block => block.questionnaireMode === "baseline"), "Default registry should include a baseline questionnaire block.");
assert(initial.experimentBlockRegistry.blocks.some(block => block.questionnaireMode === "pictographic"), "Default registry should include pictographic sampling blocks.");
assert(initial.experimentBlockRegistry.blocks.some(block => block.package === "com.Viscereality.ViscerealityPeriPersonalSpaceRight"), "Default registry should target the Peripersonal Space Right package.");
assert(initial.experimentBlockRegistry.controllerTriggerButton === "auto-unused-non-breath-tracking", "Default ChainLink trigger button should let Unity choose the non-breath-tracking controller.");
assert(initial.experimentBlockRegistry.blocks.some(block => block.type === "apk" && block.extras && block.extras["mq.controllerButton"] === "auto-unused-non-breath-tracking"), "Scenario APK blocks should receive the auto controller-button policy.");
const initialChainPlan = context.__api.buildChainPlan(initial);
assert(initialChainPlan.schemaVersion === "viscereality.chainlink.plan.v1", "ChainLink plan schema mismatch.");
assert(initialChainPlan.blockRegistry.blocks.length === initial.experimentBlockRegistry.blocks.length, "ChainLink plan should embed the full registered block list.");
assert(initialQuality.status === "fail", "Default questionnaire should be blocked until a trigger catalog is loaded.");
assert(initialQuality.issues.some(issue => issue.text.includes("Load an APK trigger catalog")), "Default quality report should explain the APK-first gate.");
assert(document.getElementById("generatorCommand").textContent.includes("generate-questionnaire-apk.ps1"), "Generator command was not rendered.");
assert(document.getElementById("downloadQualityButton"), "Quality report download button was not rendered.");
assert(document.getElementById("downloadBlockRegistryButton"), "Block registry download button was not rendered.");
assert(document.getElementById("downloadChainPlanButton"), "Chain plan download button was not rendered.");
assert(document.getElementById("headsetSequenceAppButton"), "Headset sequence button was not rendered.");
assert(typeof context.__api.runHeadsetSequenceWithApp === "function", "Headset sequence runner should be exposed.");
assert(typeof context.__api.physicalGatePacketPayloadFromEvidence === "function", "Physical packet payload helper should be exposed.");
assert(html.includes("operator-guardrail-receipts"), "Hosted/offline GUI should require the operator guardrail receipt capability.");
const sequenceSource = context.__api.runHeadsetSequenceWithApp.toString();
assertOrderedText(sequenceSource, [
  "\"Save config\"",
  "\"/api/save-config\"",
  "\"Validate config\"",
  "\"/api/validate-config\"",
  "\"Generate APK and local render\"",
  "\"/api/generate-apk\"",
  "runTests: true",
  "renderPreview: true",
  "\"Detect Quest\"",
  "\"/api/quest-readiness\"",
  "\"Install APK on Quest\"",
  "\"/api/install-apk\"",
  "\"Run replay/export\"",
  "\"/api/quest-replay\"",
  "\"/api/2d-first-launcher\"",
  "\"/api/direct-handoff\"",
  "\"Audit readiness\"",
  "\"/api/handoff-readiness-audit\"",
  "\"Prepare physical packet\"",
  "\"/api/physical-gate-packet\"",
  "physicalGatePacketPayloadFromEvidence(latestData)"
], "Headset sequence");
assert(sequenceSource.includes("payload.dryRun = true"), "Headset sequence should dry-run launch gates in preflight mode.");
assert(sequenceSource.includes("payload.skipInstall = true"), "Headset sequence should skip install inside preflight launch gates.");
assert(sequenceSource.includes("preflightOnly ? false : directHandoffWakeBeforeReadiness()"), "Headset sequence should ignore wake-before-readiness in preflight mode.");
document.getElementById("workflowQuestSerial").value = "QUEST-SMOKE-001";
const auditPacketPayload = context.__api.physicalGatePacketPayloadFromEvidence({
  auditReceipt: { artifacts: { summaryPath: "C:\\artifacts\\audit-summary.json" } }
});
assert(auditPacketPayload.questSerial === "QUEST-SMOKE-001", "Physical packet payload should include the current Quest serial.");
assert(auditPacketPayload.auditSummaryPath === "C:\\artifacts\\audit-summary.json", "Physical packet payload should prefer the visible audit summary.");
assert(!Object.prototype.hasOwnProperty.call(auditPacketPayload, "companionSummaryPath"), "Visible audit payload should not fall back to companion summary discovery.");
const priorPacketPayload = context.__api.physicalGatePacketPayloadFromEvidence({
  physicalGatePacketReceipt: { artifacts: { auditSummaryPath: "C:\\artifacts\\packet-audit-summary.json" } }
});
assert(priorPacketPayload.auditSummaryPath === "C:\\artifacts\\packet-audit-summary.json", "Physical packet payload should reuse the visible packet's audit summary.");
const companionPacketPayload = context.__api.physicalGatePacketPayloadFromEvidence({
  endToEndReceipt: { artifacts: { summaryPath: "C:\\artifacts\\companion-summary.json" } }
});
assert(companionPacketPayload.companionSummaryPath === "C:\\artifacts\\companion-summary.json", "Physical packet payload should fall back to the visible companion workflow summary.");
const manualGuardrailText = context.__api.manualSignoffReceiptText({
  manualSignoffReceipt: {
    status: "pending-operator-signoff",
    checks: {
      instructionsWritten: true,
      operatorTemplateWritten: true,
      stopConditionGuardrailsPresent: true
    },
    counts: {},
    artifacts: {}
  }
});
assert(manualGuardrailText.includes("controller dialog"), "Manual signoff receipt should show the controller-dialog stop condition.");
assert(manualGuardrailText.includes("start gate"), "Manual signoff receipt should show the Unity start-gate stop condition.");
assert(manualGuardrailText.includes("frozen video"), "Manual signoff receipt should show the frozen-video stop condition.");
assert(manualGuardrailText.includes("Meta/ADB recovery"), "Manual signoff receipt should show the no Meta/ADB recovery stop condition.");
const physicalGuardrailText = context.__api.physicalGatePacketReceiptText({
  physicalGatePacketReceipt: {
    status: "ready-for-operator",
    checks: {
      runbookWritten: true,
      manualSignoffTemplateWritten: true,
      operatorGuardrailsPresent: true
    },
    counts: { requirements: 12, proven: 9, physicalPending: 3, failedOrMissing: 0 },
    remainingGateCount: 3,
    physicalQuestProductPathPending: true,
    artifacts: {}
  }
});
assert(physicalGuardrailText.includes("2D-first start gate"), "Physical packet receipt should show the 2D-first start-gate guardrail.");
assert(physicalGuardrailText.includes("no controller dialog"), "Physical packet receipt should show the no-controller-dialog guardrail.");
assert(physicalGuardrailText.includes("no Meta/ADB recovery"), "Physical packet receipt should show the no Meta/ADB recovery guardrail.");
assert(physicalGuardrailText.includes("video resumes"), "Physical packet receipt should show the video-resume guardrail.");
assert(document.getElementById("pipelineCommands").textContent.includes("quest-validate.ps1"), "Quest validation command was not rendered.");
assert(document.getElementById("pipelineCommands").textContent.includes("render-questionnaire-visuals.ps1"), "Foreground render command was not rendered.");
assert(document.getElementById("pipelineCommands").textContent.includes("quest-chain-validate.ps1"), "Quest chain validation command was not rendered.");
assert(document.getElementById("pipelineCommands").textContent.includes("quest-broker-chain-validate.ps1"), "Quest broker chain validation command was not rendered.");
assert(document.getElementById("pipelineCommands").textContent.includes("validate-builder-to-quest-workflow.ps1"), "Full builder-to-Quest workflow command was not rendered.");
assert(document.getElementById("directHandoffPreflightOnly").checked === true, "Direct handoff preflight toggle should default on.");
assert(document.getElementById("directHandoffWakeBeforeReadiness").checked === false, "Wake-before-readiness toggle should default off.");
const defaultWorkflowDirect = context.__api.directHandoffWorkflowOptions();
const defaultWorkflowPayload = context.__api.workflowValidationPayload();
assert(defaultWorkflowDirect.preflightOnly === true, "Default workflow direct handoff mode should be preflight.");
assert(defaultWorkflowDirect.runDirect === true, "Default workflow should include direct handoff preflight.");
assert(defaultWorkflowDirect.liveTrials === false, "Default workflow should not request live direct handoff trials.");
assert(defaultWorkflowDirect.trialCount === 1, "Default workflow preflight should clamp to one direct handoff trial.");
assert(defaultWorkflowDirect.waitForReadySeconds === 0, "Default workflow preflight should not wait for product-path readiness.");
assert(defaultWorkflowDirect.wakeBeforeReadiness === false, "Default workflow preflight should not wake before readiness.");
assert(defaultWorkflowPayload.runQuestDirectHandoff === true, "Workflow payload should request direct handoff when preflight is enabled.");
assert(defaultWorkflowPayload.dryRunQuestDirectHandoff === true, "Workflow payload should dry-run direct handoff by default.");
assert(defaultWorkflowPayload.skipInstall === true, "Workflow payload should skip install for direct handoff preflight.");
assert(defaultWorkflowPayload.questTrials === 1, "Workflow payload should send one dry-run direct handoff trial.");
assert(defaultWorkflowPayload.waitForReadySeconds === 0, "Workflow payload should send zero readiness wait for dry-run preflight.");
assert(defaultWorkflowPayload.wakeBeforeReadiness === false, "Workflow payload should keep wake-before-readiness off for preflight.");
document.getElementById("directHandoffPreflightOnly").checked = false;
document.getElementById("workflowDirectHandoff").checked = true;
document.getElementById("directHandoffTrials").value = "8";
document.getElementById("directHandoffWaitSeconds").value = "60";
document.getElementById("directHandoffWakeBeforeReadiness").checked = true;
const liveWorkflowDirect = context.__api.directHandoffWorkflowOptions();
const liveWorkflowPayload = context.__api.workflowValidationPayload();
assert(liveWorkflowDirect.preflightOnly === false, "Live workflow should clear preflight mode.");
assert(liveWorkflowDirect.liveTrials === true, "Live workflow should mark direct handoff trials requested.");
assert(liveWorkflowDirect.runReadiness === true, "Live workflow should require Quest readiness.");
assert(liveWorkflowDirect.wakeBeforeReadiness === true, "Live workflow should preserve wake-before-readiness when requested.");
assert(liveWorkflowPayload.dryRunQuestDirectHandoff === false, "Live workflow payload should not dry-run direct handoff.");
assert(liveWorkflowPayload.skipInstall === false, "Live workflow payload should not skip install.");
assert(liveWorkflowPayload.questTrials === 8, "Live workflow payload should keep bounded trial count.");
assert(liveWorkflowPayload.waitForReadySeconds === 60, "Live workflow payload should keep readiness wait.");
assert(liveWorkflowPayload.wakeBeforeReadiness === true, "Live workflow payload should send wake-before-readiness when requested.");
document.getElementById("directHandoffPreflightOnly").checked = true;
document.getElementById("workflowDirectHandoff").checked = false;
document.getElementById("directHandoffWakeBeforeReadiness").checked = false;

context.__api.applyTriggerCatalog({
  schemaVersion: "mq.quest_questionnaire_trigger_catalog.v1",
  catalogVersion: "1.0.0",
  scenarioId: "demo-scenario",
  package: "com.example.scenario",
  activity: "com.example.scenario.MainActivity",
  label: "Demo scenario",
  triggers: [
    { triggerId: "after_intro", label: "After intro", recommendedMode: "pictographic" },
    { triggerId: "after_task", label: "After task", recommendedMode: "slider" }
  ]
}, "demo-scenario.apk");

const triggered = context.__api.buildConfig();
const triggeredQuality = context.__api.qualityReport(triggered);
assert(triggered.chainDefaults.callerPackage === "com.example.scenario", "Catalog package should become the caller package.");
assert(triggered.triggerQuestionnaireMapping.triggers.length === 2, "Trigger catalog should produce two trigger mappings.");
assert(triggered.experimentBlockRegistry.blocks.length === 2, "Trigger catalog should produce one registry block per enabled trigger.");
assert(triggered.experimentBlockRegistry.blocks.every(block => block.type === "questionnaire"), "Manifest registry should contain questionnaire blocks.");
assert(triggered.experimentBlockRegistry.blocks.every(block => block.trigger.type === "apkManifestTrigger"), "Manifest blocks should use APK trigger events.");
assert(triggeredQuality.status === "pass", "Catalog-backed questionnaire should pass quality report.");
assert(triggeredQuality.issueCounts.warning >= 1, "Catalog-backed source questionnaire should warn about moderate headset burden.");
document.getElementById("downloadQualityButton").click();
document.getElementById("downloadBlockRegistryButton").click();
document.getElementById("downloadChainPlanButton").click();

context.__api.applyTriggerCatalog({
  schemaVersion: "mq.quest_questionnaire_trigger_catalog.v1",
  catalogVersion: "1.0.0",
  scenarioId: "awe-of-the-great-dictator",
  package: "org.questionnairebuilder.stimulusdemo",
  activity: "org.questionnairebuilder.stimulusdemo.StimulusUnityPlayerGameActivity",
  label: "Questionnaire Stimulus Builder Demo",
  triggers: [
    { triggerId: "trigger_1_launch_questionnaire", label: "Trigger 1: before video", recommendedMode: "demographics" },
    { triggerId: "trigger_2_video_complete", label: "Trigger 2: after video", recommendedMode: "temporalTracer" }
  ]
}, "awe-great-dictator.apk");

const handoff = context.__api.buildConfig();
const handoffQuality = context.__api.qualityReport(handoff);
const handoffPlan = context.__api.buildChainPlan(handoff);
assert(handoff.triggerQuestionnaireMapping.triggers.length === 2, "Handoff demo catalog should produce two trigger mappings.");
assert(handoff.triggerQuestionnaireMapping.triggers[0].questionnaireMode === "demographics", "Trigger 1 should map to demographics.");
assert(handoff.triggerQuestionnaireMapping.triggers[1].questionnaireMode === "temporalTracer", "Trigger 2 should map to the temporal tracer.");
assert(handoff.experimentBlockRegistry.blocks.some(block => block.type === "temporalTracer"), "Handoff registry should include a temporal tracer block.");
assert(handoffPlan.steps.some(step => step.type === "temporalTracer" && step.action === "org.viscereality.temporaltracer2d.RUN"), "Handoff chain plan should launch the temporal tracer action.");
assert(handoffQuality.status === "pass", "Handoff demo config should pass quality report.");

context.__api.applyQuestionnaireFirstDefaults();
const twoDStart = context.__api.buildConfig();
const twoDStartQuality = context.__api.qualityReport(twoDStart);
assert(twoDStart.chainDefaults.startMode === "questionnaireFirst", "2D-first preset should mark questionnaire-first start mode.");
assert(twoDStart.chainDefaults.finishBehavior === "openNext", "2D-first preset should open the Unity APK after demographics.");
assert(twoDStart.chainDefaults.questionnaireMode === "demographics", "2D-first preset should run demographics from a normal launcher start.");
assert(twoDStart.chainDefaults.triggerId === "trigger_1_launch_questionnaire", "2D-first preset should reuse the first demographics trigger id.");
assert(twoDStart.chainDefaults.nextPackage === "org.questionnairebuilder.stimulusdemo", "2D-first preset should target the Unity package as nextPackage.");
assert(twoDStart.experimentBlockRegistry.blocks.every(block => block.extras && block.extras["mq.finishBehavior"] === "resumeCaller"), "Unity-triggered blocks should still return to Unity in 2D-first mode.");
assert(twoDStartQuality.status === "pass", "2D-first handoff demo config should pass quality report.");

const csv = fs.readFileSync(csvPath, "utf8");
context.__api.applyCsvText(csv, "two-item-slider-template.csv");
const imported = JSON.parse(document.getElementById("preview").textContent);
const slider = imported.blocks.find(block => block.id === "viscereality");
const validation = context.__api.validate(imported);
const importedQuality = context.__api.qualityReport(imported);

assert(imported.questionnaireId === "demo-slider", "CSV questionnaire id was not applied.");
assert(!imported.blocks.some(block => block.id === "maia2"), "Slider-only CSV import should omit MAIA-2.");
assert(!imported.blocks.some(block => block.id === "pictographic"), "Slider-only CSV import should omit pictographic scales.");
assert(imported.blocks.map(block => block.id).join(">") === "demographics>viscereality>end", "Slider-only CSV import block order mismatch.");
assert(slider.expectedItemCount === 2, "CSV slider expected count was not applied.");
assert(slider.languages.English.items.length === 2, "CSV English slider items were not imported.");
assert(slider.languages.Deutsch.items.length === 2, "CSV Deutsch slider items were not imported.");
assert(document.getElementById("generatorCommand").textContent.includes(".\\QuestionnaireConfigs\\demo-slider.config.json"), "CSV generator command was not updated.");
assert(document.getElementById("pipelineCommands").textContent.includes(".\\Builds\\demo-slider-1.0.0.apk"), "CSV APK path was not updated.");
assert(validation.some(issue => issue.level === "ok"), "Imported config did not pass local editor validation.");
assert(importedQuality.status === "pass", "Imported config did not pass builder quality report.");
assert(importedQuality.issueCounts.error === 0, "Imported config should have no builder quality errors.");
assert(importedQuality.counts.slider === 2, "Imported quality report slider count mismatch.");

const duplicate = JSON.parse(JSON.stringify(imported));
const duplicateSlider = duplicate.blocks.find(block => block.id === "viscereality");
duplicateSlider.languages.English.items[1] = duplicateSlider.languages.English.items[0];
const duplicateQuality = context.__api.qualityReport(duplicate);
assert(duplicateQuality.status === "fail", "Duplicate item quality report should fail.");
assert(duplicateQuality.issues.some(issue => issue.text.includes("duplicates another item")), "Duplicate item issue was not reported.");

const summary = {
  status: "pass",
  defaultQuestionnaireId: initial.questionnaireId,
  defaultQualityStatus: initialQuality.status,
  defaultQualityWarnings: initialQuality.issueCounts.warning,
  handoffQuestionnaireId: handoff.questionnaireId,
  handoffQualityStatus: handoffQuality.status,
  handoffTriggerCount: handoff.triggerQuestionnaireMapping.triggers.length,
  handoffRegisteredBlocks: handoff.experimentBlockRegistry.blocks.length,
  twoDStartQualityStatus: twoDStartQuality.status,
  twoDStartFinishBehavior: twoDStart.chainDefaults.finishBehavior,
  twoDStartNextPackage: twoDStart.chainDefaults.nextPackage,
  importedQuestionnaireId: imported.questionnaireId,
  importedMode: "slider-only",
  importedSliderItems: slider.expectedItemCount,
  importedQualityStatus: importedQuality.status,
  importedQualityErrors: importedQuality.issueCounts.error,
  importedQualityWarnings: importedQuality.issueCounts.warning,
  duplicateGuardrailStatus: duplicateQuality.status,
  qualityReportDownloadAction: "pass",
  blockRegistryDownloadAction: "pass",
  chainPlanDownloadAction: "pass",
  headsetSequenceAction: "pass",
  headsetSequenceOrderAction: "pass",
  physicalGatePacketPayloadAction: "pass",
  workflowPreflightPayloadAction: "pass",
  defaultRegisteredBlocks: initial.experimentBlockRegistry.blocks.length,
  pipelineCommands: 7
};

if (outputDir) {
  fs.mkdirSync(outputDir, { recursive: true });
  const initialConfigPath = path.join(outputDir, "viscereality-maia2.config.json");
  const importedConfigPath = path.join(outputDir, "demo-slider.config.json");
  const handoffConfigPath = path.join(outputDir, "awe-great-dictator-handoff.config.json");
  const handoffQualityPath = path.join(outputDir, "awe-great-dictator-handoff.quality-report.json");
  const handoffChainPlanPath = path.join(outputDir, "awe-great-dictator-handoff.chainlink-plan.json");
  const twoDStartConfigPath = path.join(outputDir, "awe-great-dictator-2d-first.config.json");
  const twoDStartQualityPath = path.join(outputDir, "awe-great-dictator-2d-first.quality-report.json");
  const summaryPath = path.join(outputDir, "builder-smoke-summary.json");
  const importedQualityPath = path.join(outputDir, "demo-slider.quality-report.json");
  const initialChainPlanPath = path.join(outputDir, "viscereality-maia2.chainlink-plan.json");
  fs.writeFileSync(initialConfigPath, `${JSON.stringify(initial, null, 2)}\n`, "utf8");
  fs.writeFileSync(initialChainPlanPath, `${JSON.stringify(initialChainPlan, null, 2)}\n`, "utf8");
  fs.writeFileSync(handoffConfigPath, `${JSON.stringify(handoff, null, 2)}\n`, "utf8");
  fs.writeFileSync(handoffQualityPath, `${JSON.stringify(handoffQuality, null, 2)}\n`, "utf8");
  fs.writeFileSync(handoffChainPlanPath, `${JSON.stringify(handoffPlan, null, 2)}\n`, "utf8");
  fs.writeFileSync(twoDStartConfigPath, `${JSON.stringify(twoDStart, null, 2)}\n`, "utf8");
  fs.writeFileSync(twoDStartQualityPath, `${JSON.stringify(twoDStartQuality, null, 2)}\n`, "utf8");
  fs.writeFileSync(importedConfigPath, `${JSON.stringify(imported, null, 2)}\n`, "utf8");
  fs.writeFileSync(importedQualityPath, `${JSON.stringify(importedQuality, null, 2)}\n`, "utf8");
  summary.initialConfig = initialConfigPath;
  summary.initialChainPlan = initialChainPlanPath;
  summary.handoffConfig = handoffConfigPath;
  summary.handoffQualityReport = handoffQualityPath;
  summary.handoffChainPlan = handoffChainPlanPath;
  summary.twoDStartConfig = twoDStartConfigPath;
  summary.twoDStartQualityReport = twoDStartQualityPath;
  summary.importedConfig = importedConfigPath;
  summary.importedQualityReport = importedQualityPath;
  summary.summary = summaryPath;
  fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, "utf8");
}

console.log(JSON.stringify(summary, null, 2));
