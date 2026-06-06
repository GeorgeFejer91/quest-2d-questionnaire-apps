package org.viscereality.questionnaires2d;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

final class QuestionnaireExporter {
    static final String EXPORT_FOLDER_NAME = "QuestionnaireExports";
    static final String IN_PROGRESS_FOLDER_NAME = "in_progress";
    static final String SESSION_INDEX_NAME = "session-index.jsonl";
    static final String COMBINED_SESSION_SUFFIX = "_combined.csv";

    private QuestionnaireExporter() {
    }

    static ExportResult writeSession(Context context, QuestionnaireData.SessionRecord record) throws IOException, JSONException {
        File folder = exportFolder(context);

        String safeName = sanitizeFileName(record.participant != null ? record.participant.name : "Unknown");
        String runId = sanitizeFileName(!isBlank(record.runId) ? record.runId : TimeUtil.newRunId());
        String configId = sanitizeFileName(record.questionnaireConfigId);
        String namespace = sanitizeFileName(record.saveNamespace);
        String baseName = sanitizeFileName(runId + "_" + safeName + "_" + (isBlank(namespace) ? "" : namespace + "_") + configId);
        File jsonFile = new File(folder, baseName + ".json");
        File csvFile = new File(folder, baseName + ".csv");

        atomicWriteUtf8(jsonFile, toJson(record).toString(2));
        atomicWriteUtf8(csvFile, toCsv(record));

        ExportResult result = new ExportResult(csvFile, jsonFile, null);
        appendSessionIndex(folder, record, result);
        File combinedCsvFile = writeCombinedSessionCsv(folder, record);
        result = new ExportResult(csvFile, jsonFile, combinedCsvFile);
        writeDraft(context, record, "complete", result);
        return result;
    }

    static File writeDraft(Context context, QuestionnaireData.SessionRecord record, String status) throws IOException, JSONException {
        return writeDraft(context, record, status, null);
    }

    static File exportFolder(Context context) throws IOException {
        File base = context.getExternalFilesDir(null);
        if (base == null) {
            base = context.getFilesDir();
        }

        File folder = new File(base, EXPORT_FOLDER_NAME);
        if (!folder.exists() && !folder.mkdirs()) {
            throw new IOException("Could not create export folder: " + folder);
        }
        return folder;
    }

    static File inProgressFolder(Context context) throws IOException {
        File folder = new File(exportFolder(context), IN_PROGRESS_FOLDER_NAME);
        if (!folder.exists() && !folder.mkdirs()) {
            throw new IOException("Could not create in-progress export folder: " + folder);
        }
        return folder;
    }

    static JSONObject toJson(QuestionnaireData.SessionRecord record) throws JSONException {
        JSONObject root = new JSONObject();
        root.put("runId", record.runId);
        root.put("timestampUtc", record.timestampUtc);
        root.put("sessionId", record.sessionId);
        root.put("invocationId", record.invocationId);
        root.put("experimentId", record.experimentId);
        root.put("scenarioId", record.scenarioId);
        root.put("trialId", record.trialId);
        root.put("chainId", record.chainId);
        root.put("chainStepId", record.chainStepId);
        root.put("chainStepIndex", record.chainStepIndex);
        root.put("finishBehavior", record.finishBehavior);
        root.put("callerPackage", record.callerPackage);
        root.put("callerActivity", record.callerActivity);
        root.put("nextPackage", record.nextPackage);
        root.put("nextActivity", record.nextActivity);
        root.put("questionnaireMode", record.questionnaireMode);
        root.put("blockNumber", record.blockNumber);
        root.put("blockId", record.blockId);
        root.put("saveNamespace", record.saveNamespace);
        root.put("appVersion", record.appVersion);
        root.put("unityVersion", record.unityVersion);
        root.put("sourceRepository", record.sourceRepository);
        root.put("sourceCommit", record.sourceCommit);
        root.put("maia2SourcePath", record.maia2SourcePath);
        root.put("questionnaireConfigId", record.questionnaireConfigId);
        root.put("questionnaireConfigVersion", record.questionnaireConfigVersion);
        root.put("participant", participantToJson(record.participant));
        root.put("maia2Answers", maiaAnswersToJson(record.maia2Answers));
        root.put("maia2Scores", maiaScoresToJson(record.maia2Scores));
        root.put("pictographicSelections", pictographicToJson(record.pictographicSelections));
        root.put("questionnaireAnswers", questionnaireAnswersToJson(record.questionnaireAnswers));
        return root;
    }

