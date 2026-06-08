package org.questquestionnaire.questionnaires2d;

import org.json.JSONObject;
import org.junit.Test;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

public final class QuestionnaireContractTest {
    @Test
    public void runtimeConfigParsesExpectedBlocks() throws Exception {
        QuestionnaireData.RuntimeConfig config = QuestionnaireData.RuntimeConfig.fromJson(readAsset("QuestionnaireConfig.json"));

        assertEquals("my-questionnaire-vr.config.v1", config.schemaVersion);
        assertTrue(config.questionnaireId.length() > 0);
        assertTrue(config.displayTitle().length() > 0);
        assertTrue(config.blocks.size() >= 3);
        assertEquals("demographics", config.blocks.get(0).type);
        assertEquals("blackScreen", config.blocks.get(config.blocks.size() - 1).type);
        assertNotNull(config.findBlock("custom_slider"));
        assertTrue(config.findBlock("custom_slider").expectedItemCount > 0);
        if (config.findBlock("maia2") != null) {
            assertEquals(37, config.findBlock("maia2").expectedItemCount);
        }
        if (config.findBlock("pictographic") != null) {
            assertTrue(config.findBlock("pictographic").prompts.size() > 0);
        }
    }

    @Test
    public void runtimeConfigParsesParticipantFacingDisplayName() throws Exception {
        QuestionnaireData.RuntimeConfig config = QuestionnaireData.RuntimeConfig.fromJson(
            "{"
                + "\"schemaVersion\":\"my-questionnaire-vr.config.v1\","
                + "\"questionnaireId\":\"demo-slider\","
                + "\"questionnaireVersion\":\"1.0.0\","
                + "\"appDisplayName\":\"Start Experiment | Questionnaire Stimulus Builder Demo\","
                + "\"blocks\":[],"
                + "\"exports\":{\"formats\":[\"json\",\"csv\"]}"
                + "}");

        assertEquals("Start Experiment | Questionnaire Stimulus Builder Demo", config.displayTitle());
    }

    @Test
    public void assetsHaveExpectedQuestionCounts() throws Exception {
        QuestionnaireData.RuntimeConfig config = QuestionnaireData.RuntimeConfig.fromJson(readAsset("QuestionnaireConfig.json"));
        int sliderExpected = config.findBlock("custom_slider").expectedItemCount;

        assertEquals(sliderExpected, QuestionnaireLoader.parseNonEmptyLines(readAsset("Questions_English.txt")).size());
        assertEquals(sliderExpected, QuestionnaireLoader.parseNonEmptyLines(readAsset("Questions_Deutsch.txt")).size());
        if (config.findBlock("maia2") != null) {
            int maiaExpected = config.findBlock("maia2").expectedItemCount;
            assertEquals(maiaExpected, QuestionnaireLoader.parseMaia2Questions(readAsset("MAIA2_Questions.json")).size());
        }
        assertEquals(20, QuestionnaireLoader.extractLanguageBlock(readAsset("UIText.txt"), "English").size());
        assertEquals(20, QuestionnaireLoader.extractLanguageBlock(readAsset("UIText.txt"), "Deutsch").size());
    }

    @Test
    public void maiaScoringUsesReverseItems() {
        List<QuestionnaireData.Maia2Answer> answers = new ArrayList<>();
        for (int i = 1; i <= 37; i++) {
            QuestionnaireData.Maia2Answer answer = new QuestionnaireData.Maia2Answer();
            answer.order = i;
            answer.itemText = "Q" + i;
            answer.score = 5;
            answers.add(answer);
        }

        List<QuestionnaireData.Maia2ScaleScore> scores = Maia2Scoring.calculate(answers);
        assertEquals(8, scores.size());
        assertEquals("Noticing", scores.get(0).scaleName);
        assertEquals(5f, scores.get(0).score, 0.001f);
        assertEquals("Not-Distracting", scores.get(1).scaleName);
        assertEquals(0f, scores.get(1).score, 0.001f);
        assertEquals("Not-Worrying", scores.get(2).scaleName);
        assertEquals(2f, scores.get(2).score, 0.001f);
    }

