package org.mesmerprism.viscereality.temporaltracer2d;

import android.content.Context;
import android.graphics.Color;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

final class TemporalTracerConfig {
    static final String ASSET_PATH = "tracer/TemporalTracerConfig.json";

    final String schema;
    final String tracerId;
    final String tracerVersion;
    final String appVersion;
    final AxisConfig axis;
    final Map<String, UiText> uiByLanguage;
    final Map<String, List<TraceItem>> itemsByLanguage;

    private TemporalTracerConfig(
        String schema,
        String tracerId,
        String tracerVersion,
        String appVersion,
        AxisConfig axis,
        Map<String, UiText> uiByLanguage,
        Map<String, List<TraceItem>> itemsByLanguage) {
        this.schema = schema;
        this.tracerId = tracerId;
        this.tracerVersion = tracerVersion;
        this.appVersion = appVersion;
        this.axis = axis;
        this.uiByLanguage = uiByLanguage;
        this.itemsByLanguage = itemsByLanguage;
    }

    static TemporalTracerConfig load(Context context) {
        try (InputStream stream = context.getAssets().open(ASSET_PATH)) {
            ByteArrayOutputStream output = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int read;
            while ((read = stream.read(buffer)) >= 0) {
                output.write(buffer, 0, read);
            }
            return fromJson(new JSONObject(output.toString(StandardCharsets.UTF_8.name())));
        } catch (Exception ex) {
            throw new IllegalStateException("Could not load temporal tracer config asset: " + ASSET_PATH, ex);
        }
    }

    static TemporalTracerConfig fromJson(JSONObject root) {
        AxisConfig axis = AxisConfig.fromJson(root.optJSONObject("axis"));
        Map<String, UiText> ui = new LinkedHashMap<>();
        JSONObject uiRoot = root.optJSONObject("ui");
        if (uiRoot != null) {
            for (String language : jsonKeys(uiRoot)) {
                ui.put(language, UiText.fromJson(uiRoot.optJSONObject(language)));
            }
        }
        if (!ui.containsKey("English")) {
            ui.put("English", UiText.defaultsEnglish());
        }
        if (!ui.containsKey("Deutsch")) {
            ui.put("Deutsch", UiText.defaultsGerman());
        }

        Map<String, List<TraceItem>> items = new LinkedHashMap<>();
        JSONObject itemsRoot = root.optJSONObject("items");
        if (itemsRoot != null) {
            for (String language : jsonKeys(itemsRoot)) {
                JSONArray array = itemsRoot.optJSONArray(language);
                List<TraceItem> parsed = new ArrayList<>();
                if (array != null) {
                    for (int i = 0; i < array.length(); i++) {
                        parsed.add(TraceItem.fromJson(array.optJSONObject(i)));
                    }
                }
                items.put(language, Collections.unmodifiableList(parsed));
            }
        }

        return new TemporalTracerConfig(
            root.optString("schema", "temporal-experience-tracer.config.v1"),
            root.optString("tracerId", "temporal-experience-tracer"),
            root.optString("tracerVersion", "unknown"),
            root.optString("appVersion", "0.1.0"),
            axis,
            Collections.unmodifiableMap(ui),
            Collections.unmodifiableMap(items));
    }

    List<String> languages() {
        return new ArrayList<>(uiByLanguage.keySet());
    }

    UiText ui(String language) {
        UiText text = uiByLanguage.get(normalizeLanguage(language));
        return text != null ? text : uiByLanguage.get("English");
    }

    List<TraceItem> items(String language) {
        List<TraceItem> items = itemsByLanguage.get(normalizeLanguage(language));
        if (items != null && !items.isEmpty()) {
            return items;
        }
        List<TraceItem> english = itemsByLanguage.get("English");
        return english != null ? english : Collections.emptyList();
    }

