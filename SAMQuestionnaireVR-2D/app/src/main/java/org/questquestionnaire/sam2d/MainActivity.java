package org.questquestionnaire.sam2d;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.text.TextUtils;
import android.util.Log;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;
import android.widget.Toast;

public final class MainActivity extends Activity {
    private static final String TAG = "SAM2D";
    private static final int COLOR_BG = Color.rgb(248, 250, 252);
    private static final int COLOR_TEXT = Color.rgb(17, 24, 39);
    private static final int COLOR_MUTED = Color.rgb(71, 85, 105);
    private static final int COLOR_ACTIVE = Color.rgb(0, 92, 255);

    private final Handler handler = new Handler(Looper.getMainLooper());
    private SamLaunchContext launch;
    private long startedElapsedMs;
    private String currentScreen = "boot";
    private int activeSamRow = 0;
    private int activeSliderRow = 0;
    private SamScaleView valenceView;
    private SamScaleView arousalView;
    private Button samNextButton;
    private SeekBar sliderArousalBar;
    private SeekBar sliderValenceBar;
    private TextView sliderArousalValue;
    private TextView sliderValenceValue;
    private TextView sliderArousalLabel;
    private TextView sliderValenceLabel;
    private SamExporter.ExportResult lastExport;

    private int valenceScore = 0;
    private int arousalScore = 0;
    private String valenceTimestampUtc = "";
    private String arousalTimestampUtc = "";
    private long valenceTimestampUnixMs = 0L;
    private long arousalTimestampUnixMs = 0L;
    private long valenceElapsedMs = 0L;
    private long arousalElapsedMs = 0L;

    private int sliderValence = 50;
    private int sliderArousal = 50;
    private String sliderValenceTimestampUtc = "";
    private String sliderArousalTimestampUtc = "";
    private long sliderValenceTimestampUnixMs = 0L;
    private long sliderArousalTimestampUnixMs = 0L;
    private long sliderValenceElapsedMs = 0L;
    private long sliderArousalElapsedMs = 0L;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        resetFromIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        resetFromIntent(intent);
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if ("sam".equals(currentScreen) && handleSamKey(keyCode)) {
            return true;
        }
        if ("affective-slider".equals(currentScreen) && handleSliderKey(keyCode)) {
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }

    private void resetFromIntent(Intent intent) {
        launch = SamLaunchContext.fromIntent(intent);
        startedElapsedMs = SystemClock.elapsedRealtime();
        valenceScore = 0;
        arousalScore = 0;
        sliderValence = 50;
        sliderArousal = 50;
        valenceTimestampUtc = "";
        arousalTimestampUtc = "";
        valenceTimestampUnixMs = 0L;
        arousalTimestampUnixMs = 0L;
        valenceElapsedMs = 0L;
        arousalElapsedMs = 0L;
        sliderValenceTimestampUtc = "";
        sliderArousalTimestampUtc = "";
        sliderValenceTimestampUnixMs = 0L;
        sliderArousalTimestampUnixMs = 0L;
        sliderValenceElapsedMs = 0L;
        sliderArousalElapsedMs = 0L;
        lastExport = null;
        Log.i(TAG, "SAM_RUN_START runId=" + launch.runId + " autoSam=" + launch.autoSam + " capturePanel=" + launch.capturePanel);
        if (launch.autoSam && launch.capturePanel) {
            runAutoSamVisualReplay();
        } else if (launch.autoSam) {
            runAutoSam();
        } else {
            showSamScreen();
        }
    }

    private void runAutoSam() {
        try {
            lastExport = AutoSamRunner.run(this, launch, startedElapsedMs);
            showSaved("Auto validation export complete.\n\nJSON:\n" + lastExport.jsonFile.getAbsolutePath()
                + "\n\nCSV:\n" + lastExport.csvFile.getAbsolutePath());
        } catch (Exception ex) {
            Log.e(TAG, "SAM_COMMAND_REPLAY_FAIL", ex);
            showSaved("Auto validation failed:\n" + ex.getMessage());
        }
    }

