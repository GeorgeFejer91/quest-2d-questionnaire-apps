package org.questquestionnaire.questionnaires2d;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

final class QuestionnaireData {
    private QuestionnaireData() {
    }

    static final class ParticipantInfo {
        String participantId;
        String name;
        int age;
        String gender;
        boolean consent;
        String language;
    }

    static final class RuntimeConfig {
        String schemaVersion;
        String questionnaireId = "quest-questionnaire-maia2";
        String questionnaireVersion = "1.0.0";
        String appVersion = "1.0.0";
        String appDisplayName = "";
        String sourceConfig;
        String sourceRepository = "Quest 2D Questionnaire";
        String sourceCommit = "7f0f7c9a40885aa841892b9a680acf45fa45b2d7";
        String maia2SourcePath = "";
        final List<String> languages = new ArrayList<>();
        final List<RuntimeBlock> blocks = new ArrayList<>();
        RuntimeExportSettings exports = new RuntimeExportSettings();
        RuntimeChainDefaults chainDefaults = new RuntimeChainDefaults();
        RuntimeTriggerQuestionnaireMapping triggerQuestionnaireMapping = new RuntimeTriggerQuestionnaireMapping();

        RuntimeBlock findBlock(String blockId) {
            for (RuntimeBlock block : blocks) {
                if (blockId.equalsIgnoreCase(block.id)) {
                    return block;
                }
            }

            return null;
        }

        static RuntimeConfig fromJson(String json) throws JSONException {
            JSONObject root = new JSONObject(json.trim());
            RuntimeConfig config = new RuntimeConfig();
            config.schemaVersion = root.optString("schemaVersion", "");
            config.questionnaireId = root.optString("questionnaireId", config.questionnaireId);
            config.questionnaireVersion = root.optString("questionnaireVersion", config.questionnaireVersion);
            config.appVersion = root.optString("appVersion", config.appVersion);
            config.appDisplayName = root.optString("appDisplayName", config.appDisplayName);
            config.sourceConfig = root.optString("sourceConfig", "");
            config.sourceRepository = root.optString("sourceRepository", config.sourceRepository);
            config.sourceCommit = root.optString("sourceCommit", config.sourceCommit);
            config.maia2SourcePath = root.optString("maia2SourcePath", config.maia2SourcePath);

            JSONArray languagesJson = root.optJSONArray("languages");
            if (languagesJson != null) {
                for (int i = 0; i < languagesJson.length(); i++) {
                    config.languages.add(languagesJson.optString(i));
                }
            }

            JSONArray blocksJson = root.optJSONArray("blocks");
            if (blocksJson != null) {
                for (int i = 0; i < blocksJson.length(); i++) {
                    JSONObject blockJson = blocksJson.optJSONObject(i);
                    if (blockJson != null) {
                        config.blocks.add(RuntimeBlock.fromJson(blockJson));
                    }
                }
            }

            JSONObject exportsJson = root.optJSONObject("exports");
            if (exportsJson != null) {
                config.exports.destination = exportsJson.optString("destination", config.exports.destination);
                JSONArray formats = exportsJson.optJSONArray("formats");
                if (formats != null) {
                    for (int i = 0; i < formats.length(); i++) {
                        config.exports.formats.add(formats.optString(i));
                    }
                }
            }

            JSONObject chainDefaultsJson = root.optJSONObject("chainDefaults");
            if (chainDefaultsJson != null) {
                config.chainDefaults = RuntimeChainDefaults.fromJson(chainDefaultsJson);
            }

            JSONObject triggerMappingJson = root.optJSONObject("triggerQuestionnaireMapping");
            if (triggerMappingJson != null) {
                config.triggerQuestionnaireMapping = RuntimeTriggerQuestionnaireMapping.fromJson(triggerMappingJson);
            }

            return config;
        }