    String normalizeLanguage(String language) {
        String clean = TemporalTracerLaunchContext.clean(language);
        if (clean.equalsIgnoreCase("de") || clean.equalsIgnoreCase("german") || clean.equalsIgnoreCase("deutsch")) {
            return "Deutsch";
        }
        if (clean.equalsIgnoreCase("en") || clean.equalsIgnoreCase("english")) {
            return "English";
        }
        return uiByLanguage.containsKey(clean) ? clean : "English";
    }

    JSONObject toSummaryJson(String language) throws Exception {
        return new JSONObject()
            .put("schema", schema)
            .put("tracerId", tracerId)
            .put("tracerVersion", tracerVersion)
            .put("appVersion", appVersion)
            .put("language", normalizeLanguage(language))
            .put("axis", axis.toJson(normalizeLanguage(language)))
            .put("itemCount", items(language).size());
    }

    static final class AxisConfig {
        final int viewBoxWidth;
        final int viewBoxHeight;
        final double durationValue;
        final String durationUnit;
        final double yMin;
        final double yMax;
        final double startGatePercent;
        final double endGatePercent;
        final int targetSampleCount;
        final double strokeWidth;
        final int traceColor;
        final int axisColor;
        final int gridColor;
        final Map<String, String> topLabel;
        final Map<String, String> bottomLabel;
        final List<String> horizontalGridLabels;
        final List<String> verticalGridLabels;

        private AxisConfig(
            int viewBoxWidth,
            int viewBoxHeight,
            double durationValue,
            String durationUnit,
            double yMin,
            double yMax,
            double startGatePercent,
            double endGatePercent,
            int targetSampleCount,
            double strokeWidth,
            int traceColor,
            int axisColor,
            int gridColor,
            Map<String, String> topLabel,
            Map<String, String> bottomLabel,
            List<String> horizontalGridLabels,
            List<String> verticalGridLabels) {
            this.viewBoxWidth = Math.max(10, viewBoxWidth);
            this.viewBoxHeight = Math.max(10, viewBoxHeight);
            this.durationValue = durationValue;
            this.durationUnit = durationUnit == null ? "" : durationUnit;
            this.yMin = yMin;
            this.yMax = yMax;
            this.startGatePercent = clamp(startGatePercent, 0.0, 49.0);
            this.endGatePercent = clamp(endGatePercent, 51.0, 100.0);
            this.targetSampleCount = Math.max(2, targetSampleCount);
            this.strokeWidth = Math.max(0.1, strokeWidth);
            this.traceColor = traceColor;
            this.axisColor = axisColor;
            this.gridColor = gridColor;
            this.topLabel = topLabel;
            this.bottomLabel = bottomLabel;
            this.horizontalGridLabels = horizontalGridLabels;
            this.verticalGridLabels = verticalGridLabels;
        }

        static AxisConfig fromJson(JSONObject json) {
            JSONObject source = json == null ? new JSONObject() : json;
            return new AxisConfig(
                source.optInt("viewBoxWidth", 1000),
                source.optInt("viewBoxHeight", 100),
                source.optDouble("durationValue", 10.0),
                source.optString("durationUnit", "min"),
                source.optDouble("yMin", 0.0),
                source.optDouble("yMax", 100.0),
                source.optDouble("startGatePercent", 5.0),
                source.optDouble("endGatePercent", 95.0),
                source.optInt("targetSampleCount", 1000),
                source.optDouble("strokeWidth", 2.5),
                parseColor(source.optString("traceColor", "#28D17C")),
                parseColor(source.optString("axisColor", "#F4F5F7")),
                parseColor(source.optString("gridColor", "#7F8794")),
                parseLanguageMap(source.optJSONObject("topLabel"), "Yes, very much more than usual", "Ja, sehr viel mehr als gewoehnlich"),
                parseLanguageMap(source.optJSONObject("bottomLabel"), "No, not more than usual", "Nein, nicht mehr als gewoehnlich"),
                parseStringArray(source.optJSONArray("horizontalGridLabels"), defaultHorizontalLabels()),
                parseStringArray(source.optJSONArray("verticalGridLabels"), defaultVerticalLabels(source.optInt("durationValue", 10), source.optString("durationUnit", "min"))));
        }

