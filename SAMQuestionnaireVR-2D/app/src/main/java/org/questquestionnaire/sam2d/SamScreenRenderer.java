package org.questquestionnaire.sam2d;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Typeface;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.security.MessageDigest;
import java.util.Locale;

final class SamScreenRenderer {
    private static final int WIDTH = 1280;
    private static final int HEIGHT = 800;
    private static final int BG = Color.rgb(248, 250, 252);
    private static final int TEXT = Color.rgb(17, 24, 39);
    private static final int MUTED = Color.rgb(71, 85, 105);
    private static final int ACTIVE = Color.rgb(0, 92, 255);

    private SamScreenRenderer() {
    }

    static RenderResult renderSamSelected(Context context, String runId, int valence, int arousal) throws Exception {
        LinearLayout root = root(context);
        root.addView(title(context, "Rate the previous session"));
        root.addView(body(context, "Select one figure on each row to show how you felt during the previous session."));

        SamScaleView valenceView = new SamScaleView(context);
        valenceView.configure("valence", "Valence", "Very unpleasant", "Very pleasant", "valence");
        valenceView.setActiveRow(true);
        valenceView.setSelectedScore(valence);
        root.addView(valenceView, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        SamScaleView arousalView = new SamScaleView(context);
        arousalView.configure("arousal", "Arousal", "Very calm", "Very excited", "arousal");
        arousalView.setSelectedScore(arousal);
        root.addView(arousalView, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        LinearLayout footer = footer(context);
        footer.addView(button(context, "Reset", false), footerButtonParams(context));
        footer.addView(button(context, "Next", true), footerButtonParams(context));
        root.addView(footer);
        return writeView(context, root, runId, "sam-selected");
    }

    static RenderResult renderSliderSelected(Context context, String runId, int valence, int arousal) throws Exception {
        LinearLayout root = root(context);
        root.addView(title(context, "Rate the previous session on sliders"));
        root.addView(body(context, "Move each slider to match how you felt during the previous session, or leave it centered for neutral."));
        root.addView(sliderPanel(context, "Valence", "Very unpleasant", "Very pleasant", valence, true), new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        root.addView(sliderPanel(context, "Arousal", "Very calm", "Very excited", arousal, false), new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        LinearLayout footer = footer(context);
        footer.addView(button(context, "Back", false), footerButtonParams(context));
        footer.addView(button(context, "Submit", true), footerButtonParams(context));
        root.addView(footer);
        return writeView(context, root, runId, "affective-slider-selected");
    }

    static RenderResult renderSaved(Context context, String runId) throws Exception {
        LinearLayout root = root(context);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.addView(title(context, "Complete"));
        TextView message = body(context, "Saved JSON and CSV exports under SamQuestionnaireExports.");
        message.setGravity(Gravity.CENTER_HORIZONTAL);
        root.addView(message, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        root.addView(button(context, "Done", true), footerButtonParams(context));
        return writeView(context, root, runId, "saved");
    }

    private static RenderResult writeView(Context context, View view, String runId, String stage) throws Exception {
        view.measure(
            View.MeasureSpec.makeMeasureSpec(WIDTH, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(HEIGHT, View.MeasureSpec.EXACTLY));
        view.layout(0, 0, WIDTH, HEIGHT);
        Bitmap bitmap = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        view.draw(canvas);
        int nonBackground = countNonBackgroundPixels(bitmap);

        File folder = SamExporter.exportFolder(context);
        if (!folder.exists() && !folder.mkdirs()) {
            throw new IOException("Could not create render folder: " + folder.getAbsolutePath());
        }
        File png = new File(folder, sanitize(runId) + "_screen_" + sanitize(stage) + ".png");
        try (FileOutputStream stream = new FileOutputStream(png, false)) {
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                throw new IOException("Could not encode screen render: " + png.getAbsolutePath());
            }
        } finally {
            bitmap.recycle();
        }

        long bytes = png.length();
        boolean pass = bytes >= 5000 && nonBackground >= 1000;
        return new RenderResult(stage, png, WIDTH, HEIGHT, bytes, nonBackground, sha256(png), pass);
    }

    private static LinearLayout root(Context context) {
        LinearLayout root = new LinearLayout(context);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setLayoutParams(new ViewGroup.LayoutParams(WIDTH, HEIGHT));
        root.setPadding(dp(context, 26), dp(context, 18), dp(context, 26), dp(context, 20));
        root.setBackgroundColor(BG);
        return root;
    }

    private static TextView title(Context context, String text) {
        TextView view = new TextView(context);
        view.setText(text);
        view.setTextColor(TEXT);
        view.setTextSize(28);
        view.setGravity(Gravity.CENTER_HORIZONTAL);
        view.setTypeface(Typeface.DEFAULT_BOLD);
        view.setSingleLine(false);
        view.setPadding(0, 0, 0, dp(context, 6));
        return view;
    }

    private static TextView body(Context context, String text) {
        TextView view = new TextView(context);
        view.setText(text);
        view.setTextColor(MUTED);
        view.setTextSize(17);
        view.setGravity(Gravity.CENTER_HORIZONTAL);
        view.setSingleLine(false);
        view.setPadding(0, 0, 0, dp(context, 8));
        return view;
    }

    private static LinearLayout sliderPanel(Context context, String label, String low, String high, int value, boolean active) {
        LinearLayout panel = new LinearLayout(context);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(context, 28), dp(context, 16), dp(context, 28), dp(context, 16));

        TextView title = new TextView(context);
        title.setText(label);
        title.setTextColor(active ? ACTIVE : TEXT);
        title.setTextSize(24);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        panel.addView(title);

        LinearLayout labels = new LinearLayout(context);
        labels.setOrientation(LinearLayout.HORIZONTAL);
        labels.addView(smallLabel(context, low, Gravity.LEFT), new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        labels.addView(smallLabel(context, high, Gravity.RIGHT), new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        panel.addView(labels);

        SeekBar seekBar = new SeekBar(context);
        seekBar.setMax(100);
        seekBar.setProgress(value);
        seekBar.setPadding(dp(context, 24), dp(context, 18), dp(context, 24), dp(context, 18));
        panel.addView(seekBar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(context, 70)));

        TextView valueLabel = new TextView(context);
        valueLabel.setText(Integer.toString(value));
        valueLabel.setTextColor(TEXT);
        valueLabel.setTextSize(22);
        valueLabel.setGravity(Gravity.CENTER_HORIZONTAL);
        valueLabel.setTypeface(Typeface.DEFAULT_BOLD);
        panel.addView(valueLabel);
        return panel;
    }

    private static TextView smallLabel(Context context, String text, int gravity) {
        TextView view = new TextView(context);
        view.setText(text);
        view.setTextColor(MUTED);
        view.setTextSize(16);
        view.setGravity(gravity);
        return view;
    }

    private static LinearLayout footer(Context context) {
        LinearLayout footer = new LinearLayout(context);
        footer.setOrientation(LinearLayout.HORIZONTAL);
        footer.setGravity(Gravity.CENTER);
        footer.setPadding(0, dp(context, 10), 0, 0);
        return footer;
    }

    private static Button button(Context context, String text, boolean primary) {
        Button button = new Button(context);
        button.setText(text);
        button.setAllCaps(false);
        button.setTextSize(18);
        button.setMinHeight(dp(context, 56));
        if (primary) {
            button.setTextColor(Color.WHITE);
            button.setBackgroundColor(ACTIVE);
        }
        return button;
    }

    private static LinearLayout.LayoutParams footerButtonParams(Context context) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, dp(context, 62), 1f);
        params.setMargins(dp(context, 8), 0, dp(context, 8), 0);
        return params;
    }

    private static int countNonBackgroundPixels(Bitmap bitmap) {
        int count = 0;
        for (int y = 0; y < bitmap.getHeight(); y++) {
            for (int x = 0; x < bitmap.getWidth(); x++) {
                int pixel = bitmap.getPixel(x, y);
                if (pixel != BG && Color.alpha(pixel) != 0) {
                    count++;
                }
            }
        }
        return count;
    }

    private static String sha256(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] buffer = new byte[8192];
        try (FileInputStream stream = new FileInputStream(file)) {
            int read;
            while ((read = stream.read(buffer)) > 0) {
                digest.update(buffer, 0, read);
            }
        }
        StringBuilder builder = new StringBuilder();
        for (byte b : digest.digest()) {
            builder.append(String.format(Locale.US, "%02x", b));
        }
        return builder.toString();
    }

    private static int dp(Context context, float value) {
        return (int) (value * context.getResources().getDisplayMetrics().density + 0.5f);
    }

    private static String sanitize(String value) {
        String clean = value == null ? "sam" : value.trim();
        if (clean.isEmpty()) {
            clean = "sam";
        }
        return clean.replaceAll("[^A-Za-z0-9._-]+", "_");
    }

    static final class RenderResult {
        final String stage;
        final File pngFile;
        final int width;
        final int height;
        final long bytes;
        final int nonBackgroundPixels;
        final String sha256;
        final boolean pass;

        RenderResult(String stage, File pngFile, int width, int height, long bytes, int nonBackgroundPixels, String sha256, boolean pass) {
            this.stage = stage;
            this.pngFile = pngFile;
            this.width = width;
            this.height = height;
            this.bytes = bytes;
            this.nonBackgroundPixels = nonBackgroundPixels;
            this.sha256 = sha256;
            this.pass = pass;
        }
    }
}