    @Test
    public void exportShapeMatchesUnityContract() throws Exception {
        QuestionnaireData.RuntimeConfig config = QuestionnaireData.RuntimeConfig.fromJson(readAsset("QuestionnaireConfig.json"));
        List<String> maia = config.findBlock("maia2") != null
            ? QuestionnaireLoader.parseMaia2Questions(readAsset("MAIA2_Questions.json"))
            : Collections.emptyList();
        List<String> slider = QuestionnaireLoader.parseNonEmptyLines(readAsset("Questions_English.txt"));
        List<QuestionnaireData.RuntimePictographicPrompt> prompts = config.findBlock("pictographic") != null
            ? config.findBlock("pictographic").prompts
            : Collections.emptyList();
        QuestionnaireData.SessionRecord record = AutoSessionRunner.buildRecord(
            new AutoSessionRunner.Mode("English", true, null),
            new AutoSessionRunner.Plan(),
            config,
            maia,
            slider,
            prompts);

        JSONObject json = QuestionnaireExporter.toJson(record);
        String csv = QuestionnaireExporter.toCsv(record);
        String combinedCsv = QuestionnaireExporter.toCombinedCsv(Arrays.asList(json));

        assertEquals("native-android", json.getString("unityVersion"));
        assertEquals(maia.size(), json.getJSONArray("maia2Answers").length());
        assertEquals(maia.size() >= 37 ? 8 : 0, json.getJSONArray("maia2Scores").length());
        assertEquals(prompts.size(), json.getJSONArray("pictographicSelections").length());
        assertEquals(slider.size(), json.getJSONArray("questionnaireAnswers").length());
        assertTrue(csv.startsWith("timestampUtc,participantId,name,age,gender,consent,language,appVersion,unityVersion"));
        if (!maia.isEmpty()) {
            assertTrue(csv.contains("maia2_q001_label"));
        }
        assertTrue(csv.contains(String.format("slider_q%03d_score_0_100", slider.size())));
        if (!prompts.isEmpty()) {
            assertTrue(combinedCsv.contains("_choice_numeric"));
        }
        assertTrue(combinedCsv.contains("blockNumber"));
    }

    @Test
    public void sliderOnlyExportOmitsLegacyAnswerSections() throws Exception {
        QuestionnaireData.RuntimeConfig config = QuestionnaireData.RuntimeConfig.fromJson(
            "{"
                + "\"schemaVersion\":\"my-questionnaire-vr.config.v1\","
                + "\"questionnaireId\":\"slider-only-demo\","
                + "\"questionnaireVersion\":\"0.1.0\","
                + "\"appVersion\":\"0.1.0\","
                + "\"languages\":[\"English\",\"Deutsch\"],"
                + "\"blocks\":["
                + "{\"id\":\"demographics\",\"type\":\"demographics\"},"
                + "{\"id\":\"custom_slider\",\"type\":\"slider\",\"expectedItemCount\":2,\"min\":0,\"max\":100,\"wholeNumbers\":true,"
                + "\"anchors\":{\"left\":\"No\",\"right\":\"Yes\"}},"
                + "{\"id\":\"end\",\"type\":\"blackScreen\"}"
                + "],"
                + "\"exports\":{\"destination\":\"getExternalFilesDir(null)/QuestionnaireExports\",\"formats\":[\"json\",\"csv\"]}"
                + "}");

        QuestionnaireData.SessionRecord record = AutoSessionRunner.buildRecord(
            new AutoSessionRunner.Mode("English", true, null),
            new AutoSessionRunner.Plan(),
            config,
            Collections.emptyList(),
            Arrays.asList("I felt present.", "The panel was comfortable."),
            Collections.emptyList());

        JSONObject json = QuestionnaireExporter.toJson(record);
        String csv = QuestionnaireExporter.toCsv(record);

        assertEquals(0, json.getJSONArray("maia2Answers").length());
        assertEquals(0, json.getJSONArray("maia2Scores").length());
        assertEquals(0, json.getJSONArray("pictographicSelections").length());
        assertEquals(2, json.getJSONArray("questionnaireAnswers").length());
        assertTrue(!csv.contains("maia2_q001_label"));
        assertTrue(!csv.contains("_choice"));
        assertTrue(csv.contains("slider_q002_score_0_100"));
    }

    private static String readAsset(String name) throws Exception {
        File file = new File("src/main/assets/questionnaire", name);
        if (!file.exists()) {
            file = new File("app/src/main/assets/questionnaire", name);
        }

        return new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8);
    }
}
