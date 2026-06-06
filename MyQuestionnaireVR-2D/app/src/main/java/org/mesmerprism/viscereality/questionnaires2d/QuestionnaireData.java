package org.mesmerprism.viscereality.questionnaires2d;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

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
        String questionnaireId = "viscereality-maia2";
        String questionnaireVersion = "1.0.0";
        String appVersion = "1.0.0";
        String sourceConfig;
        String sourceRepository = "MesmerPrism/Viscereality";
        String sourceCommit = "7f0f7c9a40885aa841892b9a680acf45fa45b2d7";
        String maia2SourcePath = "C:\\Users\\cogpsy-vrlab\\Documents\\GitHub\\maia-2\\questionnaire\\src";
        final List<String> languages = new ArrayList<>();
        final List<RuntimeBlock> blocks = new ArrayList<>();
        RuntimeExportSettings exports = new RuntimeExportSettings();
        RuntimeChainDefaults chainDefaults = new RuntimeChainDefaults();

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

            return config;
        }
    }

    static final class RuntimeBlock {
        String id;
        String type;
        int expectedItemCount;
        int min;
        int max;
        boolean wholeNumbers;
        RuntimeAnchorSettings anchors;
        final List<RuntimeLanguageSource> languageSources = new ArrayList<>();
        final List<RuntimePictographicPrompt> prompts = new ArrayList<>();
        final List<RuntimeScoreGroup> scoreGroups = new ArrayList<>();
        final List<String> choices = new ArrayList<>();

        static RuntimeBlock fromJson(JSONObject json) throws JSONException {
            RuntimeBlock block = new RuntimeBlock();
            block.id = json.optString("id", "");
            block.type = json.optString("type", "");
            block.expectedItemCount = json.optInt("expectedItemCount", 0);
            block.min = json.optInt("min", 0);
            block.max = json.optInt("max", 0);
            block.wholeNumbers = json.optBoolean("wholeNumbers", false);

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

            return block;
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

    static final class RuntimeExportSettings {
        String destination = "Application.persistentDataPath/QuestionnaireExports";
        final List<String> formats = new ArrayList<>();
    }

    static final class RuntimeChainDefaults {
        String finishBehavior = "staySaved";
        String callerPackage = "";
        String callerActivity = "";
        String nextPackage = "";
        String nextActivity = "";
        long autoCloseDelayMs = 2000L;

        static RuntimeChainDefaults fromJson(JSONObject json) {
            RuntimeChainDefaults defaults = new RuntimeChainDefaults();
            defaults.finishBehavior = json.optString("finishBehavior", defaults.finishBehavior);
            defaults.callerPackage = json.optString("callerPackage", defaults.callerPackage);
            defaults.callerActivity = json.optString("callerActivity", defaults.callerActivity);
            defaults.nextPackage = json.optString("nextPackage", defaults.nextPackage);
            defaults.nextActivity = json.optString("nextActivity", defaults.nextActivity);
            defaults.autoCloseDelayMs = Math.max(0L, json.optLong("autoCloseDelayMs", defaults.autoCloseDelayMs));
            return defaults;
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
        String finishBehavior;
        String callerPackage;
        String callerActivity;
        String nextPackage;
        String nextActivity;
        String questionnaireMode;
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