    static String toCsv(QuestionnaireData.SessionRecord record) {
        List<String> headers = new ArrayList<>();
        headers.add("timestampUtc");
        headers.add("participantId");
        headers.add("name");
        headers.add("age");
        headers.add("gender");
        headers.add("consent");
        headers.add("language");
        headers.add("appVersion");
        headers.add("unityVersion");
        headers.add("sourceRepository");
        headers.add("sourceCommit");
        headers.add("maia2SourcePath");
        headers.add("questionnaireConfigId");
        headers.add("questionnaireConfigVersion");
        headers.add("runId");
        headers.add("sessionId");
        headers.add("invocationId");
        headers.add("experimentId");
        headers.add("scenarioId");
        headers.add("trialId");
        headers.add("chainId");
        headers.add("chainStepId");
        headers.add("chainStepIndex");
        headers.add("finishBehavior");
        headers.add("callerPackage");
        headers.add("callerActivity");
        headers.add("nextPackage");
        headers.add("nextActivity");
        headers.add("questionnaireMode");
        headers.add("blockNumber");
        headers.add("blockId");
        headers.add("saveNamespace");

        for (QuestionnaireData.Maia2Answer answer : record.maia2Answers) {
            String prefix = String.format(Locale.US, "maia2_q%03d", answer.order);
            headers.add(prefix + "_label");
            headers.add(prefix + "_score_raw_0_5");
            headers.add(prefix + "_timestamp_utc");
            headers.add(prefix + "_timestamp_unix_ms");
        }

        for (QuestionnaireData.Maia2ScaleScore score : record.maia2Scores) {
            headers.add("maia2_score_" + sanitizeHeader(score.scaleName));
        }

        for (QuestionnaireData.PictographicSelection selection : record.pictographicSelections) {
            headers.add(selection.promptId + "_prompt");
            headers.add(selection.promptId + "_choice");
            headers.add(selection.promptId + "_choice_numeric");
            headers.add(selection.promptId + "_timestamp_utc");
            headers.add(selection.promptId + "_timestamp_unix_ms");
        }

        for (QuestionnaireData.QuestionnaireAnswer answer : record.questionnaireAnswers) {
            String prefix = String.format(Locale.US, "viscereality_q%03d", answer.order);
            headers.add(prefix + "_label");
            headers.add(prefix + "_score_0_100");
            headers.add(prefix + "_timestamp_utc");
            headers.add(prefix + "_timestamp_unix_ms");
        }

        QuestionnaireData.ParticipantInfo participant = record.participant;
        List<String> values = new ArrayList<>();
        values.add(record.timestampUtc);
        values.add(participant.participantId);
        values.add(participant.name);
        values.add(Integer.toString(participant.age));
        values.add(participant.gender);
        values.add(participant.consent ? "true" : "false");
        values.add(participant.language);
        values.add(record.appVersion);
        values.add(record.unityVersion);
        values.add(record.sourceRepository);
        values.add(record.sourceCommit);
        values.add(record.maia2SourcePath);
        values.add(record.questionnaireConfigId);
        values.add(record.questionnaireConfigVersion);
        values.add(record.runId);
        values.add(record.sessionId);
        values.add(record.invocationId);
        values.add(record.experimentId);
        values.add(record.scenarioId);
        values.add(record.trialId);
        values.add(record.chainId);
        values.add(record.chainStepId);
        values.add(Integer.toString(record.chainStepIndex));
        values.add(record.finishBehavior);
        values.add(record.callerPackage);
        values.add(record.callerActivity);
        values.add(record.nextPackage);
        values.add(record.nextActivity);
        values.add(record.questionnaireMode);
        values.add(record.blockNumber);
        values.add(record.blockId);
        values.add(record.saveNamespace);

        for (QuestionnaireData.Maia2Answer answer : record.maia2Answers) {
            values.add(answer.itemText);
            values.add(Integer.toString(answer.score));
            values.add(answer.responseTimestampUtc);
            values.add(Long.toString(answer.responseTimestampUnixMs));
        }

        for (QuestionnaireData.Maia2ScaleScore score : record.maia2Scores) {
            values.add(trimFloat(score.score));
        }

        for (QuestionnaireData.PictographicSelection selection : record.pictographicSelections) {
            values.add(selection.promptText);
            values.add(selection.selectedChoice);
            values.add(choiceToNumeric(selection.selectedChoice));
            values.add(selection.responseTimestampUtc);
            values.add(Long.toString(selection.responseTimestampUnixMs));
        }

        for (QuestionnaireData.QuestionnaireAnswer answer : record.questionnaireAnswers) {
            values.add(answer.itemText);
            values.add(Integer.toString(answer.score));
            values.add(answer.responseTimestampUtc);
            values.add(Long.toString(answer.responseTimestampUnixMs));
        }

        return joinCsv(headers) + System.lineSeparator() + joinCsv(values) + System.lineSeparator();
    }

