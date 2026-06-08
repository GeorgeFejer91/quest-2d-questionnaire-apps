package org.questquestionnaire.questionnaires2d;

import android.content.Context;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Locale;

final class TemporalTraceExporter {
    private TemporalTraceExporter() {
    }

    static QuestionnaireData.TemporalTraceExport exportTrace(
        Context context,
        QuestionnaireLaunchContext launchContext,
        QuestionnaireData.RuntimeConfig config,
        QuestionnaireData.ParticipantInfo participant,
        int traceIndex,
        QuestionnaireData.RuntimeTemporalDimension dimension,
        List<TracePoint> rawPoints,
        List<TracePoint> resampledPoints) throws Exception {

        if (resampledPoints == null || resampledPoints.size() < 2) {
            throw new IllegalArgumentException("Cannot export incomplete temporal trace.");
        }

        File dir = new File(QuestionnaireExporter.exportFolder(context), "TemporalTraces");
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IllegalStateException("Could not create temporal trace export folder: " + dir);
        }

        String runId = clean(launchContext != null ? launchContext.runId : TimeUtil.newRunId());
        String participantName = participant != null ? participant.name : "anonymous";
        String baseName = safeFileComponent(runId + "_" + String.format(Locale.US, "%02d", traceIndex + 1) + "_" + participantName + "_" + dimension.dimensionLabel);
        File svgFile = new File(dir, baseName + ".svg");
        File csvFile = new File(dir, baseName + ".csv");
        File jsonFile = new File(dir, baseName + ".json");
        String exportedAt = TimeUtil.utcIsoNowMillis();

        JSONObject json = buildJson(launchContext, config, participant, traceIndex, dimension, rawPoints, resampledPoints, exportedAt);
        writeAtomic(svgFile, buildSvg(launchContext, config, traceIndex, dimension, rawPoints, resampledPoints, json));
        writeAtomic(csvFile, buildCsv(launchContext, config, participant, traceIndex, dimension, resampledPoints, exportedAt));
        json.put("exports", new JSONObject()
            .put("svgPath", svgFile.getAbsolutePath())
            .put("csvPath", csvFile.getAbsolutePath())
            .put("jsonPath", jsonFile.getAbsolutePath()));
        writeAtomic(jsonFile, json.toString(2));