        String topLabel(String language) {
            return localized(topLabel, language);
        }

        String bottomLabel(String language) {
            return localized(bottomLabel, language);
        }

        double durationAt(double u) {
            return clamp(u, 0.0, 1.0) * durationValue;
        }

        double valueAt(double v) {
            return yMin + clamp(v, 0.0, 1.0) * (yMax - yMin);
        }

        JSONObject toJson(String language) throws Exception {
            return new JSONObject()
                .put("viewBoxWidth", viewBoxWidth)
                .put("viewBoxHeight", viewBoxHeight)
                .put("durationValue", durationValue)
                .put("durationUnit", durationUnit)
                .put("yMin", yMin)
                .put("yMax", yMax)
                .put("startGatePercent", startGatePercent)
                .put("endGatePercent", endGatePercent)
                .put("targetSampleCount", targetSampleCount)
                .put("strokeWidth", strokeWidth)
                .put("topLabel", topLabel(language))
                .put("bottomLabel", bottomLabel(language))
                .put("horizontalGridLabels", new JSONArray(horizontalGridLabels))
                .put("verticalGridLabels", new JSONArray(verticalGridLabels));
        }
    }

    static final class UiText {
        final String appTitle;
        final String languageTitle;
        final String participantTitle;
        final String participantNameHint;
        final String participantIdHint;
        final String continueLabel;
        final String backLabel;
        final String clearLabel;
        final String saveNextLabel;
        final String completeToSaveLabel;
        final String completeLabel;
        final String savedTitle;
        final String finishedTitle;
        final String finishedBody;
        final String introButton;

        private UiText(JSONObject source, UiText defaults) {
            this.appTitle = opt(source, "appTitle", defaults.appTitle);
            this.languageTitle = opt(source, "languageTitle", defaults.languageTitle);
            this.participantTitle = opt(source, "participantTitle", defaults.participantTitle);
            this.participantNameHint = opt(source, "participantNameHint", defaults.participantNameHint);
            this.participantIdHint = opt(source, "participantIdHint", defaults.participantIdHint);
            this.continueLabel = opt(source, "continueLabel", defaults.continueLabel);
            this.backLabel = opt(source, "backLabel", defaults.backLabel);
            this.clearLabel = opt(source, "clearLabel", defaults.clearLabel);
            this.saveNextLabel = opt(source, "saveNextLabel", defaults.saveNextLabel);
            this.completeToSaveLabel = opt(source, "completeToSaveLabel", defaults.completeToSaveLabel);
            this.completeLabel = opt(source, "completeLabel", defaults.completeLabel);
            this.savedTitle = opt(source, "savedTitle", defaults.savedTitle);
            this.finishedTitle = opt(source, "finishedTitle", defaults.finishedTitle);
            this.finishedBody = opt(source, "finishedBody", defaults.finishedBody);
            this.introButton = opt(source, "introButton", defaults.introButton);
        }

        static UiText fromJson(JSONObject source) {
            return new UiText(source == null ? new JSONObject() : source, defaultsEnglish());
        }

        static UiText defaultsEnglish() {
            return new UiText();
        }

        static UiText defaultsGerman() {
            JSONObject json = new JSONObject();
            try {
                json.put("appTitle", "Temporaler Erlebnis-Tracer");
                json.put("languageTitle", "Sprache waehlen");
                json.put("participantTitle", "Teilnehmer");
                json.put("participantNameHint", "Name");
                json.put("participantIdHint", "Teilnehmer-ID");
                json.put("continueLabel", "Weiter");
                json.put("backLabel", "Zurueck");
                json.put("clearLabel", "Linie loeschen");
                json.put("saveNextLabel", "Linie speichern");
                json.put("completeToSaveLabel", "Links beginnen und bis zum rechten Rand zeichnen");
                json.put("completeLabel", "Linie vollstaendig");
                json.put("savedTitle", "Gespeichert");
                json.put("finishedTitle", "Fertig");
                json.put("finishedBody", "Alle Linien wurden lokal auf dem Headset gespeichert.");
                json.put("introButton", "Text lesen, Uebungslinie vollstaendig zeichnen, dann fortfahren");
            } catch (Exception ignored) {
            }
            return new UiText(json, defaultsEnglish());
        }