        String displayTitle() {
            return appDisplayName != null && !appDisplayName.trim().isEmpty()
                ? appDisplayName.trim()
                : "Questionnaire";
        }

        RuntimeTriggerMapping findTriggerMapping(String triggerId) {
            if (triggerId == null || triggerId.trim().isEmpty() || triggerQuestionnaireMapping == null) {
                return null;
            }

            for (RuntimeTriggerMapping mapping : triggerQuestionnaireMapping.triggers) {
                if (mapping.enabled && triggerId.equalsIgnoreCase(mapping.triggerId)) {
                    return mapping;
                }
            }

            return null;
        }
    }

    static final class RuntimeBlock {
        String id;
        String type;
        int expectedItemCount;
        int min;
        int max;
        boolean wholeNumbers;
        String presentationMode = "";
        String scoreOptionLayout = "vertical";
        RuntimeAnchorSettings anchors;
        final List<RuntimeLanguageSource> languageSources = new ArrayList<>();
        final List<RuntimePictographicPrompt> prompts = new ArrayList<>();
        final List<RuntimeScoreGroup> scoreGroups = new ArrayList<>();
        final List<String> choices = new ArrayList<>();
        RuntimeTemporalAxis temporalAxis = RuntimeTemporalAxis.defaults();
        final List<RuntimeTemporalDimension> temporalDimensions = new ArrayList<>();

        static RuntimeBlock fromJson(JSONObject json) throws JSONException {
            RuntimeBlock block = new RuntimeBlock();
            block.id = json.optString("id", "");
            block.type = json.optString("type", "");
            block.expectedItemCount = json.optInt("expectedItemCount", 0);
            block.min = json.optInt("min", 0);
            block.max = json.optInt("max", 0);
            block.wholeNumbers = json.optBoolean("wholeNumbers", false);
            block.presentationMode = json.optString("presentationMode", "");
            block.scoreOptionLayout = normalizeScoreOptionLayout(
                json.optString("scoreOptionLayout", json.optString("optionLayout", json.optString("scoreLayout", "vertical")))
            );

            JSONObject anchorsJson = json.optJSONObject("anchors");
            if (anchorsJson != null) {
                block.anchors = new RuntimeAnchorSettings();
                block.anchors.left = anchorsJson.optString("left", "");
                block.anchors.right = anchorsJson.optString("right", "");
            }

            JSONArray languageSourcesJson = json.optJSONArray("languageSources");
            if (languageSourcesJson != null) {
                for (int i = 0; i < languageSourcesJson.length(); i++) {
                    JSONObject sourceJson = languageSourcesJson.optJSONObject(i);
                    if (sourceJson != null) {
                        RuntimeLanguageSource source = new RuntimeLanguageSource();
                        source.language = sourceJson.optString("language", "");
                        source.source = sourceJson.optString("source", "");
                        source.target = sourceJson.optString("target", "");
                        source.inlineItemCount = sourceJson.optInt("inlineItemCount", 0);
                        block.languageSources.add(source);
                    }
                }
            }

            JSONArray promptsJson = json.optJSONArray("prompts");
            if (promptsJson != null) {
                for (int i = 0; i < promptsJson.length(); i++) {
                    JSONObject promptJson = promptsJson.optJSONObject(i);
                    if (promptJson != null) {
                        RuntimePictographicPrompt prompt = new RuntimePictographicPrompt();
                        prompt.id = promptJson.optString("id", "");
                        prompt.imageFileName = promptJson.optString("imageFileName", "");
                        prompt.source = promptJson.optString("source", "");
                        prompt.promptEnglish = nullIfJsonNull(promptJson, "promptEnglish");
                        prompt.promptDeutsch = nullIfJsonNull(promptJson, "promptDeutsch");
                        JSONArray choicesJson = promptJson.optJSONArray("choices");
                        if (choicesJson != null) {
                            for (int choice = 0; choice < choicesJson.length(); choice++) {
                                prompt.choices.add(choicesJson.optString(choice));
                            }
                        }
                        block.prompts.add(prompt);
                    }
                }
            }

            JSONArray scoreGroupsJson = json.optJSONArray("scoreGroups");
            if (scoreGroupsJson != null) {
                for (int i = 0; i < scoreGroupsJson.length(); i++) {
                    JSONObject groupJson = scoreGroupsJson.optJSONObject(i);
                    if (groupJson != null) {
                        RuntimeScoreGroup group = new RuntimeScoreGroup();
                        group.id = groupJson.optString("id", "");
                        group.label = groupJson.optString("label", "");
                        JSONArray itemsJson = groupJson.optJSONArray("items");
                        if (itemsJson != null) {
                            for (int item = 0; item < itemsJson.length(); item++) {
                                group.items.add(itemsJson.optInt(item));
                            }
                        }
                        block.scoreGroups.add(group);
                    }
                }
            }

            JSONArray choicesJson = json.optJSONArray("choices");
            if (choicesJson != null) {
                for (int i = 0; i < choicesJson.length(); i++) {
                    block.choices.add(choicesJson.optString(i));
                }
            }

            JSONObject temporalAxisJson = json.optJSONObject("axis");
            if (temporalAxisJson != null) {
                block.temporalAxis = RuntimeTemporalAxis.fromJson(temporalAxisJson, block.temporalAxis);
            }

            JSONArray dimensionsJson = json.optJSONArray("dimensions");
            if (dimensionsJson != null) {
                for (int i = 0; i < dimensionsJson.length(); i++) {
                    JSONObject dimensionJson = dimensionsJson.optJSONObject(i);
                    if (dimensionJson != null) {
                        block.temporalDimensions.add(RuntimeTemporalDimension.fromJson(dimensionJson, block.temporalAxis, i));
                    }
                }
            }

            return block;
        }

