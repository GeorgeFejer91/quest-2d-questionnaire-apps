package org.questquestionnaire.sam2d;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.view.View;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.security.MessageDigest;
import java.util.Locale;

final class SamPanelCapture {
    private static final int BACKGROUND = Color.rgb(248, 250, 252);

    private SamPanelCapture() {
    }

    static CaptureResult capture(Activity activity, String stage, String runId) throws Exception {
        View root = activity.getWindow().getDecorView().getRootView();
        int width = root.getWidth();
        int height = root.getHeight();
        if (width <= 0 || height <= 0) {
            width = Math.max(640, activity.getResources().getDisplayMetrics().widthPixels);
            height = Math.max(480, activity.getResources().getDisplayMetrics().heightPixels);
            root.measure(
                View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY));
            root.layout(0, 0, width, height);
        }

        Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bitmap);
        root.draw(canvas);

        File folder = SamExporter.exportFolder(activity);
        if (!folder.exists() && !folder.mkdirs()) {
            throw new IOException("Could not create panel capture folder: " + folder.getAbsolutePath());
        }
        File png = new File(folder, sanitize(runId) + "_screen_" + sanitize(stage) + ".png");
        try (FileOutputStream stream = new FileOutputStream(png, false)) {
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                throw new IOException("Could not encode panel capture PNG: " + png.getAbsolutePath());
            }
        } finally {
            bitmap.recycle();
        }

        long bytes = png.length();
        int nonBackground = countNonBackgroundPixels(png);
        boolean pass = width >= 640 && height >= 480 && bytes >= 5000 && nonBackground >= 1000;
        return new CaptureResult(stage, png, width, height, bytes, nonBackground, sha256(png), pass);
    }

    private static int countNonBackgroundPixels(File png) throws IOException {
        Bitmap bitmap = android.graphics.BitmapFactory.decodeFile(png.getAbsolutePath());
        if (bitmap == null) {
            return 0;
        }
        int count = 0;
        try {
            for (int y = 0; y < bitmap.getHeight(); y++) {
                for (int x = 0; x < bitmap.getWidth(); x++) {
                    int pixel = bitmap.getPixel(x, y);
                    if (pixel != BACKGROUND && Color.alpha(pixel) != 0) {
                        count++;
                    }
                }
            }
        } finally {
            bitmap.recycle();
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

    private static String sanitize(String value) {
        String clean = value == null ? "sam" : value.trim();
        if (clean.isEmpty()) {
            clean = "sam";
        }
        return clean.replaceAll("[^A-Za-z0-9._-]+", "_");
    }

    static final class CaptureResult {
        final String stage;
        final File pngFile;
        final int width;
        final int height;
        final long bytes;
        final int nonBackgroundPixels;
        final String sha256;
        final boolean pass;

        CaptureResult(String stage, File pngFile, int width, int height, long bytes, int nonBackgroundPixels, String sha256, boolean pass) {
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
