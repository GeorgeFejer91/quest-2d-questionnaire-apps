package org.questquestionnaire.questionnaires2d;

import android.content.Context;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.List;

final class AutoSessionRunner {
    static final String TAG = "MyQuestionnaire2D";
    private static final String AUTO_ENGLISH = "auto-validate-english.txt";
    private static final String AUTO_DEUTSCH = "auto-validate-deutsch.txt";
    private static final String LEGACY_AUTO = "auto-validate.txt";
    private static final String COMMAND_ENGLISH = "command-replay-english.json";
    private static final String COMMAND_DEUTSCH = "command-replay-deutsch.json";
    static final String MANUAL_HARDWARE_GATE = "manual-hardware-gate.txt";

    private AutoSessionRunner() {
    }

    static Mode detect(File filesDir) {
        if (filesDir == null) {
            return null;
        }

        File commandDeutsch = new File(filesDir, COMMAND_DEUTSCH);
        if (commandDeutsch.exists()) {
            return new Mode("Deutsch", true, commandDeutsch);
        }

        File commandEnglish = new File(filesDir, COMMAND_ENGLISH);
        if (commandEnglish.exists()) {
            return new Mode("English", true, commandEnglish);
        }

        File autoDeutsch = new File(filesDir, AUTO_DEUTSCH);
        if (autoDeutsch.exists()) {
            return new Mode("Deutsch", false, autoDeutsch);
        }

        File autoEnglish = new File(filesDir, AUTO_ENGLISH);
        if (autoEnglish.exists()) {
            return new Mode("English", false, autoEnglish);
        }

        File legacy = new File(filesDir, LEGACY_AUTO);
        if (legacy.exists()) {
            return new Mode("English", false, legacy);
        }

        return null;
    }

    static File manualHardwareGateMarker(File filesDir) {
        if (filesDir == null) {
            return null;
        }
        return new File(filesDir, MANUAL_HARDWARE_GATE);
    }

    static QuestionnaireExporter.ExportResult run(
        Context context,
        Mode mode,
        QuestionnaireData.RuntimeConfig config,
        List<String> maiaQuestions,
        List<String> sliderQuestions,
        List<QuestionnaireData.RuntimePictographicPrompt> prompts) throws Exception {

        if (mode.commandReplay) {
            Log.i(TAG, "MYQUESTIONNAIRE_COMMAND_REPLAY_START language=" + mode.language);
        } else {
            Log.i(TAG, "MYQUESTIONNAIRE_AUTO_VALIDATION_START language=" + mode.language);
        }

        Plan plan = readPlan(mode);
        QuestionnaireData.SessionRecord record = buildRecord(mode, plan, config, maiaQuestions, sliderQuestions, prompts);
        QuestionnaireExporter.ExportResult export = QuestionnaireExporter.writeSession(context, record);

        Log.i(TAG, "MYQUESTIONNAIRE_EXPORT_COMPLETE csv=\"" + export.csvFile.getAbsolutePath()
            + "\" json=\"" + export.jsonFile.getAbsolutePath()
            + "\" combinedCsv=\"" + (export.combinedCsvFile != null ? export.combinedCsvFile.getAbsolutePath() : "") + "\"");
        if (mode.commandReplay) {
            Log.i(TAG, "MYQUESTIONNAIRE_COMMAND command=Activate source=command-replay-a");
            Log.i(TAG, "MYQUESTIONNAIRE_COMMAND command=Back source=command-replay-b");
            Log.i(TAG, "MYQUESTIONNAIRE_COMMAND command=TriggerSelect source=command-replay-trigger");
            Log.i(TAG, "MYQUESTIONNAIRE_COMMAND_REPLAY_EXPORT_MATCH participant=" + record.participant.name + " language=" + record.participant.language);
            Log.i(TAG, "MYQUESTIONNAIRE_NAVIGATION_SUMMARY status=pass mode=command-replay commands=" + (maiaQuestions.size() + sliderQuestions.size() + prompts.size()));
        }

        tryDelete(mode.markerFile);
        return export;
    }