    private static JSONObject participantToJson(QuestionnaireData.ParticipantInfo participant) throws JSONException {
        JSONObject json = new JSONObject();
        if (participant == null) {
            return json;
        }

        json.put("participantId", participant.participantId);
        json.put("name", participant.name);
        json.put("age", participant.age);
        json.put("gender", participant.gender);
        json.put("consent", participant.consent);
        json.put("language", participant.language);
        return json;
    }

    private static JSONArray maiaAnswersToJson(List<QuestionnaireData.Maia2Answer> answers) throws JSONException {
        JSONArray array = new JSONArray();
        for (QuestionnaireData.Maia2Answer answer : answers) {
            JSONObject json = new JSONObject();
            json.put("order", answer.order);
            json.put("itemText", answer.itemText);
            json.put("score", answer.score);
            json.put("responseTimestampUtc", answer.responseTimestampUtc);
            json.put("responseTimestampUnixMs", answer.responseTimestampUnixMs);
            array.put(json);
        }

        return array;
    }

    private static JSONArray maiaScoresToJson(List<QuestionnaireData.Maia2ScaleScore> scores) throws JSONException {
        JSONArray array = new JSONArray();
        for (QuestionnaireData.Maia2ScaleScore score : scores) {
            JSONObject json = new JSONObject();
            json.put("scaleName", score.scaleName);
            json.put("score", score.score);
            array.put(json);
        }

        return array;
    }

    private static JSONArray pictographicToJson(List<QuestionnaireData.PictographicSelection> selections) throws JSONException {
        JSONArray array = new JSONArray();
        for (QuestionnaireData.PictographicSelection selection : selections) {
            JSONObject json = new JSONObject();
            json.put("promptId", selection.promptId);
            json.put("promptText", selection.promptText);
            json.put("selectedChoice", selection.selectedChoice);
            json.put("selectedChoiceNumeric", choiceToNumeric(selection.selectedChoice));
            json.put("order", selection.order);
            json.put("responseTimestampUtc", selection.responseTimestampUtc);
            json.put("responseTimestampUnixMs", selection.responseTimestampUnixMs);
            array.put(json);
        }

        return array;
    }

    private static JSONArray questionnaireAnswersToJson(List<QuestionnaireData.QuestionnaireAnswer> answers) throws JSONException {
        JSONArray array = new JSONArray();
        for (QuestionnaireData.QuestionnaireAnswer answer : answers) {
            JSONObject json = new JSONObject();
            json.put("order", answer.order);
            json.put("itemText", answer.itemText);
            json.put("score", answer.score);
            json.put("responseTimestampUtc", answer.responseTimestampUtc);
            json.put("responseTimestampUnixMs", answer.responseTimestampUnixMs);
            array.put(json);
        }

        return array;
    }