        private static String normalizeScoreOptionLayout(String value) {
            String cleaned = value == null ? "" : value.trim().toLowerCase(Locale.US).replaceAll("[\\s_-]+", "");
            if ("horizontal".equals(cleaned) || "inline".equals(cleaned) || "row".equals(cleaned)) {
                return "horizontal";
            }
            return "vertical";
        }
    }

    static final class RuntimeAnchorSettings {
        String left;
        String right;
    }

    static final class RuntimeLanguageSource {
        String language;
        String source;
        String target;
        int inlineItemCount;
    }

    static final class RuntimePictographicPrompt {
        String id;
        String imageFileName;
        String source;
        String promptEnglish;
        String promptDeutsch;
        final List<String> choices = new ArrayList<>();

        String promptForLanguage(String language) {
            String configured = "Deutsch".equals(language) ? promptDeutsch : promptEnglish;
            if (configured != null && !configured.trim().isEmpty()) {
                return configured;
            }

            return defaultPrompt(id, language);
        }
    }

    static final class RuntimeScoreGroup {
        String id;
        String label;
        final List<Integer> items = new ArrayList<>();
    }

    static final class RuntimeTemporalAxis {
        int viewBoxWidth = 1000;
        int viewBoxHeight = 100;
        double xMin = 0.0;
        double xMax = 10.0;
        String xUnit = "min";
        double yMin = 0.0;
        double yMax = 100.0;
        String yMinLabel = "No, not more than usual";
        String yMaxLabel = "Yes, very much more than usual";
        double startGatePercent = 5.0;
        double endGatePercent = 95.0;
        int targetSampleCount = 1000;
        double strokeWidth = 2.5;
        int traceColor = rgb(40, 209, 124);
        int axisColor = rgb(244, 245, 247);
        int gridColor = rgb(127, 135, 148);
        final List<String> xBins = new ArrayList<>();
        final List<String> yBins = new ArrayList<>();