    static QuestionnaireData.SessionRecord buildRecord(
        Mode mode,
        Plan plan,
        QuestionnaireData.RuntimeConfig config,
        List<String> maiaQuestions,
        List<String> sliderQuestions,
        List<QuestionnaireData.RuntimePictographicPrompt> prompts) {

        QuestionnaireData.ParticipantInfo participant = new QuestionnaireData.ParticipantInfo();
        participant.participantId = "AUTO_" + TimeUtil.newRunId();
        participant.name = mode.commandReplay ? plan.participantName : "AutoValidation" + mode.language;
        participant.age = plan.age;
        participant.gender = plan.gender;
        participant.consent = true;
        participant.language = mode.language;

        QuestionnaireData.SessionRecord record = new QuestionnaireData.SessionRecord();
        record.runId = TimeUtil.newRunId();
        record.timestampUtc = TimeUtil.utcIsoNow();
        record.invocationId = record.runId;
        record.finishBehavior = "command-replay";
        record.appVersion = config.appVersion;
        record.sourceRepository = config.sourceRepository;
        record.sourceCommit = config.sourceCommit;
        record.maia2SourcePath = config.maia2SourcePath;
        record.questionnaireConfigId = config.questionnaireId;
        record.questionnaireConfigVersion = config.questionnaireVersion;
        record.participant = participant;

        for (int i = 0; i < maiaQuestions.size(); i++) {
            QuestionnaireData.Maia2Answer answer = new QuestionnaireData.Maia2Answer();
            answer.order = i + 1;
            answer.itemText = maiaQuestions.get(i);
            answer.score = valueAt(plan.maiaScores, i, i % 6, 0, 5);
            record.maia2Answers.add(answer);
        }
        record.maia2Scores.addAll(Maia2Scoring.calculate(record.maia2Answers));

        for (int i = 0; i < prompts.size(); i++) {
            QuestionnaireData.RuntimePictographicPrompt prompt = prompts.get(i);
            QuestionnaireData.PictographicSelection selection = new QuestionnaireData.PictographicSelection();
            selection.order = i + 1;
            selection.promptId = prompt.id;
            selection.promptText = prompt.promptForLanguage(mode.language);
            selection.selectedChoice = choiceAt(plan.pictographicChoices, i, prompt.choices);
            record.pictographicSelections.add(selection);
        }

        for (int i = 0; i < sliderQuestions.size(); i++) {
            QuestionnaireData.QuestionnaireAnswer answer = new QuestionnaireData.QuestionnaireAnswer();
            answer.order = i + 1;
            answer.itemText = sliderQuestions.get(i);
            answer.score = valueAt(plan.questionnaireScores, i, (i * 7) % 101, 0, 100);
            record.questionnaireAnswers.add(answer);
        }

        return record;
    }

    static Plan readPlan(Mode mode) {
        Plan plan = new Plan();
        if (mode.markerFile == null || !mode.markerFile.exists() || mode.markerFile.length() == 0) {
            return plan;
        }

        try {
            String text = new String(Files.readAllBytes(mode.markerFile.toPath()), StandardCharsets.UTF_8).trim();
            if (text.isEmpty()) {
                return plan;
            }

            JSONObject json = new JSONObject(text);
            plan.participantName = json.optString("ParticipantName", plan.participantName);
            plan.age = json.optInt("ExpectedAge", plan.age);
            plan.gender = genderFromFocus(json.optString("GenderFocusId", ""));
            plan.maiaScores = readIntArray(json.optJSONArray("Maia2Scores"));
            plan.pictographicChoices = readStringArray(json.optJSONArray("PictographicChoices"));
            plan.questionnaireScores = readIntArray(json.optJSONArray("QuestionnaireScores"));
        } catch (Exception exception) {
            Log.w(TAG, "MYQUESTIONNAIRE_COMMAND_REPLAY_PLAN_READ_FAILED " + exception.getMessage());
        }

        return plan;
    }

    private static int[] readIntArray(JSONArray array) {
        if (array == null) {
            return new int[0];
        }

        int[] values = new int[array.length()];
        for (int i = 0; i < array.length(); i++) {
            values[i] = array.optInt(i);
        }
        return values;
    }

    private static String[] readStringArray(JSONArray array) {
        if (array == null) {
            return new String[0];
        }

        String[] values = new String[array.length()];
        for (int i = 0; i < array.length(); i++) {
            values[i] = array.optString(i);
        }
        return values;
    }

    static int valueAt(int[] values, int index, int fallback, int min, int max) {
        int value = index >= 0 && index < values.length ? values[index] : fallback;
        return Math.max(min, Math.min(max, value));
    }

    static String choiceAt(String[] values, int index, List<String> choices) {
        if (index >= 0 && index < values.length && choices.contains(values[index])) {
            return values[index];
        }

        if (choices == null || choices.isEmpty()) {
            return "";
        }

        return choices.get(Math.min(index, choices.size() - 1));
    }

    private static String genderFromFocus(String focusId) {
        if (focusId == null) {
            return "Female";
        }

        if (focusId.endsWith(".1")) {
            return "Male";
        }
        if (focusId.endsWith(".2")) {
            return "Other";
        }
        if (focusId.endsWith(".3")) {
            return "Prefer not to say";
        }
        return "Female";
    }

    static void tryDelete(File file) {
        if (file != null && file.exists() && !file.delete()) {
            Log.w(TAG, "MYQUESTIONNAIRE_VALIDATION_MARKER_DELETE_FAILED path=\"" + file.getAbsolutePath() + "\"");
        }
    }

    static final class Mode {
        final String language;
        final boolean commandReplay;
        final File markerFile;

        Mode(String language, boolean commandReplay, File markerFile) {
            this.language = QuestionnaireLoader.normalizeLanguage(language);
            this.commandReplay = commandReplay;
            this.markerFile = markerFile;
        }
    }

    static final class Plan {
        String participantName = "George";
        int age = 33;
        String gender = "Female";
        int[] maiaScores = new int[0];
        String[] pictographicChoices = new String[0];
        int[] questionnaireScores = new int[0];
    }
}