    private static File writeDraft(Context context, QuestionnaireData.SessionRecord record, String status, ExportResult result) throws IOException, JSONException {
        String runId = sanitizeFileName(!isBlank(record.runId) ? record.runId : TimeUtil.newRunId());
        File draft = new File(inProgressFolder(context), runId + "_draft.json");
        JSONObject json = toJson(record);
        json.put("draftStatus", status);
        json.put("draftUpdatedUtc", TimeUtil.utcIsoNow());
        if (result != null) {
            json.put("exportJsonPath", result.jsonFile.getAbsolutePath());
            json.put("exportCsvPath", result.csvFile.getAbsolutePath());
            if (result.combinedCsvFile != null) {
                json.put("combinedCsvPath", result.combinedCsvFile.getAbsolutePath());
            }
        }
        atomicWriteUtf8(draft, json.toString(2));
        return draft;
    }

    private static void appendSessionIndex(File folder, QuestionnaireData.SessionRecord record, ExportResult result) throws IOException, JSONException {
        JSONObject index = new JSONObject();
        index.put("runId", record.runId);
        index.put("timestampUtc", record.timestampUtc);
        index.put("sessionId", record.sessionId);
        index.put("invocationId", record.invocationId);
        index.put("experimentId", record.experimentId);
        index.put("scenarioId", record.scenarioId);
        index.put("trialId", record.trialId);
        index.put("chainId", record.chainId);
        index.put("chainStepId", record.chainStepId);
        index.put("chainStepIndex", record.chainStepIndex);
        index.put("participantId", record.participant != null ? record.participant.participantId : "");
        index.put("participantName", record.participant != null ? record.participant.name : "");
        index.put("language", record.participant != null ? record.participant.language : "");
        index.put("questionnaireConfigId", record.questionnaireConfigId);
        index.put("questionnaireConfigVersion", record.questionnaireConfigVersion);
        index.put("finishBehavior", record.finishBehavior);
        index.put("questionnaireMode", record.questionnaireMode);
        index.put("blockNumber", record.blockNumber);
        index.put("blockId", record.blockId);
        index.put("saveNamespace", record.saveNamespace);
        index.put("jsonPath", result.jsonFile.getAbsolutePath());
        index.put("csvPath", result.csvFile.getAbsolutePath());
        File indexFile = new File(folder, SESSION_INDEX_NAME);
        String line = index.toString() + System.lineSeparator();
        try (FileOutputStream output = new FileOutputStream(indexFile, true)) {
            output.write(line.getBytes(StandardCharsets.UTF_8));
            output.getFD().sync();
        }
    }

    private static File writeCombinedSessionCsv(File folder, QuestionnaireData.SessionRecord currentRecord) throws IOException, JSONException {
        String groupKey = sessionGroupKey(currentRecord);
        File combined = new File(folder, "session_" + sanitizeFileName(groupKey) + COMBINED_SESSION_SUFFIX);
        List<JSONObject> records = readSessionGroupRecords(folder, groupKey);
        if (records.isEmpty()) {
            return combined;
        }

        atomicWriteUtf8(combined, toCombinedCsv(records));
        return combined;
    }

    private static List<JSONObject> readSessionGroupRecords(File folder, String groupKey) throws IOException, JSONException {
        List<JSONObject> records = new ArrayList<>();
        File indexFile = new File(folder, SESSION_INDEX_NAME);
        if (!indexFile.exists()) {
            return records;
        }

        String indexText = new String(Files.readAllBytes(indexFile.toPath()), StandardCharsets.UTF_8);
        String[] lines = indexText.split("\\r?\\n");
        for (String line : lines) {
            if (isBlank(line)) {
                continue;
            }
            JSONObject index = new JSONObject(line);
            if (!groupKey.equals(sessionGroupKey(index))) {
                continue;
            }
            File jsonFile = new File(index.optString("jsonPath", ""));
            if (!jsonFile.exists()) {
                continue;
            }
            records.add(new JSONObject(new String(Files.readAllBytes(jsonFile.toPath()), StandardCharsets.UTF_8)));
        }
        return records;
    }