        static RuntimeTemporalAxis defaults() {
            RuntimeTemporalAxis axis = new RuntimeTemporalAxis();
            axis.xBins.add("0");
            axis.xBins.add("2");
            axis.xBins.add("4");
            axis.xBins.add("6");
            axis.xBins.add("8");
            axis.xBins.add("10 min");
            axis.yBins.add(axis.yMaxLabel);
            axis.yBins.add("Middle");
            axis.yBins.add(axis.yMinLabel);
            return axis;
        }

        static RuntimeTemporalAxis fromJson(JSONObject json, RuntimeTemporalAxis fallback) {
            RuntimeTemporalAxis base = fallback != null ? fallback : defaults();
            RuntimeTemporalAxis axis = new RuntimeTemporalAxis();
            axis.viewBoxWidth = Math.max(10, json.optInt("viewBoxWidth", base.viewBoxWidth));
            axis.viewBoxHeight = Math.max(10, json.optInt("viewBoxHeight", base.viewBoxHeight));
            axis.xMin = json.optDouble("xMin", base.xMin);
            axis.xMax = json.optDouble("xMax", base.xMax);
            axis.xUnit = json.optString("xUnit", base.xUnit);
            axis.yMin = json.optDouble("yMin", base.yMin);
            axis.yMax = json.optDouble("yMax", base.yMax);
            axis.yMinLabel = json.optString("yMinLabel", base.yMinLabel);
            axis.yMaxLabel = json.optString("yMaxLabel", base.yMaxLabel);
            axis.startGatePercent = TemporalTraceMath.clamp(json.optDouble("startGatePercent", base.startGatePercent), 0.0, 49.0);
            axis.endGatePercent = TemporalTraceMath.clamp(json.optDouble("endGatePercent", base.endGatePercent), 51.0, 100.0);
            axis.targetSampleCount = Math.max(2, json.optInt("targetSampleCount", base.targetSampleCount));
            axis.strokeWidth = Math.max(0.1, json.optDouble("strokeWidth", base.strokeWidth));
            axis.traceColor = parseColor(json.optString("traceColor", ""), base.traceColor);
            axis.axisColor = parseColor(json.optString("axisColor", ""), base.axisColor);
            axis.gridColor = parseColor(json.optString("gridColor", ""), base.gridColor);
            axis.xBins.addAll(nonEmptyStringList(json, "xBins", base.xBins));
            axis.yBins.addAll(nonEmptyStringList(json, "yBins", base.yBins));
            if (axis.xBins.isEmpty()) {
                axis.xBins.addAll(defaults().xBins);
            }
            if (axis.yBins.isEmpty()) {
                axis.yBins.add(axis.yMaxLabel);
                axis.yBins.add("Middle");
                axis.yBins.add(axis.yMinLabel);
            }
            return axis;
        }

        double xAxisAt(double u) {
            return xMin + TemporalTraceMath.clamp(u, 0.0, 1.0) * (xMax - xMin);
        }

        double yAxisAt(double v) {
            return yMin + TemporalTraceMath.clamp(v, 0.0, 1.0) * (yMax - yMin);
        }
    }

    static final class RuntimeTemporalDimension {
        String id;
        String language = "English";
        int order;
        String dimensionLabel;
        String dimensionDescription;
        boolean required = true;
        String audioFile = "";
        RuntimeTemporalAxis axis;

        static RuntimeTemporalDimension fromJson(JSONObject json, RuntimeTemporalAxis fallbackAxis, int index) {
            RuntimeTemporalDimension dimension = new RuntimeTemporalDimension();
            dimension.id = json.optString("id", "trace_" + (index + 1));
            dimension.language = json.optString("language", "English");
            dimension.order = json.optInt("order", index + 1);
            dimension.dimensionLabel = json.optString("dimensionLabel", json.optString("label", dimension.id));
            dimension.dimensionDescription = json.optString("dimensionDescription", json.optString("description", ""));
            dimension.required = json.optBoolean("required", true);
            dimension.audioFile = json.optString("audioFile", "");
            JSONObject axisJson = json.optJSONObject("axis");
            dimension.axis = axisJson != null ? RuntimeTemporalAxis.fromJson(axisJson, fallbackAxis) : fallbackAxis;
            if (dimension.axis == null) {
                dimension.axis = RuntimeTemporalAxis.defaults();
            }
            return dimension;
        }
    }

