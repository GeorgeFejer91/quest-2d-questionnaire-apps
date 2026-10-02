package org.questquestionnaire.sam2d;

import android.content.Context;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

final class SamExporter {
    static final String EXPORT_DIR = "SamQuestionnaireExports";
    static final String SESSION_INDEX_NAME = "session-index.jsonl";

    private SamExporter() {
    }

    static ExportResult writeSession(Context context, SamResponseRecord record) throws Exception {
        File folder = exportFolder(context);
        if (!folder.exists() && !folder.mkdirs()) {
            throw new IOException("Could not create export folder: " + folder.getAbsolutePath());
        }

        String baseName = sanitize(record.runId) + "_sam_questionnaire";
        File jsonFile = new File(folder, baseName + ".json");
        File csvFile = new File(folder, baseName + ".csv");

        JSONObject json = toJson(context, record);
        atomicWriteUtf8(jsonFile, json.toString(2));
        atomicWriteUtf8(csvFile, toCsv(record));
        ExportResult result = new ExportResult(csvFile, jsonFile);
        appendSessionIndex(folder, record, result);
        return result;
    }

    static File exportFolder(Context context) {
        File root = context.getExternalFilesDir(null);
        if (root == null) {
            root = context.getFilesDir();
        }
        return new File(root, EXPORT_DIR);
    }

    static JSONObject toJson(Context context, SamResponseRecord record) throws Exception {
        SamAssetProvenance provenance = SamAssetProvenance.load(context);
        JSONObject root = new JSONObject();
        root.put("schema", "quest-questionnaire.sam2d.export.v2");
        root.put("appVersion", SamResponseRecord.APP_VERSION);
        root.put("runId", clean(record.runId));
        root.put("ratingTarget", SamResponseRecord.RATING_TARGET);
        root.put("timestampUtc", clean(record.timestampUtc));
        root.put("startedUnixMs", record.startedUnixMs);
        root.put("startedElapsedMs", record.startedElapsedMs);
        root.put("submittedUnixMs", record.submittedUnixMs);
        root.put("submittedElapsedMs", record.submittedElapsedMs);
        root.put("inputPath", clean(record.inputPath));

        root.put("participant", new JSONObject()
            .put("participantId", clean(record.participantId))
            .put("participantName", clean(record.participantName))
            .put("language", clean(record.language)));

        root.put("launch", new JSONObject()
            .put("sessionId", clean(record.sessionId))
            .put("invocationId", clean(record.invocationId))
            .put("experimentId", clean(record.experimentId))
            .put("scenarioId", clean(record.scenarioId))
            .put("trialId", clean(record.trialId))
            .put("triggerId", clean(record.triggerId))
            .put("blockId", clean(record.blockId))
            .put("blockNumber", clean(record.blockNumber))
            .put("finishBehavior", clean(record.finishBehavior))
            .put("callerPackage", clean(record.callerPackage))
            .put("callerActivity", clean(record.callerActivity))
            .put("nextPackage", clean(record.nextPackage))
            .put("nextActivity", clean(record.nextActivity)));

        root.put("sam", new JSONObject()
            .put("valenceRaw1To5", record.valenceScore)
            .put("valenceNormalized0To1", SamResponseRecord.normalized(record.valenceScore))
            .put("valenceLabel", clean(record.valenceLabel))
            .put("valenceResponseTimestampUtc", clean(record.valenceResponseTimestampUtc))
            .put("valenceResponseUnixMs", record.valenceResponseUnixMs)
            .put("valenceResponseElapsedMs", record.valenceResponseElapsedMs)
            .put("arousalRaw1To5", record.arousalScore)
            .put("arousalNormalized0To1", SamResponseRecord.normalized(record.arousalScore))
            .put("arousalLabel", clean(record.arousalLabel))
            .put("arousalResponseTimestampUtc", clean(record.arousalResponseTimestampUtc))
            .put("arousalResponseUnixMs", record.arousalResponseUnixMs)
            .put("arousalResponseElapsedMs", record.arousalResponseElapsedMs));

        root.put("affectiveSlider", new JSONObject()
            .put("valenceRaw0To100", record.sliderValence)
            .put("valenceNormalized0To1", record.sliderValence / 100.0)
            .put("valenceResponseTimestampUtc", clean(record.sliderValenceResponseTimestampUtc))
            .put("valenceResponseUnixMs", record.sliderValenceResponseUnixMs)
            .put("valenceResponseElapsedMs", record.sliderValenceResponseElapsedMs)
            .put("arousalRaw0To100", record.sliderArousal)
            .put("arousalNormalized0To1", record.sliderArousal / 100.0)
            .put("arousalResponseTimestampUtc", clean(record.sliderArousalResponseTimestampUtc))
            .put("arousalResponseUnixMs", record.sliderArousalResponseUnixMs)
            .put("arousalResponseElapsedMs", record.sliderArousalResponseElapsedMs)
            .put("studyReference", "Betella and Verschure 2016, PLOS ONE 11(2):e0148037"));

        root.put("assetProvenance", new JSONObject()
            .put("sourceRepository", clean(provenance.sourceRepository))
            .put("sourceLicense", clean(provenance.sourceLicense))
            .put("sourceReference", clean(provenance.sourceReference))
            .put("valenceGridSha256", clean(provenance.valenceGridSha256))
            .put("arousalGridSha256", clean(provenance.arousalGridSha256)));
        return root;
    }