    private void runAutoSamVisualReplay() {
        Log.i(TAG, "SAM_COMMAND_REPLAY_START runId=" + launch.runId + " mode=visual-ui");
        showSamScreen();
        handler.postDelayed(() -> {
            try {
                int arousal = SamLaunchContext.clampScore(launch.autoArousal);
                int valence = SamLaunchContext.clampScore(launch.autoValence);
                activeSamRow = 0;
                updateSamActiveRows();
                valenceView.setSelectedScore(valence);
                recordSamSelection("valence", valence, "command-replay");
                activeSamRow = 1;
                updateSamActiveRows();
                arousalView.setSelectedScore(arousal);
                recordSamSelection("arousal", arousal, "command-replay");
                updateSamNext();
                capturePanelNow("sam-selected");
                handler.postDelayed(this::showAutoSliderScreen, 500L);
            } catch (Exception ex) {
                Log.e(TAG, "SAM_COMMAND_REPLAY_FAIL", ex);
                showSaved("Auto visual validation failed:\n" + ex.getMessage());
            }
        }, 700L);
    }

    private void showAutoSliderScreen() {
        showSliderScreen();
        handler.postDelayed(() -> {
            try {
                int visualSliderValence = Math.round((SamLaunchContext.clampScore(launch.autoValence) - 1) * 100f / 4f);
                int visualSliderArousal = Math.round((SamLaunchContext.clampScore(launch.autoArousal) - 1) * 100f / 4f);
                activeSliderRow = 0;
                updateSliderActiveRows();
                sliderValenceBar.setProgress(visualSliderValence);
                stampSlider("valence");
                Log.i(TAG, "SAM_INPUT action=SliderAdjust dimension=valence value=" + visualSliderValence + " source=command-replay");
                activeSliderRow = 1;
                updateSliderActiveRows();
                sliderArousalBar.setProgress(visualSliderArousal);
                stampSlider("arousal");
                Log.i(TAG, "SAM_INPUT action=SliderAdjust dimension=arousal value=" + visualSliderArousal + " source=command-replay");
                capturePanelNow("affective-slider-selected");
                handler.postDelayed(() -> submit("command-replay"), 500L);
            } catch (Exception ex) {
                Log.e(TAG, "SAM_COMMAND_REPLAY_FAIL", ex);
                showSaved("Auto visual validation failed:\n" + ex.getMessage());
            }
        }, 700L);
    }