    static final class RuntimeExportSettings {
        String destination = "Application.persistentDataPath/QuestionnaireExports";
        final List<String> formats = new ArrayList<>();
    }

    static final class RuntimeChainDefaults {
        String finishBehavior = "staySaved";
        String startMode = "unityFirst";
        String callerPackage = "";
        String callerActivity = "";
        String nextPackage = "";
        String nextActivity = "";
        String questionnaireMode = "";
        final List<String> questionnaireSequence = new ArrayList<>();
        String triggerId = "";
        String blockNumber = "";
        String blockId = "";
        String saveNamespace = "";
        long autoCloseDelayMs = 2000L;

        static RuntimeChainDefaults fromJson(JSONObject json) {
            RuntimeChainDefaults defaults = new RuntimeChainDefaults();
            defaults.finishBehavior = json.optString("finishBehavior", defaults.finishBehavior);
            defaults.startMode = json.optString("startMode", defaults.startMode);
            defaults.callerPackage = json.optString("callerPackage", defaults.callerPackage);
            defaults.callerActivity = json.optString("callerActivity", defaults.callerActivity);
            defaults.nextPackage = json.optString("nextPackage", defaults.nextPackage);
            defaults.nextActivity = json.optString("nextActivity", defaults.nextActivity);
            defaults.questionnaireMode = json.optString("questionnaireMode", defaults.questionnaireMode);
            defaults.questionnaireSequence.addAll(stringList(json, "questionnaireSequence"));
            defaults.triggerId = json.optString("triggerId", defaults.triggerId);
            defaults.blockNumber = json.optString("blockNumber", defaults.blockNumber);
            defaults.blockId = json.optString("blockId", defaults.blockId);
            defaults.saveNamespace = json.optString("saveNamespace", defaults.saveNamespace);
            defaults.autoCloseDelayMs = Math.max(0L, json.optLong("autoCloseDelayMs", defaults.autoCloseDelayMs));
            return defaults;
        }
    }

    static final class RuntimeTriggerQuestionnaireMapping {
        String schemaVersion = "";
        final List<RuntimeTriggerMapping> triggers = new ArrayList<>();

        static RuntimeTriggerQuestionnaireMapping fromJson(JSONObject json) {
            RuntimeTriggerQuestionnaireMapping mapping = new RuntimeTriggerQuestionnaireMapping();
            mapping.schemaVersion = json.optString("schemaVersion", mapping.schemaVersion);
            JSONArray triggersJson = json.optJSONArray("triggers");
            if (triggersJson != null) {
                for (int i = 0; i < triggersJson.length(); i++) {
                    JSONObject triggerJson = triggersJson.optJSONObject(i);
                    if (triggerJson != null) {
                        mapping.triggers.add(RuntimeTriggerMapping.fromJson(triggerJson));
                    }
                }
            }
            return mapping;
        }
    }

    static final class RuntimeTriggerMapping {
        String triggerId = "";
        boolean enabled = true;
        String questionnaireMode = "";
        final List<String> questionnaireSequence = new ArrayList<>();
        String blockNumber = "";
        String blockId = "";
        String saveNamespace = "";
        String language = "";
        long autoCloseDelayMs = 2000L;