    static String toCsv(SamResponseRecord record) {
        List<String> headers = new ArrayList<>();
        List<String> values = new ArrayList<>();
        add(headers, values, "timestampUtc", record.timestampUtc);
        add(headers, values, "runId", record.runId);
        add(headers, values, "sessionId", record.sessionId);
        add(headers, values, "invocationId", record.invocationId);
        add(headers, values, "participantId", record.participantId);
        add(headers, values, "participantName", record.participantName);
        add(headers, values, "language", record.language);
        add(headers, values, "appVersion", SamResponseRecord.APP_VERSION);
        add(headers, values, "ratingTarget", SamResponseRecord.RATING_TARGET);
        add(headers, values, "experimentId", record.experimentId);
        add(headers, values, "scenarioId", record.scenarioId);
        add(headers, values, "trialId", record.trialId);
        add(headers, values, "triggerId", record.triggerId);
        add(headers, values, "blockId", record.blockId);
        add(headers, values, "blockNumber", record.blockNumber);
        add(headers, values, "finishBehavior", record.finishBehavior);
        add(headers, values, "inputPath", record.inputPath);
        add(headers, values, "startedUnixMs", Long.toString(record.startedUnixMs));
        add(headers, values, "startedElapsedMs", Long.toString(record.startedElapsedMs));
        add(headers, values, "submittedUnixMs", Long.toString(record.submittedUnixMs));
        add(headers, values, "submittedElapsedMs", Long.toString(record.submittedElapsedMs));
        add(headers, values, "sam_valence_raw_1_5", Integer.toString(record.valenceScore));
        add(headers, values, "sam_valence_normalized_0_1", trimDouble(SamResponseRecord.normalized(record.valenceScore)));
        add(headers, values, "sam_valence_label", record.valenceLabel);
        add(headers, values, "sam_valence_timestamp_utc", record.valenceResponseTimestampUtc);
        add(headers, values, "sam_valence_timestamp_unix_ms", Long.toString(record.valenceResponseUnixMs));
        add(headers, values, "sam_valence_elapsed_ms", Long.toString(record.valenceResponseElapsedMs));
        add(headers, values, "sam_arousal_raw_1_5", Integer.toString(record.arousalScore));
        add(headers, values, "sam_arousal_normalized_0_1", trimDouble(SamResponseRecord.normalized(record.arousalScore)));
        add(headers, values, "sam_arousal_label", record.arousalLabel);
        add(headers, values, "sam_arousal_timestamp_utc", record.arousalResponseTimestampUtc);
        add(headers, values, "sam_arousal_timestamp_unix_ms", Long.toString(record.arousalResponseUnixMs));
        add(headers, values, "sam_arousal_elapsed_ms", Long.toString(record.arousalResponseElapsedMs));
        add(headers, values, "as_valence_raw_0_100", Integer.toString(record.sliderValence));
        add(headers, values, "as_valence_normalized_0_1", trimDouble(record.sliderValence / 100.0));
        add(headers, values, "as_valence_timestamp_utc", record.sliderValenceResponseTimestampUtc);
        add(headers, values, "as_valence_timestamp_unix_ms", Long.toString(record.sliderValenceResponseUnixMs));
        add(headers, values, "as_valence_elapsed_ms", Long.toString(record.sliderValenceResponseElapsedMs));
        add(headers, values, "as_arousal_raw_0_100", Integer.toString(record.sliderArousal));
        add(headers, values, "as_arousal_normalized_0_1", trimDouble(record.sliderArousal / 100.0));
        add(headers, values, "as_arousal_timestamp_utc", record.sliderArousalResponseTimestampUtc);
        add(headers, values, "as_arousal_timestamp_unix_ms", Long.toString(record.sliderArousalResponseUnixMs));
        add(headers, values, "as_arousal_elapsed_ms", Long.toString(record.sliderArousalResponseElapsedMs));
        return joinCsv(headers) + System.lineSeparator() + joinCsv(values) + System.lineSeparator();
    }