    static String toCombinedCsv(List<JSONObject> records) throws JSONException {
        Set<String> headers = new LinkedHashSet<>();
        addBaseHeaders(headers);
        for (JSONObject record : records) {
            addDynamicHeaders(headers, record);
        }

        List<String> headerList = new ArrayList<>(headers);
        StringBuilder builder = new StringBuilder();
        builder.append(joinCsv(headerList)).append(System.lineSeparator());
        for (JSONObject record : records) {
            JSONObject flattened = flattenRecordForCombinedCsv(record);
            List<String> values = new ArrayList<>();
            for (String header : headerList) {
                values.add(flattened.optString(header, ""));
            }
            builder.append(joinCsv(values)).append(System.lineSeparator());
        }
        return builder.toString();
    }

    private static void addBaseHeaders(Set<String> headers) {
        headers.add("timestampUtc");
        headers.add("participantId");
        headers.add("name");
        headers.add("age");
        headers.add("gender");
        headers.add("consent");
        headers.add("language");
        headers.add("appVersion");
        headers.add("unityVersion");
        headers.add("sourceRepository");
        headers.add("sourceCommit");
        headers.add("maia2SourcePath");
        headers.add("questionnaireConfigId");
        headers.add("questionnaireConfigVersion");
        headers.add("runId");
        headers.add("sessionId");
        headers.add("invocationId");
        headers.add("experimentId");
        headers.add("scenarioId");
        headers.add("trialId");
        headers.add("chainId");
        headers.add("chainStepId");
        headers.add("chainStepIndex");
        headers.add("finishBehavior");
        headers.add("callerPackage");
        headers.add("callerActivity");
        headers.add("nextPackage");
        headers.add("nextActivity");
        headers.add("questionnaireMode");
        headers.add("blockNumber");
        headers.add("blockId");
        headers.add("saveNamespace");
    }

    private static void addDynamicHeaders(Set<String> headers, JSONObject record) {
        JSONArray maiaAnswers = record.optJSONArray("maia2Answers");
        if (maiaAnswers != null) {
            for (int i = 0; i < maiaAnswers.length(); i++) {
                JSONObject answer = maiaAnswers.optJSONObject(i);
                if (answer == null) {
                    continue;
                }
                String prefix = String.format(Locale.US, "maia2_q%03d", answer.optInt("order", i + 1));
                headers.add(prefix + "_label");
                headers.add(prefix + "_score_raw_0_5");
                headers.add(prefix + "_timestamp_utc");
                headers.add(prefix + "_timestamp_unix_ms");
            }
        }

        JSONArray scores = record.optJSONArray("maia2Scores");
        if (scores != null) {
            for (int i = 0; i < scores.length(); i++) {
                JSONObject score = scores.optJSONObject(i);
                if (score != null) {
                    headers.add("maia2_score_" + sanitizeHeader(score.optString("scaleName", "")));
                }
            }
        }

        JSONArray pictographicSelections = record.optJSONArray("pictographicSelections");
        if (pictographicSelections != null) {
            for (int i = 0; i < pictographicSelections.length(); i++) {
                JSONObject selection = pictographicSelections.optJSONObject(i);
                if (selection == null) {
                    continue;
                }
                String prefix = sanitizeHeader(selection.optString("promptId", "pictographic_" + (i + 1)));
                headers.add(prefix + "_prompt");
                headers.add(prefix + "_choice");
                headers.add(prefix + "_choice_numeric");
                headers.add(prefix + "_timestamp_utc");
                headers.add(prefix + "_timestamp_unix_ms");
            }
        }

        JSONArray questionnaireAnswers = record.optJSONArray("questionnaireAnswers");
        if (questionnaireAnswers != null) {
            for (int i = 0; i < questionnaireAnswers.length(); i++) {
                JSONObject answer = questionnaireAnswers.optJSONObject(i);
                if (answer == null) {
                    continue;
                }
                String prefix = String.format(Locale.US, "viscereality_q%03d", answer.optInt("order", i + 1));
                headers.add(prefix + "_label");
                headers.add(prefix + "_score_0_100");
                headers.add(prefix + "_timestamp_utc");
                headers.add(prefix + "_timestamp_unix_ms");
            }
        }
    }

