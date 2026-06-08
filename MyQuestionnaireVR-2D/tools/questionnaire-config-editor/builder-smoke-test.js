const fs = require("fs");
const path = require("path");
const vm = require("vm");

const root = path.resolve(__dirname, "..", "..");
const repoRoot = path.resolve(root, "..");
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
    this.body = {
      classes: new Set(),
      classList: {
        add: (...names) => names.forEach(name => this.body.classes.add(name)),
        contains: name => this.body.classes.has(name)
      }
    };
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
    Blob,
    TextEncoder,
    TextDecoder,
    atob,
    btoa,
    fetch: async (url, options = {}) => {
      if (String(url).includes("/api/stage-scenario-apk")) {
        const payload = options.body ? JSON.parse(options.body) : {};
        return {
          ok: true,
          text: async () => JSON.stringify({
            status: "ok",
            fileName: payload.fileName || "scenario.apk",
            apk: `C:\\staged\\${payload.fileName || "scenario.apk"}`,
            bytes: payload.base64 ? Buffer.from(payload.base64, "base64").length : 0
          })
        };
      }
      return {
        ok: false,
        status: 404,
        text: async () => JSON.stringify({ status: "error", message: `Unhandled fetch ${url}` })
      };
    },
    URL: { createObjectURL: () => "blob:fake", revokeObjectURL: () => undefined },
    FileReader: class FileReader {},
    setTimeout,
    clearTimeout
  };
  context.window = context;
  vm.createContext(context);
  vm.runInContext(`${scriptMatch[1]}\nthis.__api = { buildConfig, validate, qualityReport, applyCsvText, csvTemplateText, downloadCsvTemplate, pictographicZipManifestText, downloadPictographicZipTemplate, loadConfig, applyTriggerCatalog, applyQuestionnaireFirstDefaults, refresh, buildExperimentBlockRegistry, buildChainPlan, loadTriggerCatalogFile, directHandoffWorkflowOptions, workflowValidationPayload, runHeadsetSequenceWithApp, physicalGatePacketPayloadFromEvidence, evidenceBundleSummaryPath, auditReceiptText, manualSignoffReceiptText, physicalGatePacketReceiptText, applyHostedFinalProductMode, appBackendRequiredCapabilities };`, context, {
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

function uint16(value) {
  return [value & 0xff, (value >> 8) & 0xff];
}

function uint32(value) {
  return [value & 0xff, (value >> 8) & 0xff, (value >> 16) & 0xff, (value >> 24) & 0xff];
}

function storedZip(entries) {
  const encoder = new TextEncoder();
  const chunks = [];
  const central = [];
  let offset = 0;
  Object.entries(entries).forEach(([name, text]) => {
    const nameBytes = encoder.encode(name);
    const dataBytes = encoder.encode(text);
    const localHeader = new Uint8Array([
      ...uint32(0x04034b50),
      ...uint16(20),
      ...uint16(0),
      ...uint16(0),
      ...uint16(0),
      ...uint16(0),
      ...uint32(0),
      ...uint32(dataBytes.length),
      ...uint32(dataBytes.length),
      ...uint16(nameBytes.length),
      ...uint16(0)
    ]);
    chunks.push(localHeader, nameBytes, dataBytes);
    central.push({
      nameBytes,
      size: dataBytes.length,
      offset
    });
    offset += localHeader.length + nameBytes.length + dataBytes.length;
  });
  const centralOffset = offset;
  central.forEach(entry => {
    const centralHeader = new Uint8Array([
      ...uint32(0x02014b50),
      ...uint16(20),
      ...uint16(20),
      ...uint16(0),
      ...uint16(0),
      ...uint16(0),
      ...uint16(0),
      ...uint32(0),
      ...uint32(entry.size),
      ...uint32(entry.size),
      ...uint16(entry.nameBytes.length),
      ...uint16(0),
      ...uint16(0),
      ...uint16(0),
      ...uint16(0),
      ...uint32(0),
      ...uint32(entry.offset)
    ]);
    chunks.push(centralHeader, entry.nameBytes);
    offset += centralHeader.length + entry.nameBytes.length;
  });
  const centralSize = offset - centralOffset;
  chunks.push(new Uint8Array([
    ...uint32(0x06054b50),
    ...uint16(0),
    ...uint16(0),
    ...uint16(central.length),
    ...uint16(central.length),
    ...uint32(centralSize),
    ...uint32(centralOffset),
    ...uint16(0)
  ]));
  const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const bytes = new Uint8Array(total);
  let cursor = 0;
  chunks.forEach(chunk => {
    bytes.set(chunk, cursor);
    cursor += chunk.length;
  });
  return bytes;
}

function readJsonFile(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function multiTriggerCatalogPath(triggerCount) {
  return path.join(
    repoRoot,
    "example-scenario-apk",
    "multi-trigger-demos",
    `${triggerCount}-triggers`,
    "questionnaire-trigger-catalog.json"
  );
}

function readMultiTriggerCatalog(triggerCount) {
  return readJsonFile(multiTriggerCatalogPath(triggerCount));
}

function assertPassiveMultiTriggerCatalog(catalog, triggerCount) {
  assert(catalog.schemaVersion === "mq.quest_questionnaire_trigger_catalog.v1", `${triggerCount}-trigger catalog schema mismatch.`);
  assert(catalog.package === `org.questquestionnaire.stimulusdemo${triggerCount}`, `${triggerCount}-trigger catalog package should use the product brand.`);
  assert(Array.isArray(catalog.triggers) && catalog.triggers.length === triggerCount, `${triggerCount}-trigger catalog should declare exactly ${triggerCount} triggers.`);
  catalog.triggers.forEach((trigger, index) => {
    const number = index + 1;
    assert(trigger.triggerId === `trigger_${number}_complete`, `${triggerCount}-trigger catalog trigger ${number} id mismatch.`);
    assert(trigger.label === `After trigger ${number}`, `${triggerCount}-trigger catalog trigger ${number} label mismatch.`);
    ["recommendedMode", "questionnaireMode", "blockId", "blockNumber", "questionnaireType", "flowMode"].forEach(field => {
      assert(!Object.prototype.hasOwnProperty.call(trigger, field), `${triggerCount}-trigger catalog must not encode Unity-side study logic field ${field}.`);
    });
  });
}

function blockSegmentCount(html) {
  return (html.match(/class="block-segment study-block"/g) || []).length;
}

function assertRenderedBlocks(test, triggerCount, label) {
  const blockHtml = test.document.getElementById("triggerMappingList").innerHTML;
  assert(blockSegmentCount(blockHtml) === triggerCount + 1, `${label}: GUI should render Block 1 plus ${triggerCount} scanned return blocks.`);
  assert(blockHtml.includes('id="block-segment-startup"'), `${label}: startup block segment missing.`);
  assert(blockHtml.includes("Before experiment/running APK"), `${label}: startup label should use experiment/running APK wording.`);
  assert(!/before video|after video|Video complete/i.test(blockHtml), `${label}: block labels must not use video-specific wording.`);
  for (let index = 0; index < triggerCount; index += 1) {
    const number = index + 1;
    assert(blockHtml.includes(`id="block-segment-trigger-${index}"`), `${label}: trigger block ${index} segment missing.`);
    assert(blockHtml.includes(`After trigger ${number}`), `${label}: trigger block ${number} label missing.`);
  }
}

function assignSingleModulePerTrigger(test, triggerCount) {
  const modules = ["slider", "pictographic", "demographics", "maia2"];
  for (let index = 0; index < triggerCount; index += 1) {
    const selected = modules[index % modules.length];
    test.document.getElementById(`triggerMode${index}`).value = selected;
    modules.forEach(module => {
      test.document.getElementById(`triggerModule${index}_${module}`).checked = module === selected;
    });
  }
  test.context.__api.refresh();
  return modules.slice(0, triggerCount);
}

function runMultiTriggerGuiScenario(triggerCount) {
  const test = loadEditor();
  const catalog = readMultiTriggerCatalog(triggerCount);
  assertPassiveMultiTriggerCatalog(catalog, triggerCount);
  test.context.__api.applyTriggerCatalog(catalog, `${triggerCount}-trigger-demo.json`);
  assertRenderedBlocks(test, triggerCount, `${triggerCount}-trigger GUI catalog`);

  const unassigned = test.context.__api.buildConfig();
  const unassignedQuality = test.context.__api.qualityReport(unassigned);
  assert(unassigned.chainDefaults.startMode === "questionnaireFirst", `${triggerCount}-trigger catalog should default to questionnaire-first participant flow.`);
  assert(unassigned.chainDefaults.nextPackage === catalog.package, `${triggerCount}-trigger catalog should target the scanned running APK package.`);
  assert(unassigned.triggerQuestionnaireMapping.triggers.length === triggerCount, `${triggerCount}-trigger catalog should create ${triggerCount} trigger mappings.`);
  assert(unassigned.triggerQuestionnaireMapping.passiveTriggerWarnings.length === 0, `${triggerCount}-trigger catalog should be passive-only.`);
  assert(unassigned.triggerQuestionnaireMapping.triggers.every(trigger => trigger.questionnaireMode === "none"), `${triggerCount}-trigger catalog should leave return blocks unassigned.`);
  assert(unassigned.experimentBlockRegistry.sourceTriggerCatalog.triggerCount === triggerCount, `${triggerCount}-trigger registry should remember source trigger count.`);
  assert(unassigned.experimentBlockRegistry.blocks.length === 0, `${triggerCount}-trigger unassigned scan should not create runnable return blocks.`);
  assert(unassignedQuality.status === "fail", `${triggerCount}-trigger unassigned scan should fail until return blocks are assigned.`);

  const assignedModules = assignSingleModulePerTrigger(test, triggerCount);
  const assigned = test.context.__api.buildConfig();
  const assignedQuality = test.context.__api.qualityReport(assigned);
  const assignedPlan = test.context.__api.buildChainPlan(assigned);
  assert(assigned.triggerQuestionnaireMapping.triggers.length === triggerCount, `${triggerCount}-trigger assigned mapping count mismatch.`);
  assert(assigned.triggerQuestionnaireMapping.triggers.every(trigger => trigger.enabled), `${triggerCount}-trigger assigned mappings should all be enabled.`);
  assert(assigned.triggerQuestionnaireMapping.triggers.every(trigger => trigger.questionnaireSequence.length === 1), `${triggerCount}-trigger stress should assign one questionnaire element per return block.`);
  assert(assigned.experimentBlockRegistry.blocks.length === triggerCount, `${triggerCount}-trigger assigned registry should contain one block per passive trigger.`);
  assert(assigned.experimentBlockRegistry.blocks.every(block => block.type === "questionnaire"), `${triggerCount}-trigger assigned registry should keep all study logic inside the questionnaire APK.`);
  assert(assigned.experimentBlockRegistry.blocks.every(block => block.package === "org.questquestionnaire.questionnaires2d"), `${triggerCount}-trigger assigned registry should never route questionnaire work to Unity.`);
  assert(assigned.experimentBlockRegistry.blocks.every(block => block.trigger.type === "apkManifestTrigger"), `${triggerCount}-trigger assigned blocks should be keyed by passive APK manifest triggers.`);
  assert(assigned.experimentBlockRegistry.blocks.every(block => block.extras && block.extras["mq.triggerId"]), `${triggerCount}-trigger assigned blocks should pass mq.triggerId.`);
  assert(assigned.experimentBlockRegistry.blocks.every(block => !block.extras["mq.blockId"] && !block.extras["mq.blockNumber"]), `${triggerCount}-trigger assigned Unity-return extras should prefer triggerId over block routing fallbacks.`);
  assignedModules.forEach((module, index) => {
    assert(assigned.triggerQuestionnaireMapping.triggers[index].questionnaireSequence.join(",") === module, `${triggerCount}-trigger mapping ${index + 1} module mismatch.`);
    assert(assigned.experimentBlockRegistry.blocks[index].extras["mq.questionnaireSequence"] === module, `${triggerCount}-trigger registry ${index + 1} sequence extra mismatch.`);
  });
  assert(assignedQuality.status === "pass", `${triggerCount}-trigger assigned catalog should pass quality report.`);
  assert(assignedPlan.blockRegistry.blocks.length === triggerCount, `${triggerCount}-trigger ChainLink plan should embed one return block per trigger.`);
  assert(!JSON.stringify(assigned.experimentBlockRegistry.sourceTriggerCatalog).includes("questionnaireMode"), `${triggerCount}-trigger source catalog metadata should not smuggle questionnaire behavior.`);

  return {
    triggerCount,
    catalogPath: multiTriggerCatalogPath(triggerCount),
    blockSegmentCount: blockSegmentCount(test.document.getElementById("triggerMappingList").innerHTML),
    unassignedQualityStatus: unassignedQuality.status,
    assignedQualityStatus: assignedQuality.status,
    assignedModules,
    assignedRegisteredBlocks: assigned.experimentBlockRegistry.blocks.length,
    assigned,
    assignedQuality
  };
}

async function runMultiTriggerApkUploadScenario(triggerCount) {
  const test = loadEditor();
  const catalog = readMultiTriggerCatalog(triggerCount);
  const bytes = storedZip({
    "assets/mq/questionnaire-trigger-catalog.json": JSON.stringify(catalog)
  });
  const fileName = `quest-questionnaire-stimulus-demo-${triggerCount}-triggers.apk`;
  const file = {
    name: fileName,
    async arrayBuffer() {
      return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    }
  };
  await test.context.__api.loadTriggerCatalogFile(file);
  assertRenderedBlocks(test, triggerCount, `${triggerCount}-trigger APK upload`);
  assignSingleModulePerTrigger(test, triggerCount);
  const config = test.context.__api.buildConfig();
  const quality = test.context.__api.qualityReport(config);
  assert(config.triggerQuestionnaireMapping.triggers.length === triggerCount, `${triggerCount}-trigger APK upload scan trigger count mismatch.`);
  assert(config.experimentBlockRegistry.blocks.length === triggerCount, `${triggerCount}-trigger APK upload scan registry block count mismatch.`);
  assert(quality.status === "pass", `${triggerCount}-trigger APK upload assigned config should pass quality report.`);
  assert(test.document.getElementById("stagedScenarioApkPath").value === `C:\\staged\\${fileName}`, `${triggerCount}-trigger APK upload should stage the source APK.`);
  return {
    triggerCount,
    blockSegmentCount: blockSegmentCount(test.document.getElementById("triggerMappingList").innerHTML),
    qualityStatus: quality.status,
    stagedScenarioApkPath: test.document.getElementById("stagedScenarioApkPath").value
  };
}

function csvCell(value) {
  const text = String(value ?? "");
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, "\"\"")}"` : text;
}

function sliderCsv(questionnaireId, count, options = {}) {
  const rows = [[
    "questionnaireId",
    "questionnaireVersion",
    "appVersion",
    "block",
    "questionType",
    "itemId",
    "language",
    "order",
    "text",
    "required",
    "scalePoints",
    "min",
    "max",
    "leftAnchor",
    "rightAnchor",
    "choices",
    "branchingTag"
  ]];
  const min = options.min ?? 0;
  const max = options.max ?? 100;
  const format = options.format ?? "slider";
  const englishPrefix = options.englishPrefix || "I noticed custom experience item";
  const germanPrefix = options.germanPrefix || "Ich bemerkte benutzerdefiniertes Erlebnis-Item";
  for (let index = 1; index <= count; index += 1) {
    const order = String(index);
    const itemId = `vas_${String(index).padStart(3, "0")}`;
    const englishText = options.quotedExample && index === 2
      ? "I noticed a comma, a quote \"mark\", and calm breathing."
      : `${englishPrefix} ${String(index).padStart(3, "0")}.`;
    const germanText = options.quotedExample && index === 2
      ? "Ich bemerkte ein Komma, ein Anfuehrungszeichen \"hier\", und ruhige Atmung."
      : `${germanPrefix} ${String(index).padStart(3, "0")}.`;
    rows.push([questionnaireId, "1.0.0", "1.0.0", "custom_slider", format, itemId, "English", order, englishText, "true", "", min, max, "LOW", "HIGH", "", ""]);
    if (!options.omitDeutsch) {
      rows.push([questionnaireId, "1.0.0", "1.0.0", "custom_slider", format, itemId, "Deutsch", order, germanText, "true", "", min, max, "NIEDRIG", "HOCH", "", ""]);
    }
  }
  return rows.map(row => row.map(csvCell).join(",")).join("\n") + "\n";
}

function runCsvStressScenario(scenario) {
  const test = loadEditor();
  applyCsvStressTriggerCatalog(test);
  test.context.__api.applyCsvText(scenario.csv, `${scenario.id}.csv`);
  const config = JSON.parse(test.document.getElementById("preview").textContent);
  const slider = config.blocks.find(block => block.id === "custom_slider");
  const validation = test.context.__api.validate(config);
  const quality = test.context.__api.qualityReport(config);
  const validationErrors = validation.filter(issue => issue.level === "error");
  assert(slider, `${scenario.id}: slider block missing.`);
  assert(config.questionnaireId === scenario.id, `${scenario.id}: questionnaire id mismatch.`);
  assert(slider.expectedItemCount === scenario.expectedCount, `${scenario.id}: expected item count mismatch.`);
  assert(slider.languages.English.items.length === scenario.expectedCount, `${scenario.id}: English item count mismatch.`);
  assert(slider.languages.Deutsch.items.length === scenario.expectedCount, `${scenario.id}: Deutsch item count mismatch.`);
  assert(!config.blocks.some(block => block.id === "maia2"), `${scenario.id}: slider CSV should omit preloaded MAIA-2.`);
  assert(!config.blocks.some(block => block.id === "pictographic"), `${scenario.id}: slider CSV should omit pictographic preloads.`);
  if (scenario.expectQualityStatus) {
    assert(quality.status === scenario.expectQualityStatus, `${scenario.id}: quality status ${quality.status} did not match ${scenario.expectQualityStatus}.`);
  }
  if (scenario.expectValidationErrors === false) {
    assert(validationErrors.length === 0, `${scenario.id}: validation errors were not expected.`);
  }
  if (scenario.expectWarningMinimum !== undefined) {
    assert(quality.issueCounts.warning >= scenario.expectWarningMinimum, `${scenario.id}: expected at least ${scenario.expectWarningMinimum} warning(s).`);
  }
  if (scenario.expectErrorMinimum !== undefined) {
    assert(quality.issueCounts.error >= scenario.expectErrorMinimum, `${scenario.id}: expected at least ${scenario.expectErrorMinimum} error(s).`);
  }
  if (scenario.expectQuotedText) {
    assert(slider.languages.English.items.some(item => item.includes("quote \"mark\"")), `${scenario.id}: quoted CSV text was not preserved.`);
  }
  return {
    id: scenario.id,
    itemCount: scenario.expectedCount,
    status: quality.status,
    validationErrors: validationErrors.length,
    qualityErrors: quality.issueCounts.error,
    qualityWarnings: quality.issueCounts.warning,
    estimatedMinutes: quality.estimatedMinutes
  };
}

function assertCsvImportThrows(csv, fileName, expectedMessage) {
  const test = loadEditor();
  applyCsvStressTriggerCatalog(test);
  let thrown = "";
  try {
    test.context.__api.applyCsvText(csv, fileName);
  } catch (error) {
    thrown = error.message || String(error);
  }
  assert(thrown.includes(expectedMessage), `${fileName}: expected error containing ${expectedMessage}, got ${thrown || "no error"}.`);
  return thrown;
}

function applyCsvStressTriggerCatalog(test) {
  test.context.__api.applyTriggerCatalog({
    schemaVersion: "mq.quest_questionnaire_trigger_catalog.v1",
    scenarioId: "csv-stress-stimulus",
    package: "org.questquestionnaire.csvstress",
    activity: "org.questquestionnaire.csvstress.UnityPlayerActivity",
    label: "CSV Stress Stimulus",
    triggers: [
      { triggerId: "after_stimulus", label: "After stimulus", recommendedMode: "slider" }
    ]
  }, "csv-stress-trigger-catalog.json");
  test.document.getElementById("triggerModule0_slider").checked = true;
  test.context.__api.refresh();
}

const { context, document, html } = loadEditor();
const initial = context.__api.buildConfig();
const initialQuality = context.__api.qualityReport(initial);
assert(initial.schemaVersion === "my-questionnaire-vr.config.v1", "Default schema version mismatch.");
assert(initial.questionnaireId === "quest-questionnaire-study", "Default questionnaire id should be generic and product-branded.");
assert(initial.blocks.some(block => block.id === "maia2"), "Default config should include the runtime Likert compatibility block.");
assert(initial.blocks.some(block => block.id === "pictographic"), "Default config should include pictographic scales.");
assert(initial.chainDefaults.finishBehavior === "resumeCaller", "Default chain finish behavior mismatch.");
assert(Array.isArray(initial.chainDefaults.questionnaireSequence), "Default chain should expose a questionnaireSequence array.");
assert(initial.chainDefaults.questionnaireSequence.length === 0, "Default block 1 should start empty until the user selects questionnaire elements.");
assert(initial.experimentBlockRegistry.schemaVersion === "questquestionnaire.chainlink.block-registry.v1", "Default block registry schema mismatch.");
assert(initial.experimentBlockRegistry.blocks[0].number === "001", "Default registry should start at block 001.");
assert(initial.experimentBlockRegistry.blocks.some(block => block.questionnaireMode === "baseline"), "Default registry should include a baseline questionnaire block.");
assert(initial.experimentBlockRegistry.blocks.some(block => Array.isArray(block.questionnaireSequence) && block.questionnaireSequence.join(",") === "demographics,maia2"), "Default registry should preserve questionnaire sequences.");
assert(initial.experimentBlockRegistry.blocks.some(block => block.questionnaireMode === "pictographic"), "Default registry should include pictographic sampling blocks.");
assert(initial.experimentBlockRegistry.blocks.some(block => block.package === "org.questquestionnaire.stimulusdemo"), "Default registry should target the neutral stimulus demo package.");
assert(initial.experimentBlockRegistry.controllerTriggerButton === "auto-unused-non-breath-tracking", "Default ChainLink trigger button should let Unity choose the non-breath-tracking controller.");
assert(initial.experimentBlockRegistry.blocks.some(block => block.type === "apk" && block.extras && block.extras["mq.controllerButton"] === "auto-unused-non-breath-tracking"), "Scenario APK blocks should receive the auto controller-button policy.");
const initialChainPlan = context.__api.buildChainPlan(initial);
assert(initialChainPlan.schemaVersion === "questquestionnaire.chainlink.plan.v1", "ChainLink plan schema mismatch.");
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
assert(html.includes("packet-bundle-audit-receipts"), "Hosted/offline GUI should require the packet-bundle audit receipt capability.");
assert(html.includes("hosted-final-product"), "Hosted GUI should include final-product mode styling.");
assert(html.includes("data-dev-only"), "Hosted GUI should mark development-only controls.");
assert(html.includes('runnerStage.removeAttribute("data-requires-apk")'), "Hosted product mode should keep companion setup available before APK load.");
assert(html.includes("shouldUseHostedQuestionnaireFirstDefaults"), "Hosted product mode should auto-select 2D-first editable block defaults after APK load.");
assert(html.includes('id="dependencyStatusButton" type="button">Dependency status'), "Dependency status should be available before APK load.");
assert(html.includes('id="installDependenciesButton" type="button">Install dependencies'), "Dependency install should be available before APK load.");
assert(html.includes('id="generateApkAppButton" class="primary" type="button" data-requires-apk-control'), "Generate APK should remain APK-gated.");
assert(html.includes('id="installApkAppButton" class="primary" type="button" data-requires-apk-control'), "Install APK should remain APK-gated.");
assert(html.includes('id="navQuestionnaires" class="nav-link locked" href="#questionnaire-stage" data-dev-only hidden'), "Legacy questionnaire content nav should be hidden from the visible block-builder flow.");
assert(html.includes('id="questionnaire-stage" class="stage" data-requires-apk data-dev-only hidden'), "Legacy questionnaire content stage should be hidden from the visible block-builder flow.");
assert(html.includes('id="navProject" class="nav-link locked" href="#project-stage" data-dev-only hidden'), "Project nav should be hidden from the product workflow.");
assert(html.includes('id="project-stage" class="stage" data-requires-apk data-dev-only hidden'), "Project/return behavior stage should be hidden from the product workflow.");
assert(html.includes('id="navReview" class="nav-link locked" href="#review-stage" data-dev-only hidden'), "Review nav should be hidden from the product workflow.");
assert(html.includes('id="review-stage" class="stage" data-requires-apk data-dev-only hidden'), "Review/pipeline stage should be hidden from the product workflow.");
assert(html.includes("[data-dev-only]"), "Developer-only controls should keep a durable hiding marker.");
assert(html.includes('id="csvStatus" class="issue" hidden'), "Global CSV status should stay quiet until there is feedback.");
assert(!html.includes("<summary>Routing</summary>"), "Block cards should not expose internal routing details in the product UI.");
assert(html.includes('id="dynamicBlockNavLinks"'), "Builder should have a dynamic nav outlet for scanned return blocks.");
assert(html.includes('block-segment-startup'), "Block 1 should render as its own HTML segment.");
assert(html.includes('block-segment-trigger-'), "Scanned Unity triggers should render as later block HTML segments.");
assert(html.includes('trigger_1_complete'), "Repository example should use the one-trigger passive completion catalog.");
assert(html.includes('label: "After trigger 1"'), "Repository example should label the passive return as After trigger 1.");
assert(!/before video|after video|Video complete/i.test(html), "Builder source must not expose video-specific trigger labels.");
assert(html.includes('const startupElementTypes = ["demographics", "likert", "pictographic", "slider"]'), "Visible block types should use generic questionnaire categories.");
assert(!html.includes('const startupElementTypes = ["demographics", "maia2"'), "MAIA-2 should not be a visible top-level questionnaire type.");
assert(!html.includes('<h3>MAIA-2</h3>'), "MAIA-2 should not appear as a standalone questionnaire panel heading.");
assert(!html.includes('>MAIA-2</button>'), "MAIA-2 should not appear as a standalone questionnaire button.");
assert(!html.includes('Likert MAIA-2 preload'), "MAIA-2 should not appear as a visible top-level Likert option.");
assert(!html.includes('<option value="temporalTracer">'), "Temporal tracer should not appear as a visible trigger-block route in the product GUI.");
assert(html.includes('Before experiment/running APK'), "Block 1 label should use experiment/running APK wording.");
assert(html.includes('stage-scenario-apk'), "Builder should expose scenario APK staging before headset install.");
assert(html.includes('id="csvTemplateKind"'), "Hosted product flow should expose questionnaire type CSV templates.");
assert(html.includes('id="downloadCsvTemplateButton"'), "Hosted product flow should expose CSV template download.");
assert(html.includes('id="loadCsvInput"'), "Hosted product flow should expose CSV upload.");
assert(html.includes('id="block1ModuleDemographics"'), "Hosted product flow should expose block 1 module controls.");
assert(html.includes('id="chainQuestionnaireSequence"'), "Generated config should expose the block 1 questionnaire sequence contract.");
assert(html.includes('id="downloadPictographicZipTemplateButton"'), "Hosted product flow should expose pictographic ZIP template download.");
assert(html.includes('id="loadPictographicZipInput"'), "Hosted product flow should expose pictographic ZIP upload.");
assert(html.includes('id="validateWorkflowAppButton" type="button" data-dev-only'), "Validate workflow button should be hidden in hosted product mode.");
assert(html.includes('id="review-stage" class="stage" data-requires-apk data-dev-only'), "Review pipeline stage should be hidden in hosted product mode.");
context.location = { protocol: "https:", hostname: "georgefejer91.github.io" };
context.__api.applyHostedFinalProductMode();
assert(document.body.classList.contains("hosted-final-product"), "Hosted product mode should set the body class.");
assert(document.getElementById("appRunTests").checked === false, "Hosted product mode should disable developer unit tests by default.");
assert(document.getElementById("workflowDirectHandoff").checked === false, "Hosted product mode should disable direct handoff trials by default.");
const hostedCapabilities = context.__api.appBackendRequiredCapabilities().map(item => item.id);
assert(hostedCapabilities.includes("generate-apk"), "Hosted product mode should require APK generation.");
assert(hostedCapabilities.includes("install-apk"), "Hosted product mode should require Quest APK install.");
assert(!hostedCapabilities.includes("validate-workflow"), "Hosted product mode should not require developer validation workflow capability.");
context.location = { protocol: "http:", hostname: "127.0.0.1" };

context.__api.applyTriggerCatalog({
  schemaVersion: "mq.quest_questionnaire_trigger_catalog.v1",
  catalogVersion: "1.0.0",
  scenarioId: "zero-trigger-demo",
  package: "org.questquestionnaire.zerotrigger",
  activity: "org.questquestionnaire.zerotrigger.UnityPlayerActivity",
  label: "Zero Trigger Demo",
  triggers: []
}, "zero-trigger-demo.apk");
const zeroTriggerHtml = document.getElementById("triggerMappingList").innerHTML;
assert((zeroTriggerHtml.match(/class="block-segment study-block"/g) || []).length === 1, "A loaded zero-trigger APK should still create the default Block 1 segment.");
assert(zeroTriggerHtml.includes('id="block-segment-startup"'), "The default Block 1 segment should have a stable anchor.");
assert(zeroTriggerHtml.includes("Block 1"), "The default Block 1 card should be visible after a zero-trigger APK load.");
assert(document.getElementById("triggerSummary").textContent.includes("0 passive Unity return triggers"), "Zero-trigger summary should explain that only Block 1 is needed.");

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
  "\"Install scenario APK on Quest\"",
  "\"Install questionnaire APK on Quest\"",
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
const physicalPacketBundleSummaryPath = context.__api.evidenceBundleSummaryPath({
  physicalGatePacketReceipt: { artifacts: { summaryPath: "C:\\artifacts\\physical-packet-summary.json" } }
});
assert(physicalPacketBundleSummaryPath === "C:\\artifacts\\physical-packet-summary.json", "Evidence bundle download should target the visible physical packet summary.");
const packetBundleAuditText = context.__api.auditReceiptText({
  auditReceipt: {
    status: "pass-with-physical-pending",
    counts: { requirements: 12, proven: 9, physicalPending: 3, failedOrMissing: 0 },
    artifacts: {
      physicalGatePacketEvidenceBundleAvailable: true,
      physicalGatePacketEvidenceBundlePass: true,
      physicalGatePacketEvidenceBundleEntryCount: 399,
      physicalGatePacketEvidenceBundleTextEntryCount: 117
    }
  }
});
assert(packetBundleAuditText.includes("portable packet bundle proven"), "Audit receipt should show proven portable packet bundle evidence.");
assert(packetBundleAuditText.includes("399 entries"), "Audit receipt should show packet bundle entry counts.");
const packetBundleMissingAuditText = context.__api.auditReceiptText({
  auditReceipt: {
    status: "incomplete-missing-evidence",
    counts: { requirements: 12, proven: 8, physicalPending: 3, failedOrMissing: 1 },
    artifacts: {
      physicalGatePacketEvidenceBundleAvailable: true,
      physicalGatePacketEvidenceBundlePass: false,
      physicalGatePacketMissingBundleEntries: ["physical-gate-runbook.txt"]
    }
  }
});
assert(packetBundleMissingAuditText.includes("portable packet bundle missing: physical-gate-runbook.txt"), "Audit receipt should show missing packet bundle entries.");
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

context.location = { protocol: "https:", hostname: "georgefejer91.github.io" };
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
assert(triggered.chainDefaults.startMode === "questionnaireFirst", "Hosted product catalog load should make the generated questionnaire APK the first participant app.");
assert(triggered.chainDefaults.finishBehavior === "openNext", "Hosted product catalog load should open the Unity APK after block 1.");
assert(triggered.chainDefaults.questionnaireMode === "none", "Catalog load should not preselect a specific questionnaire for editable block 1.");
assert(triggered.chainDefaults.questionnaireSequence.length === 0, "Catalog load should keep editable block 1 empty until the user adds questionnaire elements.");
assert(triggered.chainDefaults.triggerId === "study_start_block_1", "Hosted product catalog load should use a generic block 1 start trigger when Unity only declares later passive triggers.");
assert(triggered.chainDefaults.nextPackage === "com.example.scenario", "Hosted product catalog load should target the scanned APK as nextPackage.");
assert(triggered.appDisplayName === "Start Experiment | Demo scenario", "Hosted product catalog load should name the generated APK from the scanned scenario label.");
assert(triggered.triggerQuestionnaireMapping.triggers.length === 2, "Trigger catalog should produce two trigger mappings.");
assert(triggered.triggerQuestionnaireMapping.triggers[0].questionnaireSequence.length === 0, "Scanned Unity triggers should start without questionnaire assignments.");
assert(triggered.triggerQuestionnaireMapping.triggers[1].questionnaireSequence.length === 0, "Second scanned Unity trigger should start without questionnaire assignments.");
assert(triggered.triggerQuestionnaireMapping.passiveTriggerWarnings.length === 2, "Trigger catalog recommended modes should be recorded as passive-trigger warnings.");
assert(triggered.triggerQuestionnaireMapping.triggers.every(trigger => trigger.sourceRecommendedMode), "Trigger mappings should preserve source recommended modes as legacy metadata.");
assert(triggered.experimentBlockRegistry.blocks.length === 0, "Unassigned scanned triggers should not fall back to the legacy demo registry.");
assert(triggeredQuality.status === "fail", "Catalog-backed questionnaire should wait for the user to assign return-block elements.");
assert(triggeredQuality.issues.some(issue => issue.text.includes("Experiment block registry")), "Unassigned scan quality should explain that no return blocks are configured yet.");
document.getElementById("downloadQualityButton").click();
document.getElementById("downloadBlockRegistryButton").click();
document.getElementById("downloadChainPlanButton").click();

document.getElementById("triggerModule0_pictographic").checked = true;
document.getElementById("triggerModule1_slider").checked = true;
context.__api.refresh();
const assignedTriggered = context.__api.buildConfig();
assert(assignedTriggered.experimentBlockRegistry.blocks.length === 2, "Assigned trigger catalog should produce one registry block per enabled trigger.");
assert(assignedTriggered.experimentBlockRegistry.blocks.every(block => block.type === "questionnaire"), "Assigned manifest registry should contain questionnaire blocks.");
assert(assignedTriggered.experimentBlockRegistry.blocks.every(block => block.trigger.type === "apkManifestTrigger"), "Assigned manifest blocks should use APK trigger events.");
assert(assignedTriggered.experimentBlockRegistry.blocks.every(block => block.extras && block.extras["mq.finishBehavior"] === "resumeCaller"), "Unity-triggered blocks should resume Unity after block 1 starts Unity.");
assert(assignedTriggered.experimentBlockRegistry.blocks.every(block => block.extras && block.extras["mq.triggerId"]), "Unity-triggered blocks should launch from passive trigger ids.");
assert(assignedTriggered.experimentBlockRegistry.blocks[0].extras["mq.questionnaireSequence"] === "pictographic", "First assigned Unity-return block should pass a pictographic sequence extra.");
assert(assignedTriggered.experimentBlockRegistry.blocks[1].extras["mq.questionnaireSequence"] === "slider", "Second assigned Unity-return block should pass a slider sequence extra.");
assert(context.__api.qualityReport(assignedTriggered).status === "pass", "Assigned catalog-backed questionnaire should pass quality report.");

document.getElementById("block1ModuleMaia2").checked = true;
document.getElementById("triggerModule0_slider").checked = true;
context.__api.refresh();
const customSequenced = context.__api.buildConfig();
assert(customSequenced.chainDefaults.questionnaireSequence.join(",") === "maia2", "GUI should add the runtime Likert block only when the user selects the Likert element.");
assert(customSequenced.chainDefaults.questionnaireMode === "maia2", "A selected Likert preload should be represented as a Likert questionnaire block, not a default baseline.");
assert(customSequenced.triggerQuestionnaireMapping.triggers[0].questionnaireSequence.join(",") === "pictographic,slider", "GUI should add multiple modules to a Unity-return block.");
assert(customSequenced.experimentBlockRegistry.blocks[0].extras["mq.questionnaireSequence"] === "pictographic,slider", "Registry should pass the multi-module sequence extra to the 2D APK.");
assert(customSequenced.experimentBlockRegistry.blocks[0].expectedOutputs.pictographicSelections > 0, "Multi-module trigger block should expect pictographic outputs.");
assert(customSequenced.experimentBlockRegistry.blocks[0].expectedOutputs.sliderAnswers > 0, "Multi-module trigger block should expect slider outputs.");
assert(context.__api.qualityReport(customSequenced).status === "pass", "Custom block sequence config should pass quality report.");

context.__api.applyTriggerCatalog({
  schemaVersion: "mq.quest_questionnaire_trigger_catalog.v1",
  catalogVersion: "1.0.0",
  scenarioId: "quest-questionnaire-stimulus-demo",
  package: "org.questquestionnaire.stimulusdemo",
  activity: "org.questquestionnaire.stimulusdemo.StimulusUnityPlayerGameActivity",
  label: "Questionnaire Stimulus Builder Demo",
  triggers: [
    { triggerId: "trigger_1_complete", label: "After trigger 1" }
  ]
}, "quest-questionnaire-stimulus-demo.apk");

const handoff = context.__api.buildConfig();
const handoffQuality = context.__api.qualityReport(handoff);
const handoffPlan = context.__api.buildChainPlan(handoff);
assert(handoff.chainDefaults.startMode === "questionnaireFirst", "Hosted handoff catalog should keep questionnaire-first start mode.");
assert(handoff.chainDefaults.finishBehavior === "openNext", "Hosted handoff catalog should open Unity after block 1.");
assert(handoff.chainDefaults.questionnaireMode === "none", "Hosted handoff catalog should not preselect a specific questionnaire in editable block 1.");
assert(handoff.chainDefaults.questionnaireSequence.length === 0, "Hosted handoff catalog should keep editable block 1 empty until the user adds elements.");
assert(handoff.chainDefaults.triggerId === "study_start_block_1", "Hosted handoff catalog should not treat Unity manifest triggers as block 1 questionnaire decisions.");
assert(handoff.chainDefaults.nextPackage === "org.questquestionnaire.stimulusdemo", "Hosted handoff catalog should target the Unity package as nextPackage.");
assert(handoff.appDisplayName === "Start Experiment | Questionnaire Stimulus Builder Demo", "Hosted handoff catalog should name the generated APK as the experiment starter for the Unity demo.");
assert(handoff.triggerQuestionnaireMapping.triggers.length === 1, "Handoff demo catalog should produce one passive Unity-return trigger mapping.");
assert(handoff.triggerQuestionnaireMapping.passiveTriggerWarnings.length === 0, "Handoff demo catalog should not encode questionnaire behavior in Unity trigger metadata.");
assert(handoff.triggerQuestionnaireMapping.triggers[0].triggerId === "trigger_1_complete", "Handoff demo catalog should expose the single passive trigger id.");
assert(handoff.triggerQuestionnaireMapping.triggers[0].label === "After trigger 1", "Handoff demo catalog should use experiment/trigger wording, not video wording.");
assert(handoff.triggerQuestionnaireMapping.triggers[0].questionnaireMode === "none", "The passive trigger should stay unassigned until the builder maps it.");
assert(handoff.triggerQuestionnaireMapping.triggers[0].questionnaireSequence.length === 0, "The passive trigger should not inherit questionnaire decisions from Unity metadata.");
assert(handoff.experimentBlockRegistry.blocks.length === 0, "Unassigned handoff trigger catalog should not create questionnaire blocks.");
assert(handoffQuality.status === "fail", "Unassigned handoff demo config should fail until return blocks are assigned.");
const handoffBlockHtml = document.getElementById("triggerMappingList").innerHTML;
assert(!handoffBlockHtml.includes("Multiple choice CSV"), "Visible block dropdown should hide unsupported multiple-choice imports.");
assert(!handoffBlockHtml.includes("Text entry CSV"), "Visible block dropdown should hide unsupported text-entry imports.");
assert(!handoffBlockHtml.includes("Temporal tracer"), "Visible block dropdown should hide unsupported temporal-tracer imports.");

document.getElementById("triggerMode0").value = "slider";
context.__api.refresh();
const assignedHandoff = context.__api.buildConfig();
const assignedHandoffQuality = context.__api.qualityReport(assignedHandoff);
const assignedHandoffPlan = context.__api.buildChainPlan(assignedHandoff);
assert(assignedHandoff.triggerQuestionnaireMapping.triggers[0].questionnaireMode === "slider", "Builder assignment should map the passive trigger to an in-APK slider block.");
assert(assignedHandoff.triggerQuestionnaireMapping.triggers[0].questionnaireSequence.join(",") === "slider", "Slider trigger should use an internal questionnaire sequence.");
assert(assignedHandoff.experimentBlockRegistry.blocks.some(block => block.type === "questionnaire" && block.questionnaireMode === "slider"), "Assigned handoff registry should include a questionnaire-owned slider block.");
assert(assignedHandoffPlan.steps.some(step => step.type === "questionnaire" && step.action === "org.questquestionnaire.questionnaires2d.RUN"), "Assigned handoff chain plan should launch the generated questionnaire APK.");
assert(assignedHandoffQuality.status === "pass", "Assigned handoff demo config should pass quality report.");

context.__api.applyQuestionnaireFirstDefaults();
const twoDStart = context.__api.buildConfig();
const twoDStartQuality = context.__api.qualityReport(twoDStart);
assert(twoDStart.chainDefaults.startMode === "questionnaireFirst", "2D-first preset should mark questionnaire-first start mode.");
assert(twoDStart.chainDefaults.finishBehavior === "openNext", "2D-first preset should open the Unity APK after block 1.");
assert(twoDStart.chainDefaults.questionnaireMode === "none", "2D-first preset should not preselect a specific questionnaire.");
assert(twoDStart.chainDefaults.questionnaireSequence.length === 0, "2D-first preset should keep block 1 empty until the user adds elements.");
assert(twoDStart.chainDefaults.triggerId === "study_start_block_1", "2D-first preset should use a generic block 1 start id.");
assert(twoDStart.chainDefaults.nextPackage === "org.questquestionnaire.stimulusdemo", "2D-first preset should target the Unity package as nextPackage.");
assert(twoDStart.appDisplayName === "Start Experiment | Questionnaire Stimulus Builder Demo", "2D-first preset should keep the participant-facing generated APK title.");
assert(twoDStart.experimentBlockRegistry.blocks.every(block => block.extras && block.extras["mq.finishBehavior"] === "resumeCaller"), "Unity-triggered blocks should still return to Unity in 2D-first mode.");
assert(twoDStartQuality.status === "pass", "2D-first handoff demo config should pass quality report.");

const csv = fs.readFileSync(csvPath, "utf8");
context.__api.applyCsvText(csv, "two-item-slider-template.csv");
const imported = JSON.parse(document.getElementById("preview").textContent);
const slider = imported.blocks.find(block => block.id === "custom_slider");
const validation = context.__api.validate(imported);
const importedQuality = context.__api.qualityReport(imported);

assert(imported.questionnaireId === "demo-slider", "CSV questionnaire id was not applied.");
assert(!imported.blocks.some(block => block.id === "maia2"), "Slider-only CSV import should omit MAIA-2.");
assert(!imported.blocks.some(block => block.id === "pictographic"), "Slider-only CSV import should omit pictographic scales.");
assert(imported.blocks.map(block => block.id).join(">") === "demographics>custom_slider>end", "Slider-only CSV import block order mismatch.");
assert(slider.expectedItemCount === 2, "CSV slider expected count was not applied.");
assert(slider.languages.English.items.length === 2, "CSV English slider items were not imported.");
assert(slider.languages.Deutsch.items.length === 2, "CSV Deutsch slider items were not imported.");
assert(document.getElementById("generatorCommand").textContent.includes(".\\QuestionnaireConfigs\\demo-slider.config.json"), "CSV generator command was not updated.");
assert(document.getElementById("pipelineCommands").textContent.includes(".\\Builds\\demo-slider-1.0.0.apk"), "CSV APK path was not updated.");
assert(!validation.some(issue => issue.level === "error"), "Imported config should have no local editor validation errors.");
assert(importedQuality.status === "pass", "Imported config did not pass builder quality report.");
assert(importedQuality.issueCounts.error === 0, "Imported config should have no builder quality errors.");
assert(importedQuality.counts.slider === 2, "Imported quality report slider count mismatch.");

const sliderTemplate = context.__api.csvTemplateText("slider");
const likertTemplate = context.__api.csvTemplateText("likert");
const multipleChoiceTemplate = context.__api.csvTemplateText("multipleChoice");
const textEntryTemplate = context.__api.csvTemplateText("textEntry");
const temporalTracerTemplate = context.__api.csvTemplateText("temporalTracer");
assert(sliderTemplate.includes("questionType"), "CSV template should include Qualtrics-style questionType metadata.");
assert(sliderTemplate.includes("itemId"), "CSV template should include stable itemId metadata.");
assert(sliderTemplate.includes("branchingTag"), "CSV template should include future branching metadata.");
assert(likertTemplate.includes("likert"), "Likert template should be type-oriented, not MAIA-specific.");
assert(multipleChoiceTemplate.includes("multipleChoice"), "Multiple-choice template should be available as a future import type.");
assert(textEntryTemplate.includes("textEntry"), "Text-entry template should be available as a future import type.");
assert(temporalTracerTemplate.includes("temporalTracer"), "Temporal tracer dimension template should be available as a future import type.");
context.__api.downloadCsvTemplate();
const pictographicManifest = context.__api.pictographicZipManifestText();
assert(pictographicManifest.includes("imageFileName"), "Pictographic ZIP manifest should tell users where to replace PNG filenames.");
assert(pictographicManifest.includes("prompt_001.png"), "Pictographic ZIP manifest should reference placeholder PNGs.");
context.__api.downloadPictographicZipTemplate();

const pictographicDataUrlConfig = JSON.parse(JSON.stringify(imported));
pictographicDataUrlConfig.blocks.splice(1, 0, {
  id: "pictographic",
  type: "pictographic",
  choices: ["A", "B", "C"],
  prompts: [
    {
      id: "custom_scale",
      imageFileName: "custom-scale.png",
      source: "uploaded://custom-scale.png",
      dataUrl: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=",
      promptEnglish: "Choose the custom scale.",
      promptDeutsch: "Waehlen Sie die benutzerdefinierte Skala.",
      choices: ["A", "B", "C"]
    }
  ]
});
pictographicDataUrlConfig.chainDefaults.questionnaireSequence = ["demographics", "pictographic"];
pictographicDataUrlConfig.chainDefaults.questionnaireMode = "full";
context.__api.loadConfig(pictographicDataUrlConfig);
const pictographicLoaded = context.__api.buildConfig();
assert(pictographicLoaded.blocks.some(block => block.id === "pictographic" && block.prompts[0].dataUrl), "Pictographic uploaded PNG data should survive config reload.");
assert(pictographicLoaded.chainDefaults.questionnaireSequence.join(",") === "demographics,pictographic", "Pictographic reload should preserve block 1 sequence.");
assert(!context.__api.validate(pictographicLoaded).some(issue => issue.level === "error"), "Pictographic dataUrl config should pass local editor validation.");

const templateImport = loadEditor();
applyCsvStressTriggerCatalog(templateImport);
templateImport.context.__api.applyCsvText(sliderTemplate, "questionnaire-slider-template.csv");
const templateConfig = JSON.parse(templateImport.document.getElementById("preview").textContent);
const templateQuality = templateImport.context.__api.qualityReport(templateConfig);
assert(templateConfig.questionnaireId === "custom-slider-demo", "Slider CSV template should import as a buildable custom questionnaire.");
assert(templateQuality.status === "pass", "Slider CSV template import should pass quality guardrails.");

const csvStressResults = [
  runCsvStressScenario({
    id: "csv-stress-001",
    expectedCount: 1,
    csv: sliderCsv("csv-stress-001", 1),
    expectQualityStatus: "pass",
    expectValidationErrors: false
  }),
  runCsvStressScenario({
    id: "csv-stress-012",
    expectedCount: 12,
    csv: sliderCsv("csv-stress-012", 12, { quotedExample: true }),
    expectQualityStatus: "pass",
    expectValidationErrors: false,
    expectQuotedText: true
  }),
  runCsvStressScenario({
    id: "csv-stress-066",
    expectedCount: 66,
    csv: sliderCsv("csv-stress-066", 66),
    expectQualityStatus: "pass",
    expectValidationErrors: false,
    expectWarningMinimum: 1
  }),
  runCsvStressScenario({
    id: "csv-stress-091",
    expectedCount: 91,
    csv: sliderCsv("csv-stress-091", 91),
    expectQualityStatus: "fail",
    expectValidationErrors: false,
    expectErrorMinimum: 1
  }),
  runCsvStressScenario({
    id: "csv-stress-invalid-scale",
    expectedCount: 2,
    csv: sliderCsv("csv-stress-invalid-scale", 2, { min: -50, max: 50 }),
    expectQualityStatus: "fail",
    expectErrorMinimum: 1
  })
];

const unsupportedFormatError = assertCsvImportThrows(
  sliderCsv("csv-unsupported-format", 1, { format: "multipleChoice" }),
  "csv-unsupported-format.csv",
  "unsupported slider format"
);
const likertImport = loadEditor();
applyCsvStressTriggerCatalog(likertImport);
likertImport.document.getElementById("triggerModule0_slider").checked = false;
likertImport.document.getElementById("triggerModule0_maia2").checked = true;
likertImport.context.__api.applyCsvText(likertTemplate, "questionnaire-likert-template.csv");
likertImport.context.__api.refresh();
const likertImportedConfig = JSON.parse(likertImport.document.getElementById("preview").textContent);
const likertImportedBlock = likertImportedConfig.blocks.find(block => block.id === "maia2");
assert(likertImportedConfig.questionnaireId === "custom-likert-demo", "Generic Likert CSV should import as a custom questionnaire.");
assert(likertImportedBlock && likertImportedBlock.expectedItemCount === 2, "Generic Likert CSV should set the imported Likert item count.");
assert(likertImportedBlock.items.length === 2, "Generic Likert CSV should populate inline Likert items.");
assert(likertImport.context.__api.qualityReport(likertImportedConfig).status === "pass", "Generic Likert CSV import should pass quality guardrails.");
const unsupportedTemporalTracerError = assertCsvImportThrows(
  temporalTracerTemplate,
  "questionnaire-temporal-tracer-template.csv",
  "unsupported block"
);

const duplicate = JSON.parse(JSON.stringify(imported));
const duplicateSlider = duplicate.blocks.find(block => block.id === "custom_slider");
duplicateSlider.languages.English.items[1] = duplicateSlider.languages.English.items[0];
const duplicateQuality = context.__api.qualityReport(duplicate);
assert(duplicateQuality.status === "fail", "Duplicate item quality report should fail.");
assert(duplicateQuality.issues.some(issue => issue.text.includes("duplicates another item")), "Duplicate item issue was not reported.");

const multiTriggerGuiStressResults = [2, 3, 4].map(runMultiTriggerGuiScenario);

const summary = {
  status: "pass",
  defaultQuestionnaireId: initial.questionnaireId,
  defaultQualityStatus: initialQuality.status,
  defaultQualityWarnings: initialQuality.issueCounts.warning,
  handoffQuestionnaireId: handoff.questionnaireId,
  handoffQualityStatus: handoffQuality.status,
  handoffPassiveTriggerWarnings: handoff.triggerQuestionnaireMapping.passiveTriggerWarnings.length,
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
  csvTemplateKinds: ["slider", "likert", "multipleChoice", "textEntry", "temporalTracer"],
  csvTemplateImportStatus: templateQuality.status,
  blockSequenceStatus: "pass",
  customBlock1Sequence: customSequenced.chainDefaults.questionnaireSequence,
  customUnityReturnSequence: customSequenced.triggerQuestionnaireMapping.triggers[0].questionnaireSequence,
  pictographicZipTemplateStatus: "pass",
  pictographicDataUrlConfigStatus: "pass",
  csvStressResults,
  csvUnsupportedTypeErrors: {
    unsupportedFormat: unsupportedFormatError,
    temporalTracer: unsupportedTemporalTracerError
  },
  duplicateGuardrailStatus: duplicateQuality.status,
  multiTriggerGuiStressStatus: "pass",
  multiTriggerGuiStressResults: multiTriggerGuiStressResults.map(result => ({
    triggerCount: result.triggerCount,
    catalogPath: result.catalogPath,
    blockSegmentCount: result.blockSegmentCount,
    unassignedQualityStatus: result.unassignedQualityStatus,
    assignedQualityStatus: result.assignedQualityStatus,
    assignedModules: result.assignedModules,
    assignedRegisteredBlocks: result.assignedRegisteredBlocks
  })),
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

async function runApkUploadScanScenario() {
  const test = loadEditor();
  const catalog = {
    schemaVersion: "mq.quest_questionnaire_trigger_catalog.v1",
    catalogVersion: "1.0.0",
    scenarioId: "apk-upload-demo",
    package: "org.questquestionnaire.apkuploaddemo",
    activity: "org.questquestionnaire.apkuploaddemo.UnityPlayerActivity",
    label: "APK Upload Demo",
    triggers: [
      { triggerId: "midpoint", label: "Midpoint" },
      { triggerId: "trigger_1_complete", label: "After trigger 1" }
    ]
  };
  const bytes = storedZip({
    "assets/mq/questionnaire-trigger-catalog.json": JSON.stringify(catalog)
  });
  const file = {
    name: "apk-upload-demo.apk",
    async arrayBuffer() {
      return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    }
  };
  await test.context.__api.loadTriggerCatalogFile(file);
  const blockHtml = test.document.getElementById("triggerMappingList").innerHTML;
  const blockSegmentCount = (blockHtml.match(/class="block-segment study-block"/g) || []).length;
  assert(blockSegmentCount === 3, "APK upload scan should create Block 1 plus one block per trigger.");
  assert(blockHtml.includes('id="block-segment-startup"'), "APK upload scan should create the startup block segment.");
  assert(blockHtml.includes('id="block-segment-trigger-0"'), "APK upload scan should create trigger block 0.");
  assert(blockHtml.includes('id="block-segment-trigger-1"'), "APK upload scan should create trigger block 1.");
  assert(test.document.getElementById("stagedScenarioApkPath").value === "C:\\staged\\apk-upload-demo.apk", "APK upload scan should stage the scenario APK for install.");
  return {
    blockSegmentCount,
    triggerCount: test.context.__api.buildConfig().triggerQuestionnaireMapping.triggers.length,
    stagedScenarioApkPath: test.document.getElementById("stagedScenarioApkPath").value
  };
}

async function finish() {
  const apkUploadScan = await runApkUploadScanScenario();
  const multiTriggerApkUploadResults = await Promise.all([2, 3, 4].map(runMultiTriggerApkUploadScenario));
  summary.apkUploadScanAction = "pass";
  summary.apkUploadTriggerCount = apkUploadScan.triggerCount;
  summary.apkUploadBlockSegmentCount = apkUploadScan.blockSegmentCount;
  summary.apkUploadStagedScenarioApkPath = apkUploadScan.stagedScenarioApkPath;
  summary.multiTriggerApkUploadScanStatus = "pass";
  summary.multiTriggerApkUploadResults = multiTriggerApkUploadResults;

if (outputDir) {
  fs.mkdirSync(outputDir, { recursive: true });
  const initialConfigPath = path.join(outputDir, "quest-questionnaire-study.config.json");
  const importedConfigPath = path.join(outputDir, "demo-slider.config.json");
  const stressConfigPath = path.join(outputDir, "csv-stress-012.config.json");
  const stressQualityPath = path.join(outputDir, "csv-stress-012.quality-report.json");
  const handoffConfigPath = path.join(outputDir, "quest-questionnaire-stimulus-handoff.config.json");
  const handoffQualityPath = path.join(outputDir, "quest-questionnaire-stimulus-handoff.quality-report.json");
  const handoffChainPlanPath = path.join(outputDir, "quest-questionnaire-stimulus-handoff.chainlink-plan.json");
  const customSequencedConfigPath = path.join(outputDir, "custom-block-sequences.config.json");
  const customSequencedQualityPath = path.join(outputDir, "custom-block-sequences.quality-report.json");
  const twoDStartConfigPath = path.join(outputDir, "quest-questionnaire-stimulus-2d-first.config.json");
  const twoDStartQualityPath = path.join(outputDir, "quest-questionnaire-stimulus-2d-first.quality-report.json");
  const pictographicDataUrlConfigPath = path.join(outputDir, "pictographic-dataurl.config.json");
  const pictographicDataUrlQualityPath = path.join(outputDir, "pictographic-dataurl.quality-report.json");
  const summaryPath = path.join(outputDir, "builder-smoke-summary.json");
  const importedQualityPath = path.join(outputDir, "demo-slider.quality-report.json");
  const initialChainPlanPath = path.join(outputDir, "quest-questionnaire-study.chainlink-plan.json");
  const stressEditor = loadEditor();
  applyCsvStressTriggerCatalog(stressEditor);
  stressEditor.context.__api.applyCsvText(sliderCsv("csv-stress-012", 12, { quotedExample: true }), "csv-stress-012.csv");
  const stressConfig = JSON.parse(stressEditor.document.getElementById("preview").textContent);
  const stressQuality = stressEditor.context.__api.qualityReport(stressConfig);
  fs.writeFileSync(initialConfigPath, `${JSON.stringify(initial, null, 2)}\n`, "utf8");
  fs.writeFileSync(initialChainPlanPath, `${JSON.stringify(initialChainPlan, null, 2)}\n`, "utf8");
  fs.writeFileSync(handoffConfigPath, `${JSON.stringify(handoff, null, 2)}\n`, "utf8");
  fs.writeFileSync(handoffQualityPath, `${JSON.stringify(handoffQuality, null, 2)}\n`, "utf8");
  fs.writeFileSync(handoffChainPlanPath, `${JSON.stringify(handoffPlan, null, 2)}\n`, "utf8");
  fs.writeFileSync(customSequencedConfigPath, `${JSON.stringify(customSequenced, null, 2)}\n`, "utf8");
  fs.writeFileSync(customSequencedQualityPath, `${JSON.stringify(context.__api.qualityReport(customSequenced), null, 2)}\n`, "utf8");
  fs.writeFileSync(twoDStartConfigPath, `${JSON.stringify(twoDStart, null, 2)}\n`, "utf8");
  fs.writeFileSync(twoDStartQualityPath, `${JSON.stringify(twoDStartQuality, null, 2)}\n`, "utf8");
  fs.writeFileSync(pictographicDataUrlConfigPath, `${JSON.stringify(pictographicLoaded, null, 2)}\n`, "utf8");
  fs.writeFileSync(pictographicDataUrlQualityPath, `${JSON.stringify(context.__api.qualityReport(pictographicLoaded), null, 2)}\n`, "utf8");
  fs.writeFileSync(importedConfigPath, `${JSON.stringify(imported, null, 2)}\n`, "utf8");
  fs.writeFileSync(importedQualityPath, `${JSON.stringify(importedQuality, null, 2)}\n`, "utf8");
  fs.writeFileSync(stressConfigPath, `${JSON.stringify(stressConfig, null, 2)}\n`, "utf8");
  fs.writeFileSync(stressQualityPath, `${JSON.stringify(stressQuality, null, 2)}\n`, "utf8");
  summary.multiTriggerConfigs = [];
  multiTriggerGuiStressResults.forEach(result => {
    const configPath = path.join(outputDir, `multi-trigger-${result.triggerCount}.config.json`);
    const qualityPath = path.join(outputDir, `multi-trigger-${result.triggerCount}.quality-report.json`);
    fs.writeFileSync(configPath, `${JSON.stringify(result.assigned, null, 2)}\n`, "utf8");
    fs.writeFileSync(qualityPath, `${JSON.stringify(result.assignedQuality, null, 2)}\n`, "utf8");
    summary.multiTriggerConfigs.push({
      triggerCount: result.triggerCount,
      config: configPath,
      qualityReport: qualityPath
    });
  });
  ["slider", "likert", "multipleChoice", "textEntry", "temporalTracer"].forEach(kind => {
    fs.writeFileSync(path.join(outputDir, `questionnaire-${kind}-template.csv`), context.__api.csvTemplateText(kind), "utf8");
  });
  fs.writeFileSync(path.join(outputDir, "questionnaire-pictographic-template-manifest.txt"), context.__api.pictographicZipManifestText(), "utf8");
  summary.initialConfig = initialConfigPath;
  summary.initialChainPlan = initialChainPlanPath;
  summary.handoffConfig = handoffConfigPath;
  summary.handoffQualityReport = handoffQualityPath;
  summary.handoffChainPlan = handoffChainPlanPath;
  summary.customSequencedConfig = customSequencedConfigPath;
  summary.customSequencedQualityReport = customSequencedQualityPath;
  summary.twoDStartConfig = twoDStartConfigPath;
  summary.twoDStartQualityReport = twoDStartQualityPath;
  summary.pictographicDataUrlConfig = pictographicDataUrlConfigPath;
  summary.pictographicDataUrlQualityReport = pictographicDataUrlQualityPath;
  summary.importedConfig = importedConfigPath;
  summary.importedQualityReport = importedQualityPath;
  summary.stressConfig = stressConfigPath;
  summary.stressQualityReport = stressQualityPath;
  summary.summary = summaryPath;
  fs.writeFileSync(summaryPath, `${JSON.stringify(summary, null, 2)}\n`, "utf8");
}

  console.log(JSON.stringify(summary, null, 2));
}

finish().catch(error => {
  console.error(error && error.stack ? error.stack : error);
  process.exit(1);
});