        QuestionnaireData.TemporalTraceExport export = new QuestionnaireData.TemporalTraceExport();
        export.order = traceIndex + 1;
        export.dimensionId = clean(dimension.id);
        export.dimensionLabel = clean(dimension.dimensionLabel);
        export.dimensionDescription = clean(dimension.dimensionDescription);
        export.audioFile = clean(dimension.audioFile);
        export.rawPointCount = rawPoints == null ? 0 : rawPoints.size();
        export.resampledPointCount = resampledPoints.size();
        export.svgPath = svgFile.getAbsolutePath();
        export.csvPath = csvFile.getAbsolutePath();
        export.jsonPath = jsonFile.getAbsolutePath();
        export.responseTimestampUtc = exportedAt;
        export.responseTimestampUnixMs = TimeUtil.unixMillisNow();
        return export;
    }

    private static JSONObject buildJson(
        QuestionnaireLaunchContext launchContext,
        QuestionnaireData.RuntimeConfig config,
        QuestionnaireData.ParticipantInfo participant,
        int traceIndex,
        QuestionnaireData.RuntimeTemporalDimension dimension,
        List<TracePoint> rawPoints,
        List<TracePoint> resampledPoints,
        String exportedAt) throws Exception {

        JSONObject json = new JSONObject()
            .put("schema", "quest-questionnaire.temporal-trace.export.v1")
            .put("runId", clean(launchContext != null ? launchContext.runId : ""))
            .put("invocationId", clean(launchContext != null ? launchContext.invocationId : ""))
            .put("sessionId", clean(launchContext != null ? launchContext.sessionId : ""))
            .put("experimentId", clean(launchContext != null ? launchContext.experimentId : ""))
            .put("scenarioId", clean(launchContext != null ? launchContext.scenarioId : ""))
            .put("trialId", clean(launchContext != null ? launchContext.trialId : ""))
            .put("chainId", clean(launchContext != null ? launchContext.chainId : ""))
            .put("chainStepId", clean(launchContext != null ? launchContext.chainStepId : ""))
            .put("chainStepIndex", launchContext != null ? launchContext.chainStepIndex : -1)
            .put("triggerId", clean(launchContext != null ? launchContext.triggerId : ""))
            .put("blockId", clean(launchContext != null ? launchContext.blockId : ""))
            .put("blockNumber", clean(launchContext != null ? launchContext.blockNumber : ""))
            .put("questionnaireConfigId", config != null ? config.questionnaireId : "")
            .put("questionnaireConfigVersion", config != null ? config.questionnaireVersion : "")
            .put("timestampUtc", exportedAt)
            .put("participant", new JSONObject()
                .put("participantId", participant != null ? clean(participant.participantId) : "")
                .put("name", participant != null ? clean(participant.name) : "")
                .put("language", participant != null ? clean(participant.language) : ""))
            .put("dimension", new JSONObject()
                .put("index", traceIndex)
                .put("id", clean(dimension.id))
                .put("label", clean(dimension.dimensionLabel))
                .put("description", clean(dimension.dimensionDescription))
                .put("audioFile", clean(dimension.audioFile))
                .put("rawPointCount", rawPoints == null ? 0 : rawPoints.size())
                .put("resampledPointCount", resampledPoints.size())
                .put("startedAtUtc", firstTimestamp(rawPoints))
                .put("completedAtUtc", lastTimestamp(rawPoints)))
            .put("axis", axisJson(dimension.axis));

        json.put("points", pointsJson(dimension.axis, resampledPoints));
        json.put("rawPoints", pointsJson(dimension.axis, rawPoints));
        return json;
    }

    private static JSONObject axisJson(QuestionnaireData.RuntimeTemporalAxis axis) throws Exception {
        return new JSONObject()
            .put("viewBoxWidth", axis.viewBoxWidth)
            .put("viewBoxHeight", axis.viewBoxHeight)
            .put("xMin", axis.xMin)
            .put("xMax", axis.xMax)
            .put("xUnit", axis.xUnit)
            .put("yMin", axis.yMin)
            .put("yMax", axis.yMax)
            .put("yMinLabel", axis.yMinLabel)
            .put("yMaxLabel", axis.yMaxLabel)
            .put("targetSampleCount", axis.targetSampleCount)
            .put("xBins", new JSONArray(axis.xBins))
            .put("yBins", new JSONArray(axis.yBins));
    }

    private static JSONArray pointsJson(QuestionnaireData.RuntimeTemporalAxis axis, List<TracePoint> points) throws Exception {
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
                .put("x_axis", axis.xAxisAt(point.u))
                .put("x_axisUnit", axis.xUnit)
                .put("y_axis", axis.yAxisAt(point.v)));
        }
        return array;
    }

    private static String buildCsv(
        QuestionnaireLaunchContext launchContext,
        QuestionnaireData.RuntimeConfig config,
        QuestionnaireData.ParticipantInfo participant,
        int traceIndex,
        QuestionnaireData.RuntimeTemporalDimension dimension,
        List<TracePoint> points,
        String exportedAt) {

        StringBuilder csv = new StringBuilder();
        csv.append("runId,sessionId,participantId,participantName,language,questionnaireConfigId,experimentId,scenarioId,trialId,chainId,chainStepId,triggerId,blockId,blockNumber,traceIndex,dimensionId,dimensionLabel,pointIndex,timestampUtc,timestampMillis,u_0to1,v_0to1,x_axis,x_axisUnit,y_axis,exportedAtUtc\n");
        for (int i = 0; i < points.size(); i++) {
            TracePoint point = points.get(i);
            csv.append(esc(launchContext != null ? launchContext.runId : "")).append(',')
                .append(esc(launchContext != null ? launchContext.sessionId : "")).append(',')
                .append(esc(participant != null ? participant.participantId : "")).append(',')
                .append(esc(participant != null ? participant.name : "")).append(',')
                .append(esc(participant != null ? participant.language : "")).append(',')
                .append(esc(config != null ? config.questionnaireId : "")).append(',')
                .append(esc(launchContext != null ? launchContext.experimentId : "")).append(',')
                .append(esc(launchContext != null ? launchContext.scenarioId : "")).append(',')
                .append(esc(launchContext != null ? launchContext.trialId : "")).append(',')
                .append(esc(launchContext != null ? launchContext.chainId : "")).append(',')
                .append(esc(launchContext != null ? launchContext.chainStepId : "")).append(',')
                .append(esc(launchContext != null ? launchContext.triggerId : "")).append(',')
                .append(esc(launchContext != null ? launchContext.blockId : "")).append(',')
                .append(esc(launchContext != null ? launchContext.blockNumber : "")).append(',')
                .append(traceIndex).append(',')
                .append(esc(dimension.id)).append(',')
                .append(esc(dimension.dimensionLabel)).append(',')
                .append(i).append(',')
                .append(esc(point.timestampUtc)).append(',')
                .append(point.timestampMillis).append(',')
                .append(fmt(point.u)).append(',')
                .append(fmt(point.v)).append(',')
                .append(fmt(dimension.axis.xAxisAt(point.u))).append(',')
                .append(esc(dimension.axis.xUnit)).append(',')
                .append(fmt(dimension.axis.yAxisAt(point.v))).append(',')
                .append(esc(exportedAt)).append('\n');
        }
        return csv.toString();
    }

    private static String buildSvg(
        QuestionnaireLaunchContext launchContext,
        QuestionnaireData.RuntimeConfig config,
        int traceIndex,
        QuestionnaireData.RuntimeTemporalDimension dimension,
        List<TracePoint> rawPoints,
        List<TracePoint> points,
        JSONObject metadata) {

        QuestionnaireData.RuntimeTemporalAxis axis = dimension.axis;
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
        svg.append("  <title>").append(xml(config != null ? config.questionnaireId : "questionnaire"))
            .append(" / ").append(xml(dimension.dimensionLabel)).append("</title>\n");
        svg.append("  <desc>runId=").append(xml(launchContext != null ? launchContext.runId : ""))
            .append(" traceIndex=").append(traceIndex).append("</desc>\n");
        svg.append("  <metadata><![CDATA[").append(metadata.toString().replace("]]>", "]]]]><![CDATA[>")).append("]]></metadata>\n");
        svg.append("  <rect x=\"0\" y=\"0\" width=\"").append(axis.viewBoxWidth).append("\" height=\"").append(axis.viewBoxHeight).append("\" fill=\"none\"/>\n");
        for (int i = 0; i < axis.yBins.size(); i++) {
            double y = axis.yBins.size() <= 1 ? 0.0 : (axis.viewBoxHeight * i) / (double) (axis.yBins.size() - 1);
            svg.append("  <line x1=\"0\" y1=\"").append(fmt(y)).append("\" x2=\"").append(axis.viewBoxWidth).append("\" y2=\"").append(fmt(y)).append("\" stroke=\"")
                .append(xml(colorHex(axis.gridColor))).append("\" stroke-width=\"0.4\" opacity=\"0.45\"/>\n");
        }
        for (int i = 0; i < axis.xBins.size(); i++) {
            double x = axis.xBins.size() <= 1 ? 0.0 : (axis.viewBoxWidth * i) / (double) (axis.xBins.size() - 1);
            svg.append("  <line x1=\"").append(fmt(x)).append("\" y1=\"0\" x2=\"").append(fmt(x)).append("\" y2=\"").append(axis.viewBoxHeight).append("\" stroke=\"")
                .append(xml(colorHex(axis.gridColor))).append("\" stroke-width=\"0.4\" opacity=\"0.45\"/>\n");
        }
        svg.append("  <text x=\"2\" y=\"4\" font-family=\"Arial\" font-size=\"3.5\" fill=\"")
            .append(xml(colorHex(axis.axisColor))).append("\">").append(xml(axis.yMaxLabel)).append("</text>\n");
        svg.append("  <text x=\"2\" y=\"").append(fmt(axis.viewBoxHeight - 6.0)).append("\" font-family=\"Arial\" font-size=\"3.5\" fill=\"")
            .append(xml(colorHex(axis.axisColor))).append("\">").append(xml(axis.yMinLabel)).append("</text>\n");
        svg.append("  <rect x=\"0\" y=\"0\" width=\"").append(axis.viewBoxWidth).append("\" height=\"").append(axis.viewBoxHeight).append("\" fill=\"none\" stroke=\"")
            .append(xml(colorHex(axis.axisColor))).append("\" stroke-width=\"0.8\"/>\n");
        svg.append("  <path id=\"trace-smooth-vector\" d=\"").append(smoothPath).append("\" fill=\"none\" stroke=\"")
            .append(xml(colorHex(axis.traceColor))).append("\" stroke-width=\"")
            .append(fmt(axis.strokeWidth)).append("\" stroke-linecap=\"round\" stroke-linejoin=\"round\" vector-effect=\"non-scaling-stroke\"/>\n");
        svg.append("  <polyline id=\"trace-raw-captured-points\" points=\"").append(rawPointString)
            .append("\" fill=\"none\" stroke=\"none\" data-role=\"raw-captured-vector\"/>\n");
        svg.append("  <polyline id=\"trace-normalized-analysis-points\" points=\"").append(normalizedPointString)
            .append("\" fill=\"none\" stroke=\"none\" data-role=\"normalized-analysis-vector\"/>\n");
        svg.append("</svg>\n");
        return svg.toString();
    }

    private static String pointString(QuestionnaireData.RuntimeTemporalAxis axis, List<TracePoint> points) {
        StringBuilder value = new StringBuilder();
        if (points == null) {
            return "";
        }
        for (TracePoint point : points) {
            double x = TemporalTraceMath.clamp(point.u, 0.0, 1.0) * axis.viewBoxWidth;
            double y = (1.0 - TemporalTraceMath.clamp(point.v, 0.0, 1.0)) * axis.viewBoxHeight;
            if (value.length() > 0) {
                value.append(' ');
            }
            value.append(fmt(x)).append(',').append(fmt(y));
        }
        return value.toString();
    }

    private static String smoothPath(QuestionnaireData.RuntimeTemporalAxis axis, List<TracePoint> points) {
        if (points == null || points.isEmpty()) {
            return "";
        }
        TracePoint first = points.get(0);
        StringBuilder path = new StringBuilder()
            .append("M ").append(fmt(TemporalTraceMath.clamp(first.u, 0.0, 1.0) * axis.viewBoxWidth))
            .append(' ').append(fmt((1.0 - TemporalTraceMath.clamp(first.v, 0.0, 1.0)) * axis.viewBoxHeight));
        for (int i = 1; i < points.size(); i++) {
            TracePoint a = points.get(i - 1);
            TracePoint b = points.get(i);
            double ax = TemporalTraceMath.clamp(a.u, 0.0, 1.0) * axis.viewBoxWidth;
            double ay = (1.0 - TemporalTraceMath.clamp(a.v, 0.0, 1.0)) * axis.viewBoxHeight;
            double bx = TemporalTraceMath.clamp(b.u, 0.0, 1.0) * axis.viewBoxWidth;
            double by = (1.0 - TemporalTraceMath.clamp(b.v, 0.0, 1.0)) * axis.viewBoxHeight;
            path.append(" Q ").append(fmt(ax)).append(' ').append(fmt(ay)).append(' ')
                .append(fmt((ax + bx) * 0.5)).append(' ').append(fmt((ay + by) * 0.5));
        }
        TracePoint last = points.get(points.size() - 1);
        path.append(" L ").append(fmt(TemporalTraceMath.clamp(last.u, 0.0, 1.0) * axis.viewBoxWidth))
            .append(' ').append(fmt((1.0 - TemporalTraceMath.clamp(last.v, 0.0, 1.0)) * axis.viewBoxHeight));
        return path.toString();
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

    private static String firstTimestamp(List<TracePoint> points) {
        return points == null || points.isEmpty() ? "" : points.get(0).timestampUtc;
    }

    private static String lastTimestamp(List<TracePoint> points) {
        return points == null || points.isEmpty() ? "" : points.get(points.size() - 1).timestampUtc;
    }

    private static String safeFileComponent(String value) {
        String clean = clean(value);
        return clean.isEmpty() ? "unnamed" : clean.replaceAll("[^A-Za-z0-9._-]+", "_");
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
}