    private static JSONObject flattenRecordForCombinedCsv(JSONObject record) throws JSONException {
        JSONObject values = new JSONObject();
        JSONObject participant = record.optJSONObject("participant");
        values.put("timestampUtc", record.optString("timestampUtc", ""));
        values.put("participantId", participant != null ? participant.optString("participantId", "") : "");
        values.put("name", participant != null ? participant.optString("name", "") : "");
        values.put("age", participant != null ? participant.optString("age", "") : "");
        values.put("gender", participant != null ? participant.optString("gender", "") : "");
        values.put("consent", participant != null ? participant.optString("consent", "") : "");
        values.put("language", participant != null ? participant.optString("language", "") : "");

        for (String key : new String[] {
            "appVersion", "unityVersion", "sourceRepository", "sourceCommit", "maia2SourcePath",
            "questionnaireConfigId", "questionnaireConfigVersion", "runId", "sessionId",
            "invocationId", "experimentId", "scenarioId", "trialId", "chainId", "chainStepId",
            "chainStepIndex", "finishBehavior", "callerPackage", "callerActivity", "nextPackage",
            "nextActivity", "questionnaireMode", "blockNumber", "blockId", "saveNamespace"
        }) {
            values.put(key, record.optString(key, ""));
        }

        JSONArray maiaAnswers = record.optJSONArray("maia2Answers");
        if (maiaAnswers != null) {
            for (int i = 0; i < maiaAnswers.length(); i++) {
                JSONObject answer = maiaAnswers.optJSONObject(i);
                if (answer == null) {
                    continue;
                }
                String prefix = String.format(Locale.US, "maia2_q%03d", answer.optInt("order", i + 1));
                values.put(prefix + "_label", answer.optString("itemText", ""));
                values.put(prefix + "_score_raw_0_5", answer.optString("score", ""));
                values.put(prefix + "_timestamp_utc", answer.optString("responseTimestampUtc", ""));
                values.put(prefix + "_timestamp_unix_ms", answer.optString("responseTimestampUnixMs", ""));
            }
        }

        JSONArray scores = record.optJSONArray("maia2Scores");
        if (scores != null) {
            for (int i = 0; i < scores.length(); i++) {
                JSONObject score = scores.optJSONObject(i);
                if (score != null) {
                    values.put("maia2_score_" + sanitizeHeader(score.optString("scaleName", "")), trimFloat((float) score.optDouble("score", 0)));
                }
            }
        }

        JSONArray pictographicSelections = record.optJSONArray("pictographicSelections");
        if (pictographicSelections != null) {
            for (int i = 0; i < pictographicSelections.length(); i++) {
                JSONObject selection = pictographicSelections.optJSONObject(i);
                if (selection == null) {
                    continue;
                }
                String prefix = sanitizeHeader(selection.optString("promptId", "pictographic_" + (i + 1)));
                String selectedChoice = selection.optString("selectedChoice", "");
                values.put(prefix + "_prompt", selection.optString("promptText", ""));
                values.put(prefix + "_choice", selectedChoice);
                values.put(prefix + "_choice_numeric", choiceToNumeric(selectedChoice));
                values.put(prefix + "_timestamp_utc", selection.optString("responseTimestampUtc", ""));
                values.put(prefix + "_timestamp_unix_ms", selection.optString("responseTimestampUnixMs", ""));
            }
        }

        JSONArray questionnaireAnswers = record.optJSONArray("questionnaireAnswers");
        if (questionnaireAnswers != null) {
            for (int i = 0; i < questionnaireAnswers.length(); i++) {
                JSONObject answer = questionnaireAnswers.optJSONObject(i);
                if (answer == null) {
                    continue;
                }
                String prefix = String.format(Locale.US, "viscereality_q%03d", answer.optInt("order", i + 1));
                values.put(prefix + "_label", answer.optString("itemText", ""));
                values.put(prefix + "_score_0_100", answer.optString("score", ""));
                values.put(prefix + "_timestamp_utc", answer.optString("responseTimestampUtc", ""));
                values.put(prefix + "_timestamp_unix_ms", answer.optString("responseTimestampUnixMs", ""));
            }
        }
        return values;
    }