        static RuntimeTriggerMapping fromJson(JSONObject json) {
            RuntimeTriggerMapping mapping = new RuntimeTriggerMapping();
            mapping.triggerId = json.optString("triggerId", mapping.triggerId);
            mapping.enabled = json.optBoolean("enabled", mapping.enabled);
            mapping.questionnaireMode = json.optString("questionnaireMode", mapping.questionnaireMode);
            mapping.questionnaireSequence.addAll(stringList(json, "questionnaireSequence"));
            mapping.blockNumber = json.optString("blockNumber", mapping.blockNumber);
            mapping.blockId = json.optString("blockId", mapping.blockId);
            mapping.saveNamespace = json.optString("saveNamespace", mapping.saveNamespace);
            mapping.language = json.optString("language", mapping.language);
            mapping.autoCloseDelayMs = Math.max(0L, json.optLong("autoCloseDelayMs", mapping.autoCloseDelayMs));
            return mapping;
        }
    }

    static final class PictographicSelection {
        String promptId;
        String promptText;
        String selectedChoice;
        int order;
        String responseTimestampUtc;
        long responseTimestampUnixMs;
    }

    static final class QuestionnaireAnswer {
        int order;
        String itemText;
        int score;
        String responseTimestampUtc;
        long responseTimestampUnixMs;
    }

    static final class Maia2Answer {
        int order;
        String itemText;
        int score;
        String responseTimestampUtc;
        long responseTimestampUnixMs;
    }

    static final class Maia2ScaleScore {
        String scaleName;
        float score;
    }

    static final class SessionRecord {
        String runId;
        String timestampUtc;
        String sessionId;
        String invocationId;
        String experimentId;
        String scenarioId;
        String trialId;
        String chainId;
        String chainStepId;
        int chainStepIndex = -1;
        String triggerId;
        String finishBehavior;
        String callerPackage;
        String callerActivity;
        String nextPackage;
        String nextActivity;
        String questionnaireMode;
        String questionnaireSequence = "";
        String blockNumber;
        String blockId;
        String saveNamespace;
        String appVersion;
        String unityVersion = "native-android";
        String sourceRepository;
        String sourceCommit;
        String maia2SourcePath;
        String questionnaireConfigId;
        String questionnaireConfigVersion;
        ParticipantInfo participant;
        final List<Maia2Answer> maia2Answers = new ArrayList<>();
        final List<Maia2ScaleScore> maia2Scores = new ArrayList<>();
        final List<PictographicSelection> pictographicSelections = new ArrayList<>();
        final List<QuestionnaireAnswer> questionnaireAnswers = new ArrayList<>();
        final List<TemporalTraceExport> temporalTraces = new ArrayList<>();
    }

    static final class TemporalTraceExport {
        int order;
        String dimensionId = "";
        String dimensionLabel = "";
        String dimensionDescription = "";
        String audioFile = "";
        int rawPointCount;
        int resampledPointCount;
        String svgPath = "";
        String csvPath = "";
        String jsonPath = "";
        String responseTimestampUtc = "";
        long responseTimestampUnixMs;
    }

    static final class LocalizedUiText {
        String inputName = "Please input your name";
        String inputAge = "Please input your age";
        String gender = "Gender";
        String selectGender = "Please select your gender";
        String consent = "Consent";
        String consentText = "I consent to participate in this experiment and understand that my data will be recorded.";
        String submit = "Submit";
        String pleaseAnswer = "Please answer the following questions";
        String notAtAll = "NO, not more than usual";
        String extremely = "YES, much more than usual";
        String thankYou = "Thank you for your participation!";
        String genderFemale = "Female";
        String genderMale = "Male";
        String genderOther = "Other";
        String genderPreferNotToSay = "Prefer not to say";

        static LocalizedUiText fromOriginalLines(List<String> lines) {
            LocalizedUiText text = new LocalizedUiText();
            if (lines == null || lines.size() < 20) {
                return text;
            }

            text.inputName = lines.get(0);
            text.inputAge = lines.get(1);
            text.gender = lines.get(2);
            text.selectGender = lines.get(3);
            text.consent = lines.get(4);
            text.consentText = lines.get(5);
            text.submit = lines.get(6);
            text.pleaseAnswer = lines.get(10);
            text.notAtAll = lines.get(11);
            text.extremely = lines.get(12);
            text.thankYou = lines.get(15);
            text.genderFemale = lines.get(16);
            text.genderMale = lines.get(17);
            text.genderOther = lines.get(18);
            text.genderPreferNotToSay = lines.get(19);
            return text;
        }
    }