    private static void appendSessionIndex(File folder, SamResponseRecord record, ExportResult result) throws Exception {
        JSONObject index = new JSONObject()
            .put("schema", "quest-questionnaire.sam2d.session-index.v2")
            .put("runId", record.runId)
            .put("sessionId", record.sessionId)
            .put("participantId", record.participantId)
            .put("ratingTarget", SamResponseRecord.RATING_TARGET)
            .put("timestampUtc", record.timestampUtc)
            .put("valenceRaw1To5", record.valenceScore)
            .put("arousalRaw1To5", record.arousalScore)
            .put("sliderValenceRaw0To100", record.sliderValence)
            .put("sliderArousalRaw0To100", record.sliderArousal)
            .put("jsonPath", result.jsonFile.getAbsolutePath())
            .put("csvPath", result.csvFile.getAbsolutePath());
        File indexFile = new File(folder, SESSION_INDEX_NAME);
        appendUtf8(indexFile, index.toString() + System.lineSeparator());
    }

    private static void add(List<String> headers, List<String> values, String header, String value) {
        headers.add(header);
        values.add(value == null ? "" : value);
    }

    private static void atomicWriteUtf8(File file, String text) throws IOException {
        File temp = new File(file.getParentFile(), file.getName() + ".tmp");
        try (FileOutputStream stream = new FileOutputStream(temp, false)) {
            stream.write(text.getBytes(StandardCharsets.UTF_8));
        }
        if (file.exists() && !file.delete()) {
            throw new IOException("Could not replace " + file.getAbsolutePath());
        }
        if (!temp.renameTo(file)) {
            throw new IOException("Could not move " + temp.getAbsolutePath() + " to " + file.getAbsolutePath());
        }
    }

    private static void appendUtf8(File file, String text) throws IOException {
        try (FileOutputStream stream = new FileOutputStream(file, true)) {
            stream.write(text.getBytes(StandardCharsets.UTF_8));
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
        String clean = value == null ? "" : value;
        if (clean.contains("\"") || clean.contains(",") || clean.contains("\n") || clean.contains("\r")) {
            return "\"" + clean.replace("\"", "\"\"") + "\"";
        }
        return clean;
    }

    private static String sanitize(String value) {
        String clean = clean(value);
        return clean.isEmpty() ? "sam" : clean.replaceAll("[^A-Za-z0-9._-]+", "_");
    }

    private static String clean(String value) {
        return value == null ? "" : value;
    }

    private static String trimDouble(double value) {
        return String.format(Locale.US, "%.6f", value).replaceAll("0+$", "").replaceAll("\\.$", "");
    }

    static final class ExportResult {
        final File csvFile;
        final File jsonFile;

        ExportResult(File csvFile, File jsonFile) {
            this.csvFile = csvFile;
            this.jsonFile = jsonFile;
        }
    }
}