    private void showSamScreen() {
        currentScreen = "sam";
        activeSamRow = 0;
        LinearLayout root = rootLayout();
        TextView title = title("Rate the previous session");
        root.addView(title);
        TextView instruction = body("Select one figure on each row to show how you felt during the previous session.");
        root.addView(instruction);

        valenceView = new SamScaleView(this);
        valenceView.configure("valence", "Valence", "Very unpleasant", "Very pleasant", "valence");
        valenceView.setOnScoreSelectedListener((view, score, source) -> {
            activeSamRow = 0;
            updateSamActiveRows();
            recordSamSelection("valence", score, source);
        });
        root.addView(valenceView, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        arousalView = new SamScaleView(this);
        arousalView.configure("arousal", "Arousal", "Very calm", "Very excited", "arousal");
        arousalView.setOnScoreSelectedListener((view, score, source) -> {
            activeSamRow = 1;
            updateSamActiveRows();
            recordSamSelection("arousal", score, source);
        });
        root.addView(arousalView, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        LinearLayout footer = footer();
        Button reset = button("Reset");
        reset.setOnClickListener(v -> {
            valenceScore = 0;
            arousalScore = 0;
            valenceView.clearSelection();
            arousalView.clearSelection();
            updateSamNext();
            Log.i(TAG, "SAM_INPUT action=Reset screen=sam");
        });
        samNextButton = primaryButton("Next");
        samNextButton.setEnabled(false);
        samNextButton.setOnClickListener(v -> showSliderScreen());
        footer.addView(reset, footerButtonParams());
        footer.addView(samNextButton, footerButtonParams());
        root.addView(footer);

        setContentView(root);
        updateSamActiveRows();
        updateSamNext();
        Log.i(TAG, "SAM_VISUAL_STAGE stage=sam screen=sam");
        Log.i(TAG, "SAM_PANEL_READY runId=" + launch.runId);
        if (!launch.autoSam) {
            schedulePanelCapture("sam", 600L);
        }
    }

    private void showSliderScreen() {
        currentScreen = "affective-slider";
        activeSliderRow = 0;
        LinearLayout root = rootLayout();
        root.addView(title("Rate the previous session on sliders"));
        root.addView(body("Move each slider to match how you felt during the previous session, or leave it centered for neutral."));

        LinearLayout valencePanel = sliderPanel("Valence", "Very unpleasant", "Very pleasant");
        sliderValenceLabel = (TextView) valencePanel.getChildAt(0);
        sliderValenceBar = (SeekBar) valencePanel.getChildAt(2);
        sliderValenceValue = (TextView) valencePanel.getChildAt(3);
        sliderValenceBar.setProgress(sliderValence);
        sliderValenceBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                sliderValence = progress;
                sliderValenceValue.setText(Integer.toString(progress));
                if (fromUser) {
                    stampSlider("valence");
                    Log.i(TAG, "SAM_INPUT action=SliderAdjust dimension=valence value=" + progress);
                }
            }
            @Override public void onStartTrackingTouch(SeekBar seekBar) { activeSliderRow = 0; updateSliderActiveRows(); }
            @Override public void onStopTrackingTouch(SeekBar seekBar) { stampSlider("valence"); }
        });
        root.addView(valencePanel, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        LinearLayout arousalPanel = sliderPanel("Arousal", "Very calm", "Very excited");
        sliderArousalLabel = (TextView) arousalPanel.getChildAt(0);
        sliderArousalBar = (SeekBar) arousalPanel.getChildAt(2);
        sliderArousalValue = (TextView) arousalPanel.getChildAt(3);
        sliderArousalBar.setProgress(sliderArousal);
        sliderArousalBar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar seekBar, int progress, boolean fromUser) {
                sliderArousal = progress;
                sliderArousalValue.setText(Integer.toString(progress));
                if (fromUser) {
                    stampSlider("arousal");
                    Log.i(TAG, "SAM_INPUT action=SliderAdjust dimension=arousal value=" + progress);
                }
            }
            @Override public void onStartTrackingTouch(SeekBar seekBar) { activeSliderRow = 1; updateSliderActiveRows(); }
            @Override public void onStopTrackingTouch(SeekBar seekBar) { stampSlider("arousal"); }
        });
        root.addView(arousalPanel, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        LinearLayout footer = footer();
        Button back = button("Back");
        back.setOnClickListener(v -> showSamScreenWithExistingValues());
        Button submit = primaryButton("Submit");
        submit.setOnClickListener(v -> submit("manual"));
        footer.addView(back, footerButtonParams());
        footer.addView(submit, footerButtonParams());
        root.addView(footer);

        setContentView(root);
        updateSliderActiveRows();
        Log.i(TAG, "SAM_VISUAL_STAGE stage=affective-slider screen=affective-slider");
        if (!launch.autoSam) {
            schedulePanelCapture("affective-slider", 600L);
        }
    }

    private void showSamScreenWithExistingValues() {
        showSamScreen();
        if (arousalScore > 0) {
            arousalView.setSelectedScore(arousalScore);
        }
        if (valenceScore > 0) {
            valenceView.setSelectedScore(valenceScore);
        }
        updateSamNext();
    }

    private void submit(String inputPath) {
        if (valenceScore <= 0 || arousalScore <= 0) {
            Toast.makeText(this, "Select valence and arousal first.", Toast.LENGTH_SHORT).show();
            return;
        }
        if (TextUtils.isEmpty(sliderArousalTimestampUtc)) {
            stampSlider("arousal");
        }
        if (TextUtils.isEmpty(sliderValenceTimestampUtc)) {
            stampSlider("valence");
        }

        try {
            SamResponseRecord record = buildRecord(inputPath);
            lastExport = SamExporter.writeSession(this, record);
            Log.i(TAG, "SAM_EXPORT_COMPLETE csv=\"" + lastExport.csvFile.getAbsolutePath()
                + "\" json=\"" + lastExport.jsonFile.getAbsolutePath()
                + "\" runId=" + launch.runId
                + " valence=" + record.valenceScore
                + " arousal=" + record.arousalScore
                + " sliderValence=" + record.sliderValence
                + " sliderArousal=" + record.sliderArousal);
            showSaved("Saved.\n\nJSON:\n" + lastExport.jsonFile.getAbsolutePath()
                + "\n\nCSV:\n" + lastExport.csvFile.getAbsolutePath());
            if ("command-replay".equals(inputPath)) {
                Log.i(TAG, "SAM_COMMAND_REPLAY_EXPORT_MATCH runId=" + launch.runId + " mode=visual-ui");
            }
            maybeReturn(record);
        } catch (Exception ex) {
            Log.e(TAG, "SAM_EXPORT_FAILED", ex);
            Toast.makeText(this, "Export failed: " + ex.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private SamResponseRecord buildRecord(String inputPath) {
        SamResponseRecord record = SamResponseRecord.create(launch, startedElapsedMs);
        record.valenceScore = valenceScore;
        record.arousalScore = arousalScore;
        record.valenceLabel = SamResponseRecord.valenceLabel(valenceScore);
        record.arousalLabel = SamResponseRecord.arousalLabel(arousalScore);
        record.valenceResponseTimestampUtc = valenceTimestampUtc;
        record.arousalResponseTimestampUtc = arousalTimestampUtc;
        record.valenceResponseUnixMs = valenceTimestampUnixMs;
        record.arousalResponseUnixMs = arousalTimestampUnixMs;
        record.valenceResponseElapsedMs = valenceElapsedMs;
        record.arousalResponseElapsedMs = arousalElapsedMs;
        record.sliderValence = sliderValence;
        record.sliderArousal = sliderArousal;
        record.sliderValenceResponseTimestampUtc = sliderValenceTimestampUtc;
        record.sliderArousalResponseTimestampUtc = sliderArousalTimestampUtc;
        record.sliderValenceResponseUnixMs = sliderValenceTimestampUnixMs;
        record.sliderArousalResponseUnixMs = sliderArousalTimestampUnixMs;
        record.sliderValenceResponseElapsedMs = sliderValenceElapsedMs;
        record.sliderArousalResponseElapsedMs = sliderArousalElapsedMs;
        record.submittedUnixMs = TimeUtil.unixMillisNow();
        record.submittedElapsedMs = SystemClock.elapsedRealtime();
        record.inputPath = inputPath;
        return record;
    }

    private void maybeReturn(SamResponseRecord record) {
        if (launch.shouldStaySaved()) {
            return;
        }
        handler.postDelayed(() -> {
            if (launch.hasReturnPendingIntent()) {
                try {
                    launch.sendReturnPendingIntent(this, lastExport, record);
                    Log.i(TAG, "SAM_RETURN_PENDING_INTENT runId=" + launch.runId);
                    finish();
                    return;
                } catch (Exception ex) {
                    Log.e(TAG, "SAM_RETURN_PENDING_INTENT_FAILED", ex);
                }
            }
            Intent completion = launch.completionIntent(this, lastExport, record);
            if (completion != null) {
                try {
                    startActivity(completion);
                    finish();
                    return;
                } catch (Exception ex) {
                    Log.e(TAG, "SAM_COMPLETION_LAUNCH_FAILED", ex);
                }
            }
            showBlackScreen();
        }, 1000L);
    }

    private void showSaved(String message) {
        currentScreen = "saved";
        LinearLayout root = rootLayout();
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        root.addView(title("Complete"));
        TextView body = body(message);
        body.setGravity(Gravity.CENTER_HORIZONTAL);
        root.addView(body, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        Button done = primaryButton("Done");
        done.setOnClickListener(v -> showBlackScreen());
        root.addView(done, footerButtonParams());
        setContentView(root);
        Log.i(TAG, "SAM_VISUAL_STAGE stage=saved screen=saved");
        schedulePanelCapture("saved", 600L);
    }

    private void schedulePanelCapture(String stage, long delayMs) {
        if (launch == null || !launch.shouldCaptureStage(stage)) {
            return;
        }
        handler.postDelayed(() -> capturePanelNow(stage), delayMs);
    }

    private void capturePanelNow(String stage) {
        if (launch == null || !launch.shouldCaptureStage(stage)) {
            return;
        }
        try {
            SamPanelCapture.CaptureResult result = SamPanelCapture.capture(this, stage, launch.runId);
            if (result.pass) {
                Log.i(TAG, "SAM_PANEL_CAPTURE_PASS stage=" + result.stage
                    + " path=\"" + result.pngFile.getAbsolutePath()
                    + "\" width=" + result.width
                    + " height=" + result.height
                    + " bytes=" + result.bytes
                    + " nonBackgroundPixels=" + result.nonBackgroundPixels
                    + " sha256=" + result.sha256);
            } else {
                Log.e(TAG, "SAM_PANEL_CAPTURE_FAIL stage=" + result.stage
                    + " path=\"" + result.pngFile.getAbsolutePath()
                    + "\" width=" + result.width
                    + " height=" + result.height
                    + " bytes=" + result.bytes
                    + " nonBackgroundPixels=" + result.nonBackgroundPixels);
            }
        } catch (Exception ex) {
            Log.e(TAG, "SAM_PANEL_CAPTURE_FAIL stage=" + stage, ex);
        }
    }

    private void showBlackScreen() {
        currentScreen = "black";
        View black = new View(this);
        black.setBackgroundColor(Color.BLACK);
        setContentView(black);
        Log.i(TAG, "SAM_VISUAL_STAGE stage=finished-black screen=black");
    }

    private void recordSamSelection(String dimension, int score, String source) {
        String timestamp = TimeUtil.utcIsoNowMillis();
        long unix = TimeUtil.unixMillisNow();
        long elapsed = SystemClock.elapsedRealtime();
        if ("valence".equals(dimension)) {
            valenceScore = score;
            valenceTimestampUtc = timestamp;
            valenceTimestampUnixMs = unix;
            valenceElapsedMs = elapsed;
        } else {
            arousalScore = score;
            arousalTimestampUtc = timestamp;
            arousalTimestampUnixMs = unix;
            arousalElapsedMs = elapsed;
        }
        Log.i(TAG, "SAM_INPUT action=Select dimension=" + dimension + " score=" + score + " source=" + source);
        updateSamNext();
    }

    private void stampSlider(String dimension) {
        String timestamp = TimeUtil.utcIsoNowMillis();
        long unix = TimeUtil.unixMillisNow();
        long elapsed = SystemClock.elapsedRealtime();
        if ("valence".equals(dimension)) {
            sliderValenceTimestampUtc = timestamp;
            sliderValenceTimestampUnixMs = unix;
            sliderValenceElapsedMs = elapsed;
        } else {
            sliderArousalTimestampUtc = timestamp;
            sliderArousalTimestampUnixMs = unix;
            sliderArousalElapsedMs = elapsed;
        }
    }

    private boolean handleSamKey(int keyCode) {
        SamScaleView active = activeSamRow == 0 ? valenceView : arousalView;
        switch (keyCode) {
            case KeyEvent.KEYCODE_DPAD_UP:
                activeSamRow = 0;
                updateSamActiveRows();
                return true;
            case KeyEvent.KEYCODE_DPAD_DOWN:
                activeSamRow = 1;
                updateSamActiveRows();
                return true;
            case KeyEvent.KEYCODE_DPAD_LEFT:
                active.moveFocus(-1);
                return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                active.moveFocus(1);
                return true;
            case KeyEvent.KEYCODE_DPAD_CENTER:
            case KeyEvent.KEYCODE_ENTER:
            case KeyEvent.KEYCODE_BUTTON_A:
                active.confirmFocusedScore("dpad");
                return true;
            default:
                return false;
        }
    }

    private boolean handleSliderKey(int keyCode) {
        SeekBar active = activeSliderRow == 0 ? sliderValenceBar : sliderArousalBar;
        String dimension = activeSliderRow == 0 ? "valence" : "arousal";
        switch (keyCode) {
            case KeyEvent.KEYCODE_DPAD_UP:
                activeSliderRow = 0;
                updateSliderActiveRows();
                return true;
            case KeyEvent.KEYCODE_DPAD_DOWN:
                activeSliderRow = 1;
                updateSliderActiveRows();
                return true;
            case KeyEvent.KEYCODE_DPAD_LEFT:
                active.setProgress(Math.max(0, active.getProgress() - 5));
                stampSlider(dimension);
                return true;
            case KeyEvent.KEYCODE_DPAD_RIGHT:
                active.setProgress(Math.min(100, active.getProgress() + 5));
                stampSlider(dimension);
                return true;
            default:
                return false;
        }
    }

    private void updateSamActiveRows() {
        if (arousalView != null) {
            arousalView.setActiveRow(activeSamRow == 1);
        }
        if (valenceView != null) {
            valenceView.setActiveRow(activeSamRow == 0);
        }
    }

    private void updateSamNext() {
        if (samNextButton != null) {
            samNextButton.setEnabled(valenceScore > 0 && arousalScore > 0);
        }
    }

    private void updateSliderActiveRows() {
        if (sliderArousalLabel != null) {
            sliderArousalLabel.setTextColor(activeSliderRow == 1 ? COLOR_ACTIVE : COLOR_TEXT);
        }
        if (sliderValenceLabel != null) {
            sliderValenceLabel.setTextColor(activeSliderRow == 0 ? COLOR_ACTIVE : COLOR_TEXT);
        }
    }

    private LinearLayout rootLayout() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setLayoutParams(new ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT));
        root.setPadding(dp(26), dp(18), dp(26), dp(20));
        root.setBackgroundColor(COLOR_BG);
        return root;
    }

    private TextView title(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextColor(COLOR_TEXT);
        view.setTextSize(28);
        view.setGravity(Gravity.CENTER_HORIZONTAL);
        view.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        view.setSingleLine(false);
        view.setPadding(0, 0, 0, dp(6));
        return view;
    }

    private TextView body(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextColor(COLOR_MUTED);
        view.setTextSize(17);
        view.setGravity(Gravity.CENTER_HORIZONTAL);
        view.setSingleLine(false);
        view.setPadding(0, 0, 0, dp(8));
        return view;
    }

    private LinearLayout sliderPanel(String label, String low, String high) {
        LinearLayout panel = new LinearLayout(this);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(28), dp(16), dp(28), dp(16));

        TextView title = new TextView(this);
        title.setText(label);
        title.setTextColor(COLOR_TEXT);
        title.setTextSize(24);
        title.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        panel.addView(title);

        LinearLayout labels = new LinearLayout(this);
        labels.setOrientation(LinearLayout.HORIZONTAL);
        TextView left = smallLabel(low, Gravity.LEFT);
        TextView right = smallLabel(high, Gravity.RIGHT);
        labels.addView(left, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        labels.addView(right, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        panel.addView(labels);

        SeekBar seekBar = new SeekBar(this);
        seekBar.setMax(100);
        seekBar.setProgress(50);
        seekBar.setPadding(dp(24), dp(18), dp(24), dp(18));
        seekBar.setContentDescription(label + " affective slider");
        panel.addView(seekBar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(70)));

        TextView value = new TextView(this);
        value.setText("50");
        value.setTextColor(COLOR_TEXT);
        value.setTextSize(22);
        value.setGravity(Gravity.CENTER_HORIZONTAL);
        value.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        panel.addView(value);
        return panel;
    }

    private TextView smallLabel(String text, int gravity) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextColor(COLOR_MUTED);
        view.setTextSize(16);
        view.setGravity(gravity);
        return view;
    }

    private LinearLayout footer() {
        LinearLayout footer = new LinearLayout(this);
        footer.setOrientation(LinearLayout.HORIZONTAL);
        footer.setGravity(Gravity.CENTER);
        footer.setPadding(0, dp(10), 0, 0);
        return footer;
    }

    private Button button(String text) {
        Button button = new Button(this);
        button.setText(text);
        button.setAllCaps(false);
        button.setTextSize(18);
        button.setMinHeight(dp(56));
        return button;
    }

    private Button primaryButton(String text) {
        Button button = button(text);
        button.setTextColor(Color.WHITE);
        button.setBackgroundColor(COLOR_ACTIVE);
        return button;
    }

    private LinearLayout.LayoutParams footerButtonParams() {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(0, dp(62), 1f);
        params.setMargins(dp(8), 0, dp(8), 0);
        return params;
    }

    private int dp(float value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }
}
