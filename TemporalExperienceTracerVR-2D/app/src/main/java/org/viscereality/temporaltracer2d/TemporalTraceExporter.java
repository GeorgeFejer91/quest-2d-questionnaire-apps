package org.viscereality.temporaltracer2d;

import android.content.Context;
import android.text.TextUtils;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Locale;

final class TemporalTraceExporter {
    static final String EXPORT_FOLDER = "TemporalTraceExports";
    static final String SESSION_INDEX_NAME = "session-index.jsonl";

    private static final String TAG = "TemporalTraceExporter";

    private final Context context;

    TemporalTraceExporter(Context context) {
        this.context = context.getApplicationContext();
    }

    File exportDir() {
        File root = context.getExternalFilesDir(null);
        File dir = new File(root == null ? context.getFilesDir() : root, EXPORT_FOLDER);
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IllegalStateException("Could not create export directory: " + dir);
        }
        return dir;
    }

    File inProgressDir() {
        File dir = new File(exportDir(), "in_progress");
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IllegalStateException("Could not create draft directory: " + dir);
        }
        return dir;
    }

    void writeDraft(
        TemporalTracerLaunchContext launch,
        TemporalTracerConfig config,
        String language,
        String participantId,
        String participantName,
        int nextTraceIndex,
        int completedTraceCount) {
        try {
            JSONObject draft = new JSONObject()
                .put("schema", "temporal-experience-tracer.draft.v1")
                .put("runId", launch.runId)
                .put("updatedAtUtc", TimeUtil.utcIsoNowMillis())
                .put("status", "in_progress")
                .put("participant", new JSONObject()
                    .put("id", clean(participantId))
                    .put("name", clean(participantName))
                    .put("language", clean(language)))
                .put("config", config.toSummaryJson(language))
                .put("nextTraceIndex", nextTraceIndex)
                .put("completedTraceCount", completedTraceCount)
                .put("sessionId", launch.sessionId)
                .put("experimentId", launch.experimentId)
                .put("scenarioId", launch.scenarioId)
                .put("trialId", launch.trialId)
                .put("chainId", launch.chainId)
                .put("chainStepId", launch.chainStepId)
                .put("chainStepIndex", launch.chainStepIndex);
            writeAtomic(new File(inProgressDir(), launch.runId + ".draft.json"), draft.toString(2));
        } catch (Exception ex) {
            Log.w(TAG, "Could not write draft", ex);
        }
    }

    void markDraftComplete(TemporalTracerLaunchContext launch) {
        try {
            File draft = new File(inProgressDir(), launch.runId + ".draft.json");
            if (!draft.exists()) {
                return;
            }
            JSONObject complete = new JSONObject()
                .put("schema", "temporal-experience-tracer.draft.v1")
                .put("runId", launch.runId)
                .put("updatedAtUtc", TimeUtil.utcIsoNowMillis())
                .put("status", "complete");
            writeAtomic(draft, complete.toString(2));
        } catch (Exception ex) {
            Log.w(TAG, "Could not mark draft complete", ex);
        }
    }

    ExportResult exportTrace(
        TemporalTracerLaunchContext launch,
        TemporalTracerConfig config,
        String language,
        String participantId,
        String participantName,
        int traceIndex,
        TemporalTracerConfig.TraceItem item,
        List<TracePoint> rawPoints,
        List<TracePoint> resampledPoints) throws Exception {
        if (resampledPoints == null || resampledPoints.size() < 2) {
            throw new IllegalArgumentException("Cannot export incomplete trace.");
        }

        File dir = exportDir();
        String baseName = launch.runId + "_" + String.format(Locale.US, "%02d", traceIndex + 1) + "_" +
            safeFileComponent(participantName) + "_" + safeFileComponent(item.label);
        File svgFile = new File(dir, baseName + ".svg");
        File csvFile = new File(dir, baseName + ".csv");
        File jsonFile = new File(dir, baseName + ".json");

        String exportedAt = TimeUtil.utcIsoNowMillis();
        JSONObject json = buildJson(launch, config, language, participantId, participantName, traceIndex, item, rawPoints, resampledPoints, exportedAt);
        writeAtomic(svgFile, buildSvg(launch, config, language, traceIndex, item, rawPoints, resampledPoints, json));
        writeAtomic(csvFile, buildCsv(launch, config, language, participantId, participantName, traceIndex, item, resampledPoints, exportedAt));
        json.put("exports", new JSONObject()
            .put("svgPath", svgFile.getAbsolutePath())
            .put("csvPath", csvFile.getAbsolutePath())
            .put("jsonPath", jsonFile.getAbsolutePath()));
        writeAtomic(jsonFile, json.toString(2));

        appendIndex(launch, config, language, participantId, participantName, traceIndex, item, svgFile, csvFile, jsonFile, exportedAt, resampledPoints.size());
        appendCombinedCsv(launch, config, language, participantId, participantName, traceIndex, item, svgFile, csvFile, jsonFile, exportedAt, resampledPoints.size());

        Log.i(TAG, "TEMPORAL_TRACER_EXPORT_COMPLETE runId=" + launch.runId + " traceIndex=" + traceIndex + " svg=" + svgFile.getAbsolutePath());
        return new ExportResult(svgFile, csvFile, jsonFile);
    }

    private JSONObject buildJson(
        TemporalTracerLaunchContext launch,
        TemporalTracerConfig config,
        String language,
        String participantId,
        String participantName,
        int traceIndex,
        TemporalTracerConfig.TraceItem item,
        List<TracePoint> rawPoints,
        List<TracePoint> resampledPoints,
        String exportedAt) throws Exception {
        JSONObject json = new JSONObject()
            .put("schema", "temporal-experience-tracer.export.v1")
            .put("runId", launch.runId)
            .put("invocationId", launch.invocationId)
            .put("sessionId", launch.sessionId)
            .put("experimentId", launch.experimentId)
            .put("scenarioId", launch.scenarioId)
            .put("trialId", launch.trialId)
            .put("chainId", launch.chainId)
            .put("chainStepId", launch.chainStepId)
            .put("chainStepIndex", launch.chainStepIndex)
            .put("blockId", launch.blockId)
            .put("blockNumber", launch.blockNumber)
            .put("finishBehavior", launch.finishBehavior)
            .put("callerPackage", launch.callerPackage)
            .put("nextPackage", launch.nextPackage)
            .put("timestampUtc", exportedAt)
            .put("participant", new JSONObject()
                .put("id", clean(participantId))
                .put("name", clean(participantName))
                .put("language", clean(language)))
            .put("config", config.toSummaryJson(language))
            .put("trace", new JSONObject()
                .put("index", traceIndex)
                .put("label", item.label)
                .put("message", item.message)
                .put("audioFile", resolvedAudioFile(config, language, traceIndex, item))
                .put("rawPointCount", rawPoints == null ? 0 : rawPoints.size())
                .put("resampledPointCount", resampledPoints.size())
                .put("startedAtUtc", firstTimestamp(rawPoints))
                .put("completedAtUtc", lastTimestamp(rawPoints)));

        json.put("points", pointsJson(config.axis, resampledPoints));
        json.put("rawPoints", pointsJson(config.axis, rawPoints));
        return json;
    }

    private String resolvedAudioFile(
        TemporalTracerConfig config,
        String language,
        int traceIndex,
        TemporalTracerConfig.TraceItem item) {
        String normalizedLanguage = config.normalizeLanguage(language);
        String primary = item.resolvedAudioFile(normalizedLanguage, traceIndex);
        if (assetExists(primary)) {
            return primary;
        }
        if (!"English".equals(normalizedLanguage)) {
            List<TemporalTracerConfig.TraceItem> englishItems = config.items("English");
            if (traceIndex >= 0 && traceIndex < englishItems.size()) {
                String fallback = englishItems.get(traceIndex).resolvedAudioFile("English", traceIndex);
                if (assetExists(fallback)) {
                    return fallback;
                }
            }
        }
        return primary;
    }

    private boolean assetExists(String assetPath) {
        try (InputStream ignored = context.getAssets().open(assetPath)) {
            return true;
        } catch (Exception ex) {
            return false;
        }
    }

    private JSONArray pointsJson(TemporalTracerConfig.AxisConfig axis, List<TracePoint> points) throws Exception {
        JSONArray array = new JSONArray();
        if (points == null) {
            return array;
        }
        for (int i = 0; i < points.size(); i++) {
            TracePoint point = points.get(i);
            array.put(new JSONObject()
                .put("pointIndex", i)
                .put("timestampMillis", point.timestampMillis)
                .put("timestampUtc", point.timestampUtc)
                .put("u_0to1", point.u)
                .put("v_0to1", point.v)
                .put("x_axis", axis.durationAt(point.u))
                .put("x_axisUnit", axis.durationUnit)
                .put("y_axis", axis.valueAt(point.v)));
        }
        return array;
    }

    private String buildCsv(
        TemporalTracerLaunchContext launch,
        TemporalTracerConfig config,
        String language,
        String participantId,
        String participantName,
        int traceIndex,
        TemporalTracerConfig.TraceItem item,
        List<TracePoint> points,
        String exportedAt) {
        StringBuilder csv = new StringBuilder();
        csv.append("runId,sessionId,participantId,participantName,language,experimentId,scenarioId,trialId,chainId,chainStepId,blockId,blockNumber,traceIndex,traceLabel,pointIndex,timestampUtc,timestampMillis,u_0to1,v_0to1,x_axis,x_axisUnit,y_axis,exportedAtUtc\n");
        for (int i = 0; i < points.size(); i++) {
            TracePoint point = points.get(i);
            csv.append(esc(launch.runId)).append(',')
                .append(esc(launch.sessionId)).append(',')
                .append(esc(participantId)).append(',')
                .append(esc(participantName)).append(',')
                .append(esc(language)).append(',')
                .append(esc(launch.experimentId)).append(',')
                .append(esc(launch.scenarioId)).append(',')
                .append(esc(launch.trialId)).append(',')
                .append(esc(launch.chainId)).append(',')
                .append(esc(launch.chainStepId)).append(',')
                .append(esc(launch.blockId)).append(',')
                .append(esc(launch.blockNumber)).append(',')
                .append(traceIndex).append(',')
                .append(esc(item.label)).append(',')
                .append(i).append(',')
                .append(esc(point.timestampUtc)).append(',')
                .append(point.timestampMillis).append(',')
                .append(fmt(point.u)).append(',')
                .append(fmt(point.v)).append(',')
                .append(fmt(config.axis.durationAt(point.u))).append(',')
                .append(esc(config.axis.durationUnit)).append(',')
                .append(fmt(config.axis.valueAt(point.v))).append(',')
                .append(esc(exportedAt)).append('\n');
        }
        return csv.toString();
    }

    private String buildSvg(
        TemporalTracerLaunchContext launch,
        TemporalTracerConfig config,
        String language,
        int traceIndex,
        TemporalTracerConfig.TraceItem item,
        List<TracePoint> rawPoints,
        List<TracePoint> points,
        JSONObject metadata) {
        TemporalTracerConfig.AxisConfig axis = config.axis;
        List<TracePoint> visualPoints = rawPoints != null && rawPoints.size() >= 2 ? rawPoints : points;
        String rawPointString = pointString(axis, visualPoints);
        String normalizedPointString = pointString(axis, points);
        String smoothPath = smoothPath(axis, visualPoints);

        StringBuilder svg = new StringBuilder();
        svg.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        svg.append("<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" viewBox=\"0 0 ")
            .append(axis.viewBoxWidth).append(' ').append(axis.viewBoxHeight)
            .append("\" width=\"").append(axis.viewBoxWidth)
            .append("\" height=\"").append(axis.viewBoxHeight)
            .append("\" preserveAspectRatio=\"none\">\n");
        svg.append("  <title>").append(xml(config.tracerId)).append(" / ").append(xml(item.label)).append("</title>\n");
        svg.append("  <desc>runId=").append(xml(launch.runId)).append(" traceIndex=").append(traceIndex).append("</desc>\n");
        svg.append("  <metadata><![CDATA[").append(metadata.toString().replace("]]>", "]]]]><![CDATA[>")).append("]]></metadata>\n");
        svg.append("  <rect x=\"0\" y=\"0\" width=\"").append(axis.viewBoxWidth).append("\" height=\"").append(axis.viewBoxHeight).append("\" fill=\"none\"/>\n");
        for (int i = 0; i < axis.horizontalGridLabels.size(); i++) {
            double y = axis.horizontalGridLabels.size() <= 1 ? 0.0 : (axis.viewBoxHeight * i) / (double) (axis.horizontalGridLabels.size() - 1);
            svg.append("  <line x1=\"0\" y1=\"").append(fmt(y)).append("\" x2=\"").append(axis.viewBoxWidth).append("\" y2=\"").append(fmt(y)).append("\" stroke=\"")
                .append(xml(colorHex(axis.gridColor))).append("\" stroke-width=\"0.4\" opacity=\"0.45\"/>\n");
            if (i == 0 || i == axis.horizontalGridLabels.size() - 1 || i == axis.horizontalGridLabels.size() / 2) {
                double textY = Math.max(4.0, Math.min(axis.viewBoxHeight - 2.0, y + 3.0));
                svg.append("  <text x=\"2\" y=\"").append(fmt(textY)).append("\" font-family=\"Arial\" font-size=\"3.5\" fill=\"")
                    .append(xml(colorHex(axis.axisColor))).append("\">").append(xml(axis.horizontalGridLabels.get(i))).append("</text>\n");
            }
        }
        for (int i = 0; i < axis.verticalGridLabels.size(); i++) {
            double x = axis.verticalGridLabels.size() <= 1 ? 0.0 : (axis.viewBoxWidth * i) / (double) (axis.verticalGridLabels.size() - 1);
            svg.append("  <line x1=\"").append(fmt(x)).append("\" y1=\"0\" x2=\"").append(fmt(x)).append("\" y2=\"").append(axis.viewBoxHeight).append("\" stroke=\"")
                .append(xml(colorHex(axis.gridColor))).append("\" stroke-width=\"0.4\" opacity=\"0.45\"/>\n");
            if (i == 0 || i == axis.verticalGridLabels.size() - 1 || i == axis.verticalGridLabels.size() / 2) {
                svg.append("  <text x=\"").append(fmt(Math.max(2.0, Math.min(axis.viewBoxWidth - 26.0, x + 1.0))))
                    .append("\" y=\"").append(fmt(axis.viewBoxHeight - 2.0))
                    .append("\" font-family=\"Arial\" font-size=\"3.5\" fill=\"")
                    .append(xml(colorHex(axis.axisColor))).append("\">").append(xml(axis.verticalGridLabels.get(i))).append("</text>\n");
            }
        }
        svg.append("  <text x=\"2\" y=\"4\" font-family=\"Arial\" font-size=\"3.5\" fill=\"")
            .append(xml(colorHex(axis.axisColor))).append("\">").append(xml(axis.topLabel(language))).append("</text>\n");
        svg.append("  <text x=\"2\" y=\"").append(fmt(axis.viewBoxHeight - 6.0)).append("\" font-family=\"Arial\" font-size=\"3.5\" fill=\"")
            .append(xml(colorHex(axis.axisColor))).append("\">").append(xml(axis.bottomLabel(language))).append("</text>\n");
        svg.append("  <rect x=\"0\" y=\"0\" width=\"").append(axis.viewBoxWidth).append("\" height=\"").append(axis.viewBoxHeight).append("\" fill=\"none\" stroke=\"")
            .append(xml(colorHex(axis.axisColor))).append("\" stroke-width=\"0.8\"/>\n");
        svg.append("  <path id=\"trace-smooth-vector\" d=\"").append(smoothPath).append("\" fill=\"none\" stroke=\"")
            .append(xml(colorHex(axis.traceColor))).append("\" stroke-width=\"")
            .append(fmt(axis.strokeWidth)).append("\" stroke-linecap=\"round\" stroke-linejoin=\"round\" vector-effect=\"non-scaling-stroke\"/>\n");
        svg.append("  <polyline id=\"trace-raw-captured-points\" points=\"").append(rawPointString)
            .append("\" fill=\"none\" stroke=\"none\" data-role=\"raw-captured-vector\"/>\n");
        svg.append("  <polyline id=\"trace-normalized-analysis-points\" points=\"").append(normalizedPointString)
            .append("\" fill=\"none\" stroke=\"none\" data-role=\"normalized-1000-analysis-vector\"/>\n");
        svg.append("</svg>\n");
        return svg.toString();
    }

    private String pointString(TemporalTracerConfig.AxisConfig axis, List<TracePoint> points) {
        StringBuilder value = new StringBuilder();
        if (points == null) {
            return "";
        }
        for (TracePoint point : points) {
            if (point == null) {
                continue;
            }
            double x = TemporalTracerConfig.clamp(point.u, 0.0, 1.0) * axis.viewBoxWidth;
            double y = (1.0 - TemporalTracerConfig.clamp(point.v, 0.0, 1.0)) * axis.viewBoxHeight;
            if (value.length() > 0) {
                value.append(' ');
            }
            value.append(fmt(x)).append(',').append(fmt(y));
        }
        return value.toString();
    }

    private String smoothPath(TemporalTracerConfig.AxisConfig axis, List<TracePoint> points) {
        if (points == null || points.isEmpty()) {
            return "";
        }
        TracePoint first = points.get(0);
        StringBuilder path = new StringBuilder()
            .append("M ").append(fmt(TemporalTracerConfig.clamp(first.u, 0.0, 1.0) * axis.viewBoxWidth))
            .append(' ').append(fmt((1.0 - TemporalTracerConfig.clamp(first.v, 0.0, 1.0)) * axis.viewBoxHeight));
        for (int i = 1; i < points.size(); i++) {
            TracePoint a = points.get(i - 1);
            TracePoint b = points.get(i);
            double ax = TemporalTracerConfig.clamp(a.u, 0.0, 1.0) * axis.viewBoxWidth;
            double ay = (1.0 - TemporalTracerConfig.clamp(a.v, 0.0, 1.0)) * axis.viewBoxHeight;
            double bx = TemporalTracerConfig.clamp(b.u, 0.0, 1.0) * axis.viewBoxWidth;
            double by = (1.0 - TemporalTracerConfig.clamp(b.v, 0.0, 1.0)) * axis.viewBoxHeight;
            path.append(" Q ").append(fmt(ax)).append(' ').append(fmt(ay)).append(' ')
                .append(fmt((ax + bx) * 0.5)).append(' ').append(fmt((ay + by) * 0.5));
        }
        TracePoint last = points.get(points.size() - 1);
        path.append(" L ").append(fmt(TemporalTracerConfig.clamp(last.u, 0.0, 1.0) * axis.viewBoxWidth))
            .append(' ').append(fmt((1.0 - TemporalTracerConfig.clamp(last.v, 0.0, 1.0)) * axis.viewBoxHeight));
        return path.toString();
    }

    private void appendIndex(
        TemporalTracerLaunchContext launch,
        TemporalTracerConfig config,
        String language,
        String participantId,
        String participantName,
        int traceIndex,
        TemporalTracerConfig.TraceItem item,
        File svgFile,
        File csvFile,
        File jsonFile,
        String exportedAt,
        int pointCount) throws Exception {
        JSONObject index = new JSONObject()
            .put("schema", "temporal-experience-tracer.session-index.v1")
            .put("runId", launch.runId)
            .put("sessionId", launch.sessionId)
            .put("participantId", clean(participantId))
            .put("participantName", clean(participantName))
            .put("language", clean(language))
            .put("tracerId", config.tracerId)
            .put("traceIndex", traceIndex)
            .put("traceLabel", item.label)
            .put("pointCount", pointCount)
            .put("timestampUtc", exportedAt)
            .put("svgPath", svgFile.getAbsolutePath())
            .put("csvPath", csvFile.getAbsolutePath())
            .put("jsonPath", jsonFile.getAbsolutePath());
        appendSynced(new File(exportDir(), SESSION_INDEX_NAME), index.toString() + "\n");
    }

    private void appendCombinedCsv(
        TemporalTracerLaunchContext launch,
        TemporalTracerConfig config,
        String language,
        String participantId,
        String participantName,
        int traceIndex,
        TemporalTracerConfig.TraceItem item,
        File svgFile,
        File csvFile,
        File jsonFile,
        String exportedAt,
        int pointCount) throws Exception {
        File combined = new File(exportDir(), launch.runId + "_session-summary.csv");
        boolean header = !combined.exists() || combined.length() == 0L;
        StringBuilder row = new StringBuilder();
        if (header) {
            row.append("runId,sessionId,participantId,participantName,language,tracerId,experimentId,scenarioId,trialId,chainId,chainStepId,blockId,blockNumber,traceIndex,traceLabel,pointCount,timestampUtc,svgPath,csvPath,jsonPath\n");
        }
        row.append(esc(launch.runId)).append(',')
            .append(esc(launch.sessionId)).append(',')
            .append(esc(participantId)).append(',')
            .append(esc(participantName)).append(',')
            .append(esc(language)).append(',')
            .append(esc(config.tracerId)).append(',')
            .append(esc(launch.experimentId)).append(',')
            .append(esc(launch.scenarioId)).append(',')
            .append(esc(launch.trialId)).append(',')
            .append(esc(launch.chainId)).append(',')
            .append(esc(launch.chainStepId)).append(',')
            .append(esc(launch.blockId)).append(',')
            .append(esc(launch.blockNumber)).append(',')
            .append(traceIndex).append(',')
            .append(esc(item.label)).append(',')
            .append(pointCount).append(',')
            .append(esc(exportedAt)).append(',')
            .append(esc(svgFile.getAbsolutePath())).append(',')
            .append(esc(csvFile.getAbsolutePath())).append(',')
            .append(esc(jsonFile.getAbsolutePath())).append('\n');
        appendSynced(combined, row.toString());
    }

    private static void writeAtomic(File target, String content) throws Exception {
        File parent = target.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IllegalStateException("Could not create directory: " + parent);
        }
        File temp = new File(parent, target.getName() + ".tmp");
        try (FileOutputStream stream = new FileOutputStream(temp, false)) {
            stream.write(content.getBytes(StandardCharsets.UTF_8));
            stream.getFD().sync();
        }
        if (target.exists() && !target.delete()) {
            throw new IllegalStateException("Could not replace file: " + target);
        }
        if (!temp.renameTo(target)) {
            throw new IllegalStateException("Could not rename temp file into place: " + target);
        }
    }

    private static void appendSynced(File target, String content) throws Exception {
        File parent = target.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IllegalStateException("Could not create directory: " + parent);
        }
        try (FileOutputStream stream = new FileOutputStream(target, true)) {
            stream.write(content.getBytes(StandardCharsets.UTF_8));
            stream.getFD().sync();
        }
    }

    private static String firstTimestamp(List<TracePoint> points) {
        if (points == null || points.isEmpty()) {
            return "";
        }
        return points.get(0).timestampUtc;
    }

    private static String lastTimestamp(List<TracePoint> points) {
        if (points == null || points.isEmpty()) {
            return "";
        }
        return points.get(points.size() - 1).timestampUtc;
    }

    private static String safeFileComponent(String value) {
        String clean = clean(value);
        if (TextUtils.isEmpty(clean)) {
            return "unnamed";
        }
        return clean.replaceAll("[^A-Za-z0-9._-]+", "_");
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private static String fmt(double value) {
        return String.format(Locale.US, "%.6f", value);
    }

    private static String esc(String value) {
        String clean = clean(value);
        if (clean.contains(",") || clean.contains("\"") || clean.contains("\n") || clean.contains("\r")) {
            return "\"" + clean.replace("\"", "\"\"") + "\"";
        }
        return clean;
    }

    private static String xml(String value) {
        return clean(value)
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace("\"", "&quot;");
    }

    private static String colorHex(int color) {
        return String.format(Locale.US, "#%02X%02X%02X", (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF);
    }

    static final class ExportResult {
        final File svgFile;
        final File csvFile;
        final File jsonFile;

        ExportResult(File svgFile, File csvFile, File jsonFile) {
            this.svgFile = svgFile;
            this.csvFile = csvFile;
            this.jsonFile = jsonFile;
        }
    }
}