    private static String nullIfJsonNull(JSONObject json, String key) {
        if (!json.has(key) || json.isNull(key)) {
            return null;
        }

        return json.optString(key, null);
    }

    private static List<String> stringList(JSONObject json, String key) {
        List<String> values = new ArrayList<>();
        if (!json.has(key) || json.isNull(key)) {
            return values;
        }

        JSONArray array = json.optJSONArray(key);
        if (array != null) {
            for (int i = 0; i < array.length(); i++) {
                String value = array.optString(i, "").trim();
                if (!value.isEmpty()) {
                    values.add(value);
                }
            }
            return values;
        }

        String raw = json.optString(key, "");
        if (!raw.trim().isEmpty()) {
            for (String value : raw.split(",")) {
                String cleaned = value.trim();
                if (!cleaned.isEmpty()) {
                    values.add(cleaned);
                }
            }
        }
        return values;
    }

    private static List<String> nonEmptyStringList(JSONObject json, String key, List<String> fallback) {
        List<String> values = stringList(json, key);
        return values.isEmpty() && fallback != null ? new ArrayList<>(fallback) : values;
    }

    private static int parseColor(String value, int fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }
        try {
            String clean = value.trim();
            if (clean.startsWith("#")) {
                clean = clean.substring(1);
            }
            long parsed = Long.parseLong(clean, 16);
            if (clean.length() == 6) {
                return (int) (0xff000000L | parsed);
            }
            if (clean.length() == 8) {
                return (int) parsed;
            }
            return fallback;
        } catch (NumberFormatException ignored) {
            return fallback;
        }
    }

    private static int rgb(int red, int green, int blue) {
        return (int) (0xff000000L
            | ((red & 0xffL) << 16)
            | ((green & 0xffL) << 8)
            | (blue & 0xffL));
    }

    private static String defaultPrompt(String id, String language) {
        boolean deutsch = "Deutsch".equals(language);
        if ("perceived_body_boundaries".equals(id)) {
            return deutsch
                ? "Bitte geben Sie das Bild an, das Ihre Erfahrung in der virtuellen Realitaet am besten beschreibt. In welchem Ausmass hatten Sie das Gefuehl, dass sich die Grenzen Ihres Koerpers veraendert haben?"
                : "Please indicate the image that best describes your experience in the virtual reality environment. To what extent did you feel that the boundaries of your body were altered?";
        }

        if ("self_extension".equals(id)) {
            return deutsch
                ? "In welchem Ausmass hat sich Ihre Wahrnehmung Ihres eigenen Selbst in der virtuellen Realitaet ausgedehnt? Verwenden Sie die Buchstaben und das folgende Bild, um anzugeben, wie weit sich Ihr Selbst ueber Ihren physischen Koerper hinaus erstreckt."
                : "To what extent has your perception of yourself extended in the virtual reality experience? Using the letters and the following image, indicate how far you believe your self extends beyond your physical body.";
        }

        if ("small_self".equals(id)) {
            return deutsch
                ? "Bitte geben Sie das Bild an, das Ihre Erfahrung in der virtuellen Realitaet am besten beschreibt. In welchem Ausmass hatten Sie das Gefuehl, dass Ihr Gefuehl des Selbst kleiner bzw. vermindert wurde?"
                : "Please indicate the image that best describes your experience in the virtual reality environment. To what extent did you feel that your sense of self diminished?";
        }

        return deutsch
            ? "Bitte waehlen Sie das Bild aus, das Ihre Erfahrung am besten beschreibt."
            : "Please select the image that best describes your experience.";
    }
}
