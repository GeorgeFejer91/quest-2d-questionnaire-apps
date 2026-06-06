package org.mesmerprism.viscereality.temporaltracer2d;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.view.View;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

import java.io.File;
import java.io.FileOutputStream;
import java.security.MessageDigest;
import java.util.Locale;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public final class RenderTemporalTracerVisualsTest {
    @Test
    public void renderTemporalTracerStagesWhenEnabled() throws Exception {
        if (!Boolean.parseBoolean(System.getProperty("temporalTracer.render.enabled", "false"))) {
            return;
        }

        Context context = RuntimeEnvironment.getApplication();
        TemporalTracerConfig config = TemporalTracerConfig.load(context);
        TemporalTracerScreenBuilder builder = new TemporalTracerScreenBuilder(context);
        String runId = System.getProperty("temporalTracer.render.runId", "");
        if (runId.trim().isEmpty()) {
            runId = "render-" + TimeUtil.utcFileStampMillis();
        }
        String outputDir = System.getProperty("temporalTracer.render.outputDir", "");
        File output = outputDir.trim().isEmpty()
            ? new File("artifacts/temporal-tracer-render-validation/" + runId)
            : new File(outputDir);
        if (!output.exists() && !output.mkdirs()) {
            throw new IllegalStateException("Could not create render output directory: " + output);
        }

        JSONArray renders = new JSONArray();
        for (Dimension dimension : parseDimensions(System.getProperty("temporalTracer.render.sizes", "1280x800,900x800"))) {
            renders.put(renderOne(output, dimension, "language", "language", "neutral",
                builder.languageScreen(config, v -> {}, v -> {}).root));
            renders.put(renderOne(output, dimension, "finished-black", "black", "neutral", builder.blackScreen()));

            for (String language : new String[] {"English", "Deutsch"}) {
                TemporalTracerConfig.UiText ui = config.ui(language);
                TemporalTracerLaunchContext launch = TemporalTracerLaunchContext.fromIntent(null);
                TemporalTracerScreenBuilder.ParticipantScreen participant = builder.participantScreen(ui, launch, v -> {}, v -> {});
                participant.participantName.setText("George");
                participant.participantId.setText("P001");
                renders.put(renderOne(output, dimension, "participant", "participant", language, participant.root));

                TemporalTracerConfig.TraceItem item = config.items(language).get(Math.min(1, config.items(language).size() - 1));
                TemporalTracerScreenBuilder.TraceScreen emptyTrace = builder.traceScreen(ui, config.axis, language, item, 1, config.items(language).size(), v -> {}, v -> {}, v -> {});
                JSONObject emptyRender = renderOne(output, dimension, "trace-empty", "trace", language, emptyTrace.root);
                renders.put(emptyRender);

                TemporalTracerScreenBuilder.TraceScreen completeTrace = builder.traceScreen(ui, config.axis, language, item, 1, config.items(language).size(), v -> {}, v -> {}, v -> {});
                completeTrace.traceCanvas.seedFixtureTrace();
                if (completeTrace.traceCanvas.rawPoints().isEmpty()) {
                    throw new AssertionError("Fixture trace did not seed raw points.");
                }
                completeTrace.saveButton.setEnabled(true);
                completeTrace.status.setText(ui.completeLabel);
                JSONObject completeRender = renderOne(output, dimension, "trace-complete", "trace", language, completeTrace.root);
                completeRender.put("fixtureRawPointCount", completeTrace.traceCanvas.rawPoints().size());
                if (emptyRender.getString("sha256").equals(completeRender.getString("sha256"))) {
                    completeRender.getJSONArray("fail").put("completed fixture render matches empty trace render");
                    completeRender.put("status", "fail");
                }
                renders.put(completeRender);

                TraceCanvasView directCanvas = new TraceCanvasView(context);
                directCanvas.configure(config.axis, language);
                directCanvas.seedFixtureTrace();
                JSONObject directRender = renderOne(output, dimension, "trace-canvas-complete-direct", "trace-canvas", language, directCanvas);
                directRender.put("fixtureRawPointCount", directCanvas.rawPoints().size());
                renders.put(directRender);

                renders.put(renderOne(output, dimension, "saved-confirmation", "saved", language,
                    builder.savedScreen(ui, "SVG:\n/device/TemporalTraceExports/fixture.svg\n\nCSV:\n/device/TemporalTraceExports/fixture.csv", v -> {}).root));
            }
        }

        JSONObject summary = new JSONObject();
        summary.put("schemaVersion", "temporal-tracer-2d.render-validation.v1");
        summary.put("runId", runId);
        summary.put("outputDir", output.getAbsolutePath());
        summary.put("renderer", "robolectric-android-view-draw");
        summary.put("config", config.toSummaryJson("English"));
        summary.put("renders", renders);
        try (FileOutputStream stream = new FileOutputStream(new File(output, "render-summary.json"))) {
            stream.write(summary.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }
    }

    private JSONObject renderOne(File output, Dimension dimension, String stage, String screenId, String language, View root) throws Exception {
        root.measure(
            View.MeasureSpec.makeMeasureSpec(dimension.width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(dimension.height, View.MeasureSpec.EXACTLY));
        root.layout(0, 0, dimension.width, dimension.height);

        Bitmap image = Bitmap.createBitmap(dimension.width, dimension.height, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(image);
        root.draw(canvas);

        String name = dimension.label() + "_" + sanitize(language) + "_" + sanitize(stage) + ".png";
        File png = new File(output, name);
        try (FileOutputStream stream = new FileOutputStream(png)) {
            image.compress(Bitmap.CompressFormat.PNG, 100, stream);
        }

        JSONObject checks = checkImage(stage, image);
        return new JSONObject()
            .put("stageName", stage)
            .put("expectedScreenId", screenId)
            .put("language", language)
            .put("widthDp", dimension.width)
            .put("heightDp", dimension.height)
            .put("png", png.getAbsolutePath())
            .put("byteLength", png.length())
            .put("sha256", sha256(png))
            .put("status", checks.getString("status"))
            .put("pass", checks.getJSONArray("pass"))
            .put("warn", checks.getJSONArray("warn"))
            .put("fail", checks.getJSONArray("fail"));
    }

    private static JSONObject checkImage(String stage, Bitmap image) throws Exception {
        int nonBlack = 0;
        int nonTransparent = 0;
        for (int y = 0; y < image.getHeight(); y += Math.max(1, image.getHeight() / 80)) {
            for (int x = 0; x < image.getWidth(); x += Math.max(1, image.getWidth() / 80)) {
                int color = image.getPixel(x, y);
                if (Color.alpha(color) > 0) {
                    nonTransparent++;
                }
                if ((color & 0x00FFFFFF) != 0) {
                    nonBlack++;
                }
            }
        }
        JSONArray pass = new JSONArray();
        JSONArray warn = new JSONArray();
        JSONArray fail = new JSONArray();
        if ("finished-black".equals(stage)) {
            if (nonBlack == 0) {
                pass.put("final black state is black");
            } else {
                fail.put("final black state has nonblack pixels");
            }
        } else if (nonBlack > 50 && nonTransparent > 50) {
            pass.put("render is nonblank");
        } else {
            fail.put("render appears blank");
        }
        return new JSONObject()
            .put("status", fail.length() == 0 ? (warn.length() == 0 ? "pass" : "warn") : "fail")
            .put("pass", pass)
            .put("warn", warn)
            .put("fail", fail);
    }

    private static Dimension[] parseDimensions(String value) {
        String[] parts = value.split(",");
        Dimension[] dimensions = new Dimension[parts.length];
        for (int i = 0; i < parts.length; i++) {
            String[] xy = parts[i].trim().split("x");
            dimensions[i] = new Dimension(Integer.parseInt(xy[0]), Integer.parseInt(xy[1]));
        }
        return dimensions;
    }

    private static String sha256(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] bytes = java.nio.file.Files.readAllBytes(file.toPath());
        byte[] hash = digest.digest(bytes);
        StringBuilder builder = new StringBuilder();
        for (byte b : hash) {
            builder.append(String.format(Locale.US, "%02x", b));
        }
        return builder.toString();
    }

    private static String sanitize(String value) {
        return value == null ? "unknown" : value.replaceAll("[^A-Za-z0-9._-]+", "_");
    }

    private static final class Dimension {
        final int width;
        final int height;

        Dimension(int width, int height) {
            this.width = width;
            this.height = height;
        }

        String label() {
            return width + "x" + height;
        }
    }
}