        private UiText() {
            this.appTitle = "Temporal Experience Tracer";
            this.languageTitle = "Choose language";
            this.participantTitle = "Participant";
            this.participantNameHint = "Participant name";
            this.participantIdHint = "Participant ID";
            this.continueLabel = "Continue";
            this.backLabel = "Back";
            this.clearLabel = "Clear trace";
            this.saveNextLabel = "Save trace";
            this.completeToSaveLabel = "Start at the left edge and draw to the right edge";
            this.completeLabel = "Trace complete";
            this.savedTitle = "Saved";
            this.finishedTitle = "Finished";
            this.finishedBody = "All traces were saved locally on the headset.";
            this.introButton = "Read, complete the practice trace, then continue";
        }
    }

    static final class TraceItem {
        final String label;
        final String message;
        final String audioFile;

        private TraceItem(String label, String message, String audioFile) {
            this.label = label == null || label.trim().isEmpty() ? "trace" : label.trim();
            this.message = message == null ? "" : message.trim();
            this.audioFile = audioFile == null ? "" : audioFile.trim();
        }

        static TraceItem fromJson(JSONObject json) {
            if (json == null) {
                return new TraceItem("trace", "", "");
            }
            return new TraceItem(json.optString("label", "trace"), json.optString("message", ""), json.optString("audioFile", ""));
        }
    }

    private static String opt(JSONObject json, String key, String fallback) {
        if (json == null) {
            return fallback;
        }
        String value = json.optString(key, fallback);
        return value == null || value.trim().isEmpty() ? fallback : value;
    }

    private static Map<String, String> parseLanguageMap(JSONObject object, String english, String german) {
        Map<String, String> map = new LinkedHashMap<>();
        map.put("English", english);
        map.put("Deutsch", german);
        if (object != null) {
            for (String key : jsonKeys(object)) {
                String value = object.optString(key, "");
                if (!value.trim().isEmpty()) {
                    map.put(key, value.trim());
                }
            }
        }
        return Collections.unmodifiableMap(map);
    }

    private static String localized(Map<String, String> map, String language) {
        if (map.containsKey(language)) {
            return map.get(language);
        }
        return map.getOrDefault("English", "");
    }

    private static List<String> parseStringArray(JSONArray array, List<String> fallback) {
        if (array == null || array.length() == 0) {
            return fallback;
        }
        List<String> values = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            values.add(array.optString(i, ""));
        }
        return Collections.unmodifiableList(values);
    }

    private static List<String> defaultHorizontalLabels() {
        List<String> labels = new ArrayList<>();
        for (int value = 100; value >= 0; value -= 10) {
            labels.add(Integer.toString(value));
        }
        return Collections.unmodifiableList(labels);
    }

    private static List<String> defaultVerticalLabels(int durationValue, String unit) {
        List<String> labels = new ArrayList<>();
        int steps = Math.max(1, durationValue);
        for (int i = 0; i <= steps; i++) {
            labels.add(String.format(Locale.US, "%d%s", i, unit == null ? "" : unit));
        }
        return Collections.unmodifiableList(labels);
    }

    private static int parseColor(String color) {
        try {
            return Color.parseColor(color);
        } catch (Exception ignored) {
            return Color.WHITE;
        }
    }

    private static List<String> jsonKeys(JSONObject object) {
        List<String> keys = new ArrayList<>();
        if (object == null) {
            return keys;
        }
        Iterator<String> iterator = object.keys();
        while (iterator.hasNext()) {
            keys.add(iterator.next());
        }
        return keys;
    }

    static double clamp(double value, double min, double max) {
        return Math.max(min, Math.min(max, value));
    }
}
