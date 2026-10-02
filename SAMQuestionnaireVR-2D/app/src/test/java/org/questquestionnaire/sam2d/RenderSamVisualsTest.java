package org.questquestionnaire.sam2d;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.View;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;

import java.io.File;
import java.io.FileOutputStream;
import java.security.MessageDigest;
import java.util.Locale;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public final class RenderSamVisualsTest {
    private static final int BG = Color.rgb(248, 250, 252);
    private static final int TEXT = Color.rgb(17, 24, 39);
    private static final int MUTED = Color.rgb(71, 85, 105);
    private static final int ACTIVE = Color.rgb(0, 92, 255);

    @Test
    public void renderSamStagesWhenEnabled() throws Exception {
        if (!Boolean.parseBoolean(System.getProperty("sam.render.enabled", "false"))) {
            return;
        }

        Context context = RuntimeEnvironment.getApplication();
        String runId = System.getProperty("sam.render.runId", "");
        if (runId.trim().isEmpty()) {
            runId = "render-" + TimeUtil.utcFileStampMillis();
        }
        String outputDir = System.getProperty("sam.render.outputDir", "");
        File output = outputDir.trim().isEmpty()
            ? new File("artifacts/sam-render-validation/" + runId)
            : new File(outputDir);
        if (!output.exists() && !output.mkdirs()) {
            throw new IllegalStateException("Could not create render output directory: " + output);
        }

        JSONArray renders = new JSONArray();
        for (Dimension dimension : parseDimensions(System.getProperty("sam.render.sizes", "1280x800,900x800"))) {
            renders.put(renderSamScreen(context, output, dimension, "sam-empty", 0, 0));
            renders.put(renderSamScreen(context, output, dimension, "sam-selected", 5, 4));
            renders.put(renderSliderScreen(output, dimension, "affective-slider", 100, 75));
            renders.put(renderSavedScreen(output, dimension, "saved"));
        }

        JSONObject summary = new JSONObject();
        summary.put("schemaVersion", "sam-2d.render-validation.v1");
        summary.put("runId", runId);
        summary.put("outputDir", output.getAbsolutePath());
        summary.put("renderer", "android-canvas-sam-fixture");
        summary.put("renders", renders);
        try (FileOutputStream stream = new FileOutputStream(new File(output, "render-summary.json"))) {
            stream.write(summary.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }
    }

    private JSONObject renderSamScreen(Context context, File output, Dimension dimension, String stage, int valenceScore, int arousalScore) throws Exception {
        Bitmap image = blank(dimension);
        Canvas canvas = new Canvas(image);
        Paint paint = paint();
        float margin = 26f;
        drawCenteredText(canvas, paint, "Rate the previous session", dimension.width / 2f, 58f, 28f, TEXT, true);
        drawCenteredText(canvas, paint, "Select one figure on each row to show how you felt during the previous session.", dimension.width / 2f, 94f, 17f, MUTED, false);

        SamScaleView valence = new SamScaleView(context);
        valence.configure("valence", "Valence", "Very unpleasant", "Very pleasant", "valence");
        valence.setActiveRow(true);
        if (valenceScore > 0) {
            valence.setSelectedScore(valenceScore);
        }
        drawChild(canvas, valence, margin, 110f, dimension.width - 2f * margin, 288f);

        SamScaleView arousal = new SamScaleView(context);
        arousal.configure("arousal", "Arousal", "Very calm", "Very excited", "arousal");
        if (arousalScore > 0) {
            arousal.setSelectedScore(arousalScore);
        }
        drawChild(canvas, arousal, margin, 408f, dimension.width - 2f * margin, 288f);

        drawButton(canvas, paint, "Reset", margin, dimension.height - 86f, (dimension.width - 3f * margin) / 2f, 62f, false);
        drawButton(canvas, paint, "Next", (dimension.width + margin) / 2f, dimension.height - 86f, (dimension.width - 3f * margin) / 2f, 62f, true);
        return writeRender(output, dimension, stage, "sam", image);
    }

    private JSONObject renderSliderScreen(File output, Dimension dimension, String stage, int valence, int arousal) throws Exception {
        Bitmap image = blank(dimension);
        Canvas canvas = new Canvas(image);
        Paint paint = paint();
        drawCenteredText(canvas, paint, "Rate the previous session on sliders", dimension.width / 2f, 58f, 28f, TEXT, true);
        drawCenteredText(canvas, paint, "Move each slider to match how you felt during the previous session.", dimension.width / 2f, 96f, 17f, MUTED, false);
        drawSlider(canvas, paint, "Valence", "Very unpleasant", "Very pleasant", valence, 136f, dimension);
        drawSlider(canvas, paint, "Arousal", "Very calm", "Very excited", arousal, 424f, dimension);
        float margin = 34f;
        drawButton(canvas, paint, "Back", margin, dimension.height - 86f, (dimension.width - 3f * margin) / 2f, 62f, false);
        drawButton(canvas, paint, "Submit", (dimension.width + margin) / 2f, dimension.height - 86f, (dimension.width - 3f * margin) / 2f, 62f, true);
        return writeRender(output, dimension, stage, "affective-slider", image);
    }

    private JSONObject renderSavedScreen(File output, Dimension dimension, String stage) throws Exception {
        Bitmap image = blank(dimension);
        Canvas canvas = new Canvas(image);
        Paint paint = paint();
        drawCenteredText(canvas, paint, "Complete", dimension.width / 2f, 180f, 28f, TEXT, true);
        drawCenteredText(canvas, paint, "Saved JSON and CSV exports under SamQuestionnaireExports.", dimension.width / 2f, 240f, 18f, MUTED, false);
        drawButton(canvas, paint, "Done", dimension.width * 0.25f, dimension.height - 140f, dimension.width * 0.5f, 62f, true);
        return writeRender(output, dimension, stage, "saved", image);
    }

    private static void drawChild(Canvas canvas, View view, float x, float y, float width, float height) {
        view.measure(
            View.MeasureSpec.makeMeasureSpec(Math.round(width), View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(Math.round(height), View.MeasureSpec.EXACTLY));
        view.layout(0, 0, Math.round(width), Math.round(height));
        canvas.save();
        canvas.translate(x, y);
        view.draw(canvas);
        canvas.restore();
    }

    private static void drawSlider(Canvas canvas, Paint paint, String title, String low, String high, int value, float top, Dimension dimension) {
        float margin = 62f;
        float width = dimension.width - 2f * margin;
        float titleY = top + 44f;
        drawText(canvas, paint, title, margin, titleY, 24f, TEXT, true);
        drawText(canvas, paint, low, margin, top + 92f, 16f, MUTED, false);
        paint.setTextAlign(Paint.Align.RIGHT);
        drawText(canvas, paint, high, dimension.width - margin, top + 92f, 16f, MUTED, false);
        paint.setTextAlign(Paint.Align.LEFT);

        float trackY = top + 145f;
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(8f);
        paint.setStrokeCap(Paint.Cap.ROUND);
        paint.setColor(Color.rgb(203, 213, 225));
        canvas.drawLine(margin, trackY, margin + width, trackY, paint);
        paint.setColor(ACTIVE);
        canvas.drawLine(margin, trackY, margin + width * value / 100f, trackY, paint);
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(Color.WHITE);
        float thumbX = margin + width * value / 100f;
        canvas.drawCircle(thumbX, trackY, 20f, paint);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(4f);
        paint.setColor(ACTIVE);
        canvas.drawCircle(thumbX, trackY, 20f, paint);
        paint.setStyle(Paint.Style.FILL);
        drawCenteredText(canvas, paint, Integer.toString(value), dimension.width / 2f, top + 205f, 22f, TEXT, true);
    }

    private static void drawButton(Canvas canvas, Paint paint, String text, float x, float y, float width, float height, boolean primary) {
        RectF rect = new RectF(x, y, x + width, y + height);
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(primary ? ACTIVE : Color.rgb(226, 232, 240));
        canvas.drawRoundRect(rect, 8f, 8f, paint);
        drawCenteredText(canvas, paint, text, rect.centerX(), rect.centerY() + 8f, 18f, primary ? Color.WHITE : TEXT, true);
    }

    private static void drawCenteredText(Canvas canvas, Paint paint, String text, float x, float y, float size, int color, boolean bold) {
        paint.setTextAlign(Paint.Align.CENTER);
        drawText(canvas, paint, text, x, y, size, color, bold);
        paint.setTextAlign(Paint.Align.LEFT);
    }

    private static void drawText(Canvas canvas, Paint paint, String text, float x, float y, float size, int color, boolean bold) {
        paint.setStyle(Paint.Style.FILL);
        paint.setColor(color);
        paint.setTextSize(size);
        paint.setFakeBoldText(bold);
        canvas.drawText(text, x, y, paint);
        paint.setFakeBoldText(false);
    }

    private static Bitmap blank(Dimension dimension) {
        Bitmap image = Bitmap.createBitmap(dimension.width, dimension.height, Bitmap.Config.ARGB_8888);
        image.eraseColor(BG);
        return image;
    }

    private static Paint paint() {
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setTextAlign(Paint.Align.LEFT);
        return paint;
    }

    private JSONObject writeRender(File output, Dimension dimension, String stage, String screenId, Bitmap image) throws Exception {
        String name = dimension.label() + "_" + sanitize(stage) + ".png";
        File png = new File(output, name);
        try (FileOutputStream stream = new FileOutputStream(png)) {
            image.compress(Bitmap.CompressFormat.PNG, 100, stream);
        }
        JSONObject checks = checkImage(image);
        return new JSONObject()
            .put("stageName", stage)
            .put("expectedScreenId", screenId)
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

    private static JSONObject checkImage(Bitmap image) throws Exception {
        int nonBackground = 0;
        for (int y = 0; y < image.getHeight(); y++) {
            for (int x = 0; x < image.getWidth(); x++) {
                if (image.getPixel(x, y) != BG) {
                    nonBackground++;
                }
            }
        }
        JSONArray pass = new JSONArray();
        JSONArray warn = new JSONArray();
        JSONArray fail = new JSONArray();
        if (nonBackground > 1000) {
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