    private static String sessionGroupKey(QuestionnaireData.SessionRecord record) {
        if (!isBlank(record.sessionId)) {
            return record.sessionId;
        }
        if (!isBlank(record.chainId)) {
            return record.chainId;
        }
        if (record.participant != null && !isBlank(record.participant.participantId)) {
            return record.participant.participantId;
        }
        return !isBlank(record.runId) ? record.runId : "standalone";
    }

    private static String sessionGroupKey(JSONObject index) {
        String sessionId = index.optString("sessionId", "");
        if (!isBlank(sessionId)) {
            return sessionId;
        }
        String chainId = index.optString("chainId", "");
        if (!isBlank(chainId)) {
            return chainId;
        }
        String participantId = index.optString("participantId", "");
        if (!isBlank(participantId)) {
            return participantId;
        }
        return index.optString("runId", "standalone");
    }

    private static void atomicWriteUtf8(File file, String value) throws IOException {
        File parent = file.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("Could not create folder: " + parent);
        }

        File temp = new File(parent, file.getName() + ".tmp");
        writeUtf8Synced(temp, value);
        if (file.exists() && !file.delete()) {
            throw new IOException("Could not replace existing file: " + file);
        }
        if (!temp.renameTo(file)) {
            throw new IOException("Could not move temp export into place: " + temp + " -> " + file);
        }
    }

    private static void writeUtf8Synced(File file, String value) throws IOException {
        try (FileOutputStream output = new FileOutputStream(file)) {
            output.write(value.getBytes(StandardCharsets.UTF_8));
            output.getFD().sync();
        }
    }

    private static String joinCsv(List<String> values) {
        StringBuilder builder = new StringBuilder();
        for (int i = 0; i < values.size(); i++) {
            if (i > 0) {
                builder.append(',');
            }
            builder.append(escapeCsv(values.get(i)));
        }

        return builder.toString();
    }

    private static String escapeCsv(String value) {
        if (value == null) {
            value = "";
        }

        boolean mustQuote = value.contains(",") || value.contains("\"") || value.contains("\r") || value.contains("\n");
        value = value.replace("\"", "\"\"");
        return mustQuote ? "\"" + value + "\"" : value;
    }

    private static String sanitizeHeader(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "unknown";
        }

        StringBuilder builder = new StringBuilder(value.length());
        String lower = value.toLowerCase(Locale.US);
        for (int i = 0; i < lower.length(); i++) {
            char c = lower.charAt(i);
            if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) {
                builder.append(c);
            } else {
                builder.append('_');
            }
        }

        String sanitized = builder.toString();
        while (sanitized.startsWith("_")) {
            sanitized = sanitized.substring(1);
        }
        while (sanitized.endsWith("_")) {
            sanitized = sanitized.substring(0, sanitized.length() - 1);
        }
        return sanitized.isEmpty() ? "unknown" : sanitized;
    }

    private static String sanitizeFileName(String value) {
        if (value == null || value.trim().isEmpty()) {
            return "Unknown";
        }

        return value.trim()
            .replaceAll("[\\\\/:*?\"<>|]", "_")
            .replace(' ', '_');
    }

    private static boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    private static String trimFloat(float value) {
        if (Math.abs(value - Math.round(value)) < 0.0001f) {
            return Integer.toString(Math.round(value));
        }

        return String.format(Locale.US, "%.3f", value).replaceAll("0+$", "").replaceAll("\\.$", "");
    }

    private static String choiceToNumeric(String value) {
        if (value == null) {
            return "";
        }
        String trimmed = value.trim();
        if (trimmed.matches("-?\\d+(\\.\\d+)?")) {
            return trimmed;
        }
        if (trimmed.length() == 1) {
            char c = Character.toUpperCase(trimmed.charAt(0));
            if (c >= 'A' && c <= 'Z') {
                return Integer.toString((c - 'A') + 1);
            }
        }
        return "";
    }

    static final class ExportResult {
        final File csvFile;
        final File jsonFile;
        final File combinedCsvFile;

        ExportResult(File csvFile, File jsonFile, File combinedCsvFile) {
            this.csvFile = csvFile;
            this.jsonFile = jsonFile;
            this.combinedCsvFile = combinedCsvFile;
        }
    }
}
