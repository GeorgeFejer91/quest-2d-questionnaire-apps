package org.questquestionnaire.questionnaires2d;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.Drawable;
import android.text.Layout;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.CompoundButton;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.RadioButton;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public final class RenderQuestionnaireVisualsTest {
    @Test
    public void renderQuestionnaireStagesWhenEnabled() throws Exception {
        if (!Boolean.parseBoolean(System.getProperty("questionnaire.render.enabled", "false"))) {
            return;
        }

        Context context = RuntimeEnvironment.getApplication();
        QuestionnaireData.RuntimeConfig config = QuestionnaireLoader.loadRuntimeConfig(context);
        QuestionnaireData.RuntimeBlock maiaBlock = config.findBlock("maia2");
        List<String> maia = maiaBlock != null ? QuestionnaireLoader.loadMaia2Questions(context) : java.util.Collections.emptyList();
        QuestionnaireData.RuntimeBlock pictographicBlock = config.findBlock("pictographic");
        List<QuestionnaireData.RuntimePictographicPrompt> prompts = pictographicBlock != null ? pictographicBlock.prompts : java.util.Collections.emptyList();
        QuestionnaireData.RuntimeBlock sliderBlock = config.findBlock("custom_slider");
        QuestionnaireScreenBuilder builder = new QuestionnaireScreenBuilder(context);

        String runId = System.getProperty("questionnaire.render.runId", "");
        if (runId.trim().isEmpty()) {
            runId = "render-" + TimeUtil.utcFileStamp();
        }

        String outputDir = System.getProperty("questionnaire.render.outputDir", "");
        File output = outputDir.trim().isEmpty()
            ? new File("artifacts/questionnaire-render-validation/" + runId)
            : new File(outputDir);
        if (!output.exists() && !output.mkdirs()) {
            throw new IllegalStateException("Could not create render output directory: " + output);
        }

        JSONArray renders = new JSONArray();
        for (Dimension dimension : parseDimensions(System.getProperty("questionnaire.render.sizes", "1280x800,900x800"))) {
            renders.put(renderOne(output, dimension, "language", "language", "neutral", builder.languageScreen().root));
            renders.put(renderOne(output, dimension, "finished-black", "black", "neutral", builder.blackScreen().root));
            renders.put(renderOne(output, dimension, "manual-hardware-gate", "manual-hardware-gate", "neutral", builder.manualHardwareGateScreen().root));

            for (String language : new String[] {"English", "Deutsch"}) {
                QuestionnaireData.LocalizedUiText uiText = QuestionnaireLoader.loadUiText(context, language);
                List<String> slider = QuestionnaireLoader.loadQuestions(context, language);
                QuestionnaireScreenBuilder.DemographicsFixture demographics = new QuestionnaireScreenBuilder.DemographicsFixture();
                demographics.name = "George";
                demographics.age = 33;
                demographics.gender = uiText.genderFemale;
                demographics.consent = true;
                demographics.submitEnabled = true;

                renders.put(renderOne(output, dimension, "demographics", "demographics", language, builder.demographicsScreen(uiText, demographics).root));
                if (!maia.isEmpty()) {
                    renders.put(renderOne(output, dimension, "maia2-first", "maia", language, builder.maiaScreen(maia.get(0), 0, maia.size(), 4, true).root));
                }
                if (!prompts.isEmpty()) {
                    renders.put(renderOne(
                        output,
                        dimension,
                        "pictographic",
                        "pictographic",
                        language,
                        builder.pictographicScreen(
                            prompts.get(0),
                            language,
                            QuestionnaireLoader.loadPictographicBitmap(context, prompts.get(0).imageFileName),
                            0,
                            prompts.size(),
                            prompts.get(0).choices.get(0),
                            true).root));
                }
                renders.put(renderOne(output, dimension, "slider-first", "slider", language, builder.sliderScreen(
                    uiText,
                    slider.get(0),
                    0,
                    slider.size(),
                    75,
                    true,
                    sliderBlock != null && sliderBlock.anchors != null ? sliderBlock.anchors.left : null,
                    sliderBlock != null && sliderBlock.anchors != null ? sliderBlock.anchors.right : null).root));
                renders.put(renderOne(output, dimension, "saved-confirmation", "saved", language, builder.savedScreen(
                    uiText.thankYou,
                    "Questionnaire data saved locally on the headset.\n\nCSV:\n/device/QuestionnaireExports/fixture.csv\n\nJSON:\n/device/QuestionnaireExports/fixture.json").root));
            }
        }

        JSONObject summary = new JSONObject();
        summary.put("schemaVersion", "my-questionnaire-2d.render-validation.v1");
        summary.put("runId", runId);
        summary.put("outputDir", output.getAbsolutePath());
        summary.put("renderer", "robolectric-android-view-draw");
        summary.put("configId", config.questionnaireId);
        summary.put("configVersion", config.questionnaireVersion);
        summary.put("appVersion", config.appVersion);
        summary.put("languages", new JSONArray().put("English").put("Deutsch"));
        summary.put("expectedCounts", new JSONObject()
            .put("maia2", maia.size())
            .put("pictographic", prompts.size())
            .put("custom_slider", QuestionnaireLoader.loadQuestions(context, "English").size()));
        summary.put("renders", renders);

        File summaryFile = new File(output, "render-summary.json");
        try (FileOutputStream stream = new FileOutputStream(summaryFile)) {
            stream.write(summary.toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }
    }

    private JSONObject renderOne(File output, Dimension dimension, String stage, String screenId, String language, View root) throws Exception {
        root.measure(
            View.MeasureSpec.makeMeasureSpec(dimension.width, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(dimension.height, View.MeasureSpec.EXACTLY));
        root.layout(0, 0, dimension.width, dimension.height);

        String name = dimension.label() + "_" + sanitize(language) + "_" + sanitize(stage) + ".png";
        File png = new File(output, name);
        Bitmap image = paintToImage(root, dimension);
        try (FileOutputStream stream = new FileOutputStream(png)) {
            image.compress(Bitmap.CompressFormat.PNG, 100, stream);
        }

        File layout = new File(output, name.replace(".png", ".layout.json"));
        try (FileOutputStream stream = new FileOutputStream(layout)) {
            stream.write(describeViewTree(root, root).toString(2).getBytes(java.nio.charset.StandardCharsets.UTF_8));
        }

        CheckResult checks = check(stage, root, image, dimension);
        JSONObject result = new JSONObject();
        result.put("stageName", stage);
        result.put("expectedScreenId", screenId);
        result.put("language", language);
        result.put("widthDp", dimension.width);
        result.put("heightDp", dimension.height);
        result.put("png", png.getAbsolutePath());
        result.put("layout", layout.getAbsolutePath());
        result.put("byteLength", png.length());
        result.put("sha256", sha256(png));
        result.put("status", checks.status());
        result.put("pass", checks.passes);
        result.put("warn", checks.warnings);
        result.put("fail", checks.failures);
        return result;
    }

    private JSONObject describeViewTree(View root, View view) throws Exception {
        JSONObject node = new JSONObject();
        Rect bounds = boundsInRoot(root, view);
        Rect visibleBounds = visibleBoundsInRoot(root, view);
        node.put("className", view.getClass().getSimpleName());
        node.put("contentDescription", view.getContentDescription() == null ? JSONObject.NULL : view.getContentDescription().toString());
        node.put("enabled", view.isEnabled());
        node.put("visible", view.getVisibility() == View.VISIBLE);
        node.put("bounds", rectJson(bounds));
        node.put("visibleBounds", rectJson(visibleBounds));

        Drawable background = view.getBackground();
        if (background instanceof ColorDrawable) {
            node.put("backgroundColor", colorHex(((ColorDrawable) background).getColor()));
        }

        if (view instanceof TextView) {
            TextView textView = (TextView) view;
            String text = textView.getText() == null ? "" : textView.getText().toString();
            if (view instanceof EditText && text.isEmpty() && textView.getHint() != null) {
                node.put("hint", textView.getHint().toString());
            }
            node.put("text", text);
            node.put("textColor", colorHex(textView.getCurrentTextColor()));
            node.put("textSize", textView.getTextSize());
            node.put("gravity", textView.getGravity());
            node.put("paddingLeft", textView.getPaddingLeft());
            node.put("paddingTop", textView.getPaddingTop());
            node.put("paddingRight", textView.getPaddingRight());
            node.put("paddingBottom", textView.getPaddingBottom());
        }

        if (view instanceof CompoundButton) {
            node.put("checked", ((CompoundButton) view).isChecked());
        }

        if (view instanceof SeekBar) {
            SeekBar seekBar = (SeekBar) view;
            node.put("progress", seekBar.getProgress());
            node.put("max", seekBar.getMax());
        }

        if (view instanceof ImageView) {
            Object tag = view.getTag();
            if (tag != null) {
                node.put("asset", tag.toString());
            }
            Drawable drawable = ((ImageView) view).getDrawable();
            if (drawable instanceof BitmapDrawable) {
                Bitmap bitmap = ((BitmapDrawable) drawable).getBitmap();
                node.put("bitmapWidth", bitmap.getWidth());
                node.put("bitmapHeight", bitmap.getHeight());
            }
            node.put("paddingLeft", view.getPaddingLeft());
            node.put("paddingTop", view.getPaddingTop());
            node.put("paddingRight", view.getPaddingRight());
            node.put("paddingBottom", view.getPaddingBottom());
        }

        if (view instanceof ViewGroup) {
            JSONArray children = new JSONArray();
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                children.put(describeViewTree(root, group.getChildAt(i)));
            }
            node.put("children", children);
        }

        return node;
    }

    private static JSONObject rectJson(Rect rect) throws Exception {
        return new JSONObject()
            .put("left", rect.left)
            .put("top", rect.top)
            .put("right", rect.right)
            .put("bottom", rect.bottom)
            .put("width", rect.width())
            .put("height", rect.height());
    }

    private static String colorHex(int color) {
        return String.format(Locale.US, "#%02X%02X%02X", Color.red(color), Color.green(color), Color.blue(color));
    }

    private Bitmap paintToImage(View root, Dimension dimension) {
        Bitmap image = Bitmap.createBitmap(dimension.width, dimension.height, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(image);
        paintView(canvas, root, root);
        return image;
    }

    private void paintView(Canvas canvas, View root, View view) {
        if (view.getVisibility() != View.VISIBLE) {
            return;
        }

        Rect bounds = boundsInRoot(root, view);
        paintBackground(canvas, view, bounds);

        if (view instanceof RadioButton) {
            paintRadio(canvas, (RadioButton) view, bounds);
        } else if (view instanceof CheckBox) {
            paintCheckBox(canvas, (CheckBox) view, bounds);
        } else if (view instanceof Button) {
            paintButton(canvas, (Button) view, bounds);
        } else if (view instanceof EditText) {
            paintEditText(canvas, (EditText) view, bounds);
        } else if (view instanceof SeekBar) {
            paintSeekBar(canvas, (SeekBar) view, bounds);
        } else if (view instanceof ImageView) {
            paintImageView(canvas, (ImageView) view, bounds);
        } else if (view instanceof TextView) {
            paintTextView(canvas, (TextView) view, bounds);
        }

        if (view instanceof ViewGroup) {
            int saveCount = canvas.save();
            if (view instanceof ScrollView) {
                canvas.clipRect(bounds);
            }
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                paintView(canvas, root, group.getChildAt(i));
            }
            canvas.restoreToCount(saveCount);
        }
    }

    private void paintBackground(Canvas canvas, View view, Rect bounds) {
        Drawable background = view.getBackground();
        if (background instanceof ColorDrawable) {
            Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
            paint.setColor(withAlpha(((ColorDrawable) background).getColor(), view.isEnabled() ? 255 : 150));
            canvas.drawRect(bounds, paint);
        }
    }

    private void paintTextView(Canvas canvas, TextView textView, Rect bounds) {
        String text = textView.getText() == null ? "" : textView.getText().toString();
        if (text.trim().isEmpty()) {
            return;
        }

        Paint paint = textPaint(textView, Typeface.NORMAL, textView.isEnabled() ? 255 : 155);
        int left = bounds.left + textView.getPaddingLeft();
        int top = bounds.top + textView.getPaddingTop();
        int width = Math.max(1, bounds.width() - textView.getPaddingLeft() - textView.getPaddingRight());
        drawWrappedText(canvas, paint, text, left, top, width, textView.getGravity());
    }

    private void paintEditText(Canvas canvas, EditText editText, Rect bounds) {
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setColor(Color.WHITE);
        canvas.drawRect(bounds, paint);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(1f);
        paint.setColor(Color.rgb(150, 158, 172));
        canvas.drawRect(bounds, paint);

        String text = editText.getText() == null ? "" : editText.getText().toString();
        boolean showingHint = text.isEmpty();
        if (showingHint && editText.getHint() != null) {
            text = editText.getHint().toString();
        }
        if (text.isEmpty()) {
            return;
        }

        Paint textPaint = textPaint(editText, Typeface.NORMAL, 255);
        textPaint.setColor(showingHint ? Color.rgb(90, 96, 108) : editText.getCurrentTextColor());
        Paint.FontMetrics metrics = textPaint.getFontMetrics();
        float baseline = bounds.top + (bounds.height() - (metrics.descent - metrics.ascent)) / 2f - metrics.ascent;
        canvas.drawText(text, bounds.left + editText.getPaddingLeft(), baseline, textPaint);
    }

    private void paintButton(Canvas canvas, Button button, Rect bounds) {
        if (!button.isEnabled()) {
            Paint fill = new Paint(Paint.ANTI_ALIAS_FLAG);
            fill.setColor(Color.rgb(82, 88, 102));
            canvas.drawRect(bounds, fill);
        }

        String text = button.getText() == null ? "" : button.getText().toString();
        Paint paint = textPaint(button, Typeface.BOLD, button.isEnabled() ? 255 : 145);
        float x = bounds.left + Math.max(0, (bounds.width() - paint.measureText(text)) / 2f);
        Paint.FontMetrics metrics = paint.getFontMetrics();
        float baseline = bounds.top + (bounds.height() - (metrics.descent - metrics.ascent)) / 2f - metrics.ascent;
        canvas.drawText(text, x, baseline, paint);
    }

    private void paintRadio(Canvas canvas, RadioButton button, Rect bounds) {
        int size = Math.min(24, Math.max(18, bounds.height() / 2));
        int x = bounds.left + button.getPaddingLeft() + 8;
        int y = bounds.top + (bounds.height() - size) / 2;
        Paint paint = strokePaint(QuestionnaireScreenBuilder.TEXT, button.isEnabled() ? 255 : 140, 2f);
        canvas.drawOval(new RectF(x, y, x + size, y + size), paint);
        if (button.isChecked()) {
            paint.setStyle(Paint.Style.FILL);
            paint.setColor(QuestionnaireScreenBuilder.ACCENT);
            canvas.drawOval(new RectF(x + 5, y + 5, x + size - 5, y + size - 5), paint);
        }
        paintCompoundText(canvas, button, bounds, x + size + 14);
    }

    private void paintCheckBox(Canvas canvas, CheckBox button, Rect bounds) {
        int size = Math.min(24, Math.max(18, bounds.height() / 2));
        int x = bounds.left + button.getPaddingLeft() + 8;
        int y = bounds.top + (bounds.height() - size) / 2;
        Paint paint = strokePaint(QuestionnaireScreenBuilder.TEXT, button.isEnabled() ? 255 : 140, 2f);
        canvas.drawRect(x, y, x + size, y + size, paint);
        if (button.isChecked()) {
            paint.setColor(QuestionnaireScreenBuilder.ACCENT);
            canvas.drawLine(x + 5, y + size / 2f, x + size / 2f, y + size - 5, paint);
            canvas.drawLine(x + size / 2f, y + size - 5, x + size - 4, y + 5, paint);
        }
        paintCompoundText(canvas, button, bounds, x + size + 14);
    }

    private void paintCompoundText(Canvas canvas, TextView textView, Rect bounds, int textLeft) {
        String text = textView.getText() == null ? "" : textView.getText().toString();
        Paint paint = textPaint(textView, Typeface.NORMAL, textView.isEnabled() ? 255 : 155);
        int width = Math.max(1, bounds.right - textLeft - textView.getPaddingRight());
        int top = bounds.top + textView.getPaddingTop();
        drawWrappedText(canvas, paint, text, textLeft, top, width, Gravity.LEFT);
    }

    private void paintSeekBar(Canvas canvas, SeekBar seekBar, Rect bounds) {
        int trackLeft = bounds.left + 18;
        int trackRight = bounds.right - 18;
        int trackY = bounds.top + bounds.height() / 2;
        Paint paint = strokePaint(Color.rgb(96, 106, 124), 255, 6f);
        canvas.drawLine(trackLeft, trackY, trackRight, trackY, paint);

        float fraction = seekBar.getMax() == 0 ? 0f : (float) seekBar.getProgress() / (float) seekBar.getMax();
        int knobX = Math.round(trackLeft + (trackRight - trackLeft) * fraction);
        paint.setColor(QuestionnaireScreenBuilder.ACCENT);
        canvas.drawLine(trackLeft, trackY, knobX, trackY, paint);
        paint.setStyle(Paint.Style.FILL);
        canvas.drawOval(new RectF(knobX - 14, trackY - 14, knobX + 14, trackY + 14), paint);
    }

    private void paintImageView(Canvas canvas, ImageView imageView, Rect bounds) {
        Drawable drawable = imageView.getDrawable();
        if (!(drawable instanceof BitmapDrawable)) {
            return;
        }

        Bitmap bitmap = ((BitmapDrawable) drawable).getBitmap();
        int padLeft = imageView.getPaddingLeft();
        int padRight = imageView.getPaddingRight();
        int padTop = imageView.getPaddingTop();
        int padBottom = imageView.getPaddingBottom();
        int availableWidth = Math.max(1, bounds.width() - padLeft - padRight);
        int availableHeight = Math.max(1, bounds.height() - padTop - padBottom);
        double scale = Math.min((double) availableWidth / bitmap.getWidth(), (double) availableHeight / bitmap.getHeight());
        int drawWidth = Math.max(1, (int) Math.round(bitmap.getWidth() * scale));
        int drawHeight = Math.max(1, (int) Math.round(bitmap.getHeight() * scale));
        int x = bounds.left + padLeft + (availableWidth - drawWidth) / 2;
        int y = bounds.top + padTop + (availableHeight - drawHeight) / 2;
        canvas.drawBitmap(bitmap, null, new Rect(x, y, x + drawWidth, y + drawHeight), null);
    }

    private static Paint textPaint(TextView textView, int typefaceStyle, int alpha) {
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.SUBPIXEL_TEXT_FLAG);
        paint.setTypeface(Typeface.create(Typeface.DEFAULT, typefaceStyle));
        paint.setTextSize(Math.max(10f, textView.getTextSize()));
        paint.setColor(withAlpha(textView.getCurrentTextColor(), alpha));
        return paint;
    }

    private static Paint strokePaint(int color, int alpha, float strokeWidth) {
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setStyle(Paint.Style.STROKE);
        paint.setStrokeWidth(strokeWidth);
        paint.setColor(withAlpha(color, alpha));
        return paint;
    }

    private static void drawWrappedText(Canvas canvas, Paint paint, String text, int left, int top, int width, int gravity) {
        Paint.FontMetrics metrics = paint.getFontMetrics();
        float lineHeight = Math.max(1f, metrics.descent - metrics.ascent + 4f);
        float baseline = top - metrics.ascent;
        for (String paragraph : text.split("\\n", -1)) {
            if (paragraph.trim().isEmpty()) {
                baseline += lineHeight;
                continue;
            }

            String[] words = paragraph.split("\\s+");
            StringBuilder line = new StringBuilder();
            for (String word : words) {
                String candidate = line.length() == 0 ? word : line + " " + word;
                if (paint.measureText(candidate) <= width || line.length() == 0) {
                    line.setLength(0);
                    line.append(candidate);
                } else {
                    drawAlignedLine(canvas, paint, line.toString(), left, baseline, width, gravity);
                    line.setLength(0);
                    line.append(word);
                    baseline += lineHeight;
                }
            }
            if (line.length() > 0) {
                drawAlignedLine(canvas, paint, line.toString(), left, baseline, width, gravity);
                baseline += lineHeight;
            }
        }
    }

    private static void drawAlignedLine(Canvas canvas, Paint paint, String line, int left, float baseline, int width, int gravity) {
        int horizontalGravity = gravity & Gravity.HORIZONTAL_GRAVITY_MASK;
        float x = left;
        if (horizontalGravity == Gravity.RIGHT) {
            x = left + Math.max(0f, width - paint.measureText(line));
        } else if (horizontalGravity == Gravity.CENTER_HORIZONTAL) {
            x = left + Math.max(0f, (width - paint.measureText(line)) / 2f);
        }
        canvas.drawText(line, x, baseline, paint);
    }

    private static int withAlpha(int color, int alpha) {
        return Color.argb(alpha, Color.red(color), Color.green(color), Color.blue(color));
    }

    private CheckResult check(String stage, View root, Bitmap bitmap, Dimension dimension) {
        CheckResult result = new CheckResult();
        List<ViewRect> interactive = new ArrayList<>();
        collectChecks(stage, root, root, interactive, result);
        checkInteractiveOverlap(interactive, result);
        checkScrollReachability(root, result);

        if ("pictographic".equals(stage)) {
            if (findFirst(root, ImageView.class) == null) {
                result.failures.put("pictographic image missing");
            } else {
                ImageView image = findFirst(root, ImageView.class);
                if (image.getDrawable() == null || image.getWidth() < 100 || image.getHeight() < 100) {
                    result.failures.put("pictographic image not visible");
                } else {
                    result.passes.put("pictographic image visible");
                }
            }
        }

        if ("finished-black".equals(stage)) {
            if (isBlack(bitmap)) {
                result.passes.put("final black state is black");
            } else {
                result.failures.put("final black state is not uniformly black");
            }
        } else if (looksBlank(bitmap)) {
            result.failures.put("render appears blank or near-blank");
        } else {
            result.passes.put("render is nonblank");
        }

        if (dimension.width < 1000) {
            result.passes.put("narrow fallback dimension rendered");
        }
        return result;
    }

    private void collectChecks(String stage, View root, View view, List<ViewRect> interactive, CheckResult result) {
        if (view.getVisibility() != View.VISIBLE) {
            return;
        }

        Rect bounds = boundsInRoot(root, view);
        Rect visibleBounds = visibleBoundsInRoot(root, view);
        if (bounds.left < 0 || bounds.top < 0 || bounds.right > root.getWidth() || bounds.bottom > root.getHeight()) {
            result.warnings.put("view clipped: " + describe(view) + " bounds=" + bounds.toShortString());
        }

        if (isInteractive(view)) {
            if (view.getWidth() < 48 || view.getHeight() < 48) {
                result.failures.put("touch target below 48dp: " + describe(view) + " size=" + view.getWidth() + "x" + view.getHeight());
            } else {
                result.passes.put("touch target ok: " + describe(view));
            }
            interactive.add(new ViewRect(view, visibleBounds));
        }

        if (view instanceof TextView) {
            checkTextFit((TextView) view, result);
        }

        if (("demographics".equals(stage) || "maia2-first".equals(stage) || "pictographic".equals(stage)) &&
            view instanceof CompoundButton && ((CompoundButton) view).isChecked()) {
            result.passes.put("selected state visible: " + describe(view));
        }

        if (view instanceof Button) {
            Button button = (Button) view;
            if (!button.isEnabled()) {
                result.passes.put("disabled button state visible: " + describe(button));
            } else {
                result.passes.put("enabled button state visible: " + describe(button));
            }
        }

        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                collectChecks(stage, root, group.getChildAt(i), interactive, result);
            }
        }
    }

    private void checkTextFit(TextView textView, CheckResult result) {
        CharSequence text = textView.getText();
        if (text == null || text.toString().trim().isEmpty()) {
            return;
        }

        Layout layout = textView.getLayout();
        if (layout == null) {
            result.warnings.put("text layout unavailable: " + describe(textView));
            return;
        }

        int availableWidth = textView.getWidth() - textView.getPaddingLeft() - textView.getPaddingRight();
        for (int line = 0; line < layout.getLineCount(); line++) {
            if (layout.getLineWidth(line) > availableWidth + 1f) {
                result.warnings.put("text line exceeds width: " + describe(textView));
                return;
            }
        }

        int availableHeight = textView.getHeight() - textView.getPaddingTop() - textView.getPaddingBottom();
        if (layout.getHeight() > availableHeight + 2) {
            result.warnings.put("text may be vertically clipped: " + describe(textView));
        } else {
            result.passes.put("text fits: " + describe(textView));
        }
    }

    private void checkInteractiveOverlap(List<ViewRect> interactive, CheckResult result) {
        for (int i = 0; i < interactive.size(); i++) {
            for (int j = i + 1; j < interactive.size(); j++) {
                ViewRect first = interactive.get(i);
                ViewRect second = interactive.get(j);
                if (first.bounds.isEmpty() || second.bounds.isEmpty()) {
                    continue;
                }
                if (isAncestor(first.view, second.view) || isAncestor(second.view, first.view)) {
                    continue;
                }

                Rect intersection = new Rect();
                if (intersection.setIntersect(first.bounds, second.bounds) && intersection.width() * intersection.height() > 16) {
                    result.failures.put("interactive overlap: " + describe(first.view) + " / " + describe(second.view));
                }
            }
        }
        result.passes.put("interactive overlap scan complete");
    }

    private void checkScrollReachability(View root, CheckResult result) {
        ScrollView scroll = findFirst(root, ScrollView.class);
        if (scroll == null || scroll.getChildCount() == 0) {
            return;
        }

        View child = scroll.getChildAt(0);
        if (child.getHeight() > scroll.getHeight()) {
            result.passes.put("scroll overflow reachable: content=" + child.getHeight() + " viewport=" + scroll.getHeight());
        } else {
            result.passes.put("content fits viewport without scrolling");
        }
    }

    private static Rect boundsInRoot(View root, View view) {
        int left = 0;
        int top = 0;
        View current = view;
        while (current != null) {
            left += current.getLeft() - current.getScrollX();
            top += current.getTop() - current.getScrollY();
            if (current == root || !(current.getParent() instanceof View)) {
                break;
            }
            current = (View) current.getParent();
        }
        return new Rect(left, top, left + view.getWidth(), top + view.getHeight());
    }

    private static Rect visibleBoundsInRoot(View root, View view) {
        Rect visible = boundsInRoot(root, view);
        Object parent = view.getParent();
        while (parent instanceof View) {
            View parentView = (View) parent;
            Rect parentBounds = boundsInRoot(root, parentView);
            Rect intersection = new Rect();
            if (!intersection.setIntersect(visible, parentBounds)) {
                return new Rect();
            }
            visible = intersection;
            if (parentView == root) {
                break;
            }
            parent = parentView.getParent();
        }
        return visible;
    }

    private static boolean isInteractive(View view) {
        return view instanceof Button ||
            view instanceof CompoundButton ||
            view instanceof EditText ||
            view instanceof SeekBar;
    }

    private static boolean isAncestor(View possibleAncestor, View view) {
        Object parent = view.getParent();
        while (parent instanceof View) {
            if (parent == possibleAncestor) {
                return true;
            }
            parent = ((View) parent).getParent();
        }
        return false;
    }

    private static boolean looksBlank(Bitmap bitmap) {
        int first = bitmap.getPixel(0, 0);
        int different = 0;
        for (int y = 0; y < bitmap.getHeight(); y += Math.max(1, bitmap.getHeight() / 16)) {
            for (int x = 0; x < bitmap.getWidth(); x += Math.max(1, bitmap.getWidth() / 16)) {
                if (bitmap.getPixel(x, y) != first) {
                    different++;
                }
            }
        }
        return different < 4;
    }

    private static boolean isBlack(Bitmap bitmap) {
        int[] xs = {0, bitmap.getWidth() / 2, bitmap.getWidth() - 1};
        int[] ys = {0, bitmap.getHeight() / 2, bitmap.getHeight() - 1};
        for (int y : ys) {
            for (int x : xs) {
                int color = bitmap.getPixel(x, y);
                if (Color.red(color) > 5 || Color.green(color) > 5 || Color.blue(color) > 5) {
                    return false;
                }
            }
        }
        return true;
    }

    private static <T extends View> T findFirst(View view, Class<T> type) {
        if (type.isInstance(view)) {
            return type.cast(view);
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                T found = findFirst(group.getChildAt(i), type);
                if (found != null) {
                    return found;
                }
            }
        }
        return null;
    }

    private static String describe(View view) {
        CharSequence description = view.getContentDescription();
        if (description != null && description.length() > 0) {
            return description.toString();
        }
        if (view instanceof TextView) {
            String text = ((TextView) view).getText().toString();
            return text.length() > 32 ? text.substring(0, 32) : text;
        }
        return view.getClass().getSimpleName();
    }

    private static List<Dimension> parseDimensions(String text) {
        List<Dimension> dimensions = new ArrayList<>();
        for (String part : text.split(",")) {
            String[] pieces = part.trim().toLowerCase(Locale.US).split("x");
            if (pieces.length != 2) {
                continue;
            }
            try {
                int width = Integer.parseInt(pieces[0].trim());
                int height = Integer.parseInt(pieces[1].trim());
                if (width > 0 && height > 0) {
                    dimensions.add(new Dimension(width, height));
                }
            } catch (NumberFormatException ignored) {
            }
        }
        if (dimensions.isEmpty()) {
            dimensions.add(new Dimension(1280, 800));
            dimensions.add(new Dimension(900, 800));
        }
        return dimensions;
    }

    private static String sanitize(String value) {
        return value.replaceAll("[^A-Za-z0-9_-]", "_");
    }

    private static String sha256(File file) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] hash = digest.digest(Files.readAllBytes(file.toPath()));
        StringBuilder builder = new StringBuilder();
        for (byte b : hash) {
            builder.append(String.format(Locale.US, "%02x", b));
        }
        return builder.toString();
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

    private static final class ViewRect {
        final View view;
        final Rect bounds;

        ViewRect(View view, Rect bounds) {
            this.view = view;
            this.bounds = bounds;
        }
    }

    private static final class CheckResult {
        final JSONArray passes = new JSONArray();
        final JSONArray warnings = new JSONArray();
        final JSONArray failures = new JSONArray();

        String status() {
            if (failures.length() > 0) {
                return "fail";
            }
            if (warnings.length() > 0) {
                return "warn";
            }
            return "pass";
        }
    }
}
