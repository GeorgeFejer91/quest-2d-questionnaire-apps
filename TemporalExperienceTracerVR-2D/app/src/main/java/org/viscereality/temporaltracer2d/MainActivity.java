package org.viscereality.temporaltracer2d;

import android.app.Activity;
import android.content.res.AssetFileDescriptor;
import android.content.Intent;
import android.media.MediaPlayer;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.TextUtils;
import android.util.Log;
import android.view.View;
import android.widget.Toast;

import java.util.List;

public final class MainActivity extends Activity {
    private static final String TAG = "TemporalTracer2D";

    private TemporalTracerConfig config;
    private TemporalTracerScreenBuilder builder;
    private TemporalTraceExporter exporter;
    private TemporalTracerLaunchContext launch;
    private final Handler handler = new Handler(Looper.getMainLooper());

    private String language = "English";
    private String participantName = "";
    private String participantId = "";
    private int traceIndex = 0;
    private int completedTraceCount = 0;
    private TemporalTraceExporter.ExportResult lastExport;
    private MediaPlayer audioPlayer;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        config = TemporalTracerConfig.load(this);
        builder = new TemporalTracerScreenBuilder(this);
        exporter = new TemporalTraceExporter(this);
        resetFromIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        resetFromIntent(intent);
    }

    @Override
    protected void onDestroy() {
        stopAudio();
        super.onDestroy();
    }

    private void resetFromIntent(Intent intent) {
        launch = TemporalTracerLaunchContext.fromIntent(intent);
        language = TextUtils.isEmpty(launch.language) ? "" : config.normalizeLanguage(launch.language);
        participantName = launch.participantName;
        participantId = launch.participantId;
        traceIndex = 0;
        completedTraceCount = 0;
        lastExport = null;
        Log.i(TAG, "TEMPORAL_TRACER_RUN_START runId=" + launch.runId + " chained=" + launch.chained);

        if (launch.autoTrace) {
            runAutoTrace();
            return;
        }

        if (TextUtils.isEmpty(language)) {
            showLanguage();
        } else {
            showParticipant();
        }
    }

    private void showLanguage() {
        Log.i(TAG, "TEMPORAL_TRACER_VISUAL_STAGE stage=language screen=language");
        setContentView(builder.languageScreen(
            config,
            v -> {
                language = "English";
                showParticipant();
            },
            v -> {
                language = "Deutsch";
                showParticipant();
            }).root);
    }

    private void runAutoTrace() {
        try {
            language = TextUtils.isEmpty(language) ? "English" : config.normalizeLanguage(language);
            participantName = TextUtils.isEmpty(launch.participantName) ? "AutoTemporalTrace" : launch.participantName;
            participantId = TextUtils.isEmpty(launch.participantId) ? launch.runId : launch.participantId;
            exporter.writeDraft(launch, config, language, participantId, participantName, 0, 0);
            lastExport = TemporalTraceAutoRunner.run(exporter, launch, config, language, participantId, participantName);
            completedTraceCount = config.items(language).size();
            showSaved("Auto trace validation saved " + completedTraceCount + " traces.\n\nLast SVG:\n" + lastExport.svgFile.getAbsolutePath());
        } catch (Exception ex) {
            Log.e(TAG, "TEMPORAL_TRACER_COMMAND_REPLAY_FAIL", ex);
            showSaved("Auto trace validation failed:\n" + ex.getMessage());
        }
    }

    private void showParticipant() {
        language = config.normalizeLanguage(language);
        Log.i(TAG, "TEMPORAL_TRACER_VISUAL_STAGE stage=participant screen=participant");
        TemporalTracerConfig.UiText ui = config.ui(language);
        final TemporalTracerScreenBuilder.ParticipantScreen[] holder = new TemporalTracerScreenBuilder.ParticipantScreen[1];
        TemporalTracerScreenBuilder.ParticipantScreen screen = builder.participantScreen(
            ui,
            launch,
            v -> {
                TemporalTracerScreenBuilder.ParticipantScreen current = holder[0];
                participantName = screenText(current.participantName.getText());
                participantId = screenText(current.participantId.getText());
                if (TextUtils.isEmpty(participantName)) {
                    current.participantName.setError(ui.participantNameHint);
                    return;
                }
                exporter.writeDraft(launch, config, language, participantId, participantName, traceIndex, completedTraceCount);
                showTrace(0);
            },
            v -> showLanguage());
        holder[0] = screen;
        setContentView(screen.root);
    }

    private void showTrace(int index) {
        List<TemporalTracerConfig.TraceItem> items = config.items(language);
        if (items.isEmpty()) {
            showSaved("No trace items configured.");
            return;
        }

        traceIndex = Math.max(0, Math.min(index, items.size() - 1));
        TemporalTracerConfig.UiText ui = config.ui(language);
        TemporalTracerConfig.TraceItem item = items.get(traceIndex);
        Log.i(TAG, "TEMPORAL_TRACER_VISUAL_STAGE stage=trace screen=trace index=" + traceIndex + " label=" + item.label);

        final TemporalTracerScreenBuilder.TraceScreen[] holder = new TemporalTracerScreenBuilder.TraceScreen[1];
        TemporalTracerScreenBuilder.TraceScreen screen = builder.traceScreen(
            ui,
            config.axis,
            language,
            item,
            traceIndex,
            items.size(),
            v -> {
                if (traceIndex <= 0) {
                    showParticipant();
                } else {
                    showTrace(traceIndex - 1);
                }
            },
            v -> {
                TemporalTracerScreenBuilder.TraceScreen current = holder[0];
                current.traceCanvas.clearTrace();
                current.saveButton.setEnabled(false);
                current.status.setText(ui.completeToSaveLabel);
            },
            v -> saveCurrentTrace(holder[0]));
        holder[0] = screen;

        screen.traceCanvas.setCompletionListener((complete, status) -> {
            screen.saveButton.setEnabled(complete);
            screen.status.setText(complete ? ui.completeLabel : status);
        });
        setContentView(screen.root);
        playDimensionAudio(item, traceIndex);
    }

    private void saveCurrentTrace(TemporalTracerScreenBuilder.TraceScreen screen) {
        if (!screen.traceCanvas.isTraceComplete()) {
            Toast.makeText(this, config.ui(language).completeToSaveLabel, Toast.LENGTH_SHORT).show();
            return;
        }
        try {
            List<TemporalTracerConfig.TraceItem> items = config.items(language);
            TemporalTracerConfig.TraceItem item = items.get(traceIndex);
            lastExport = exporter.exportTrace(
                launch,
                config,
                language,
                participantId,
                participantName,
                traceIndex,
                item,
                screen.traceCanvas.rawPoints(),
                screen.traceCanvas.resampledPoints());
            completedTraceCount++;
            traceIndex++;
            exporter.writeDraft(launch, config, language, participantId, participantName, traceIndex, completedTraceCount);

            if (traceIndex >= items.size()) {
                exporter.markDraftComplete(launch);
                showSaved("SVG:\n" + lastExport.svgFile.getAbsolutePath() + "\n\nCSV:\n" + lastExport.csvFile.getAbsolutePath() + "\n\nJSON:\n" + lastExport.jsonFile.getAbsolutePath());
            } else {
                showTrace(traceIndex);
            }
        } catch (Exception ex) {
            Log.e(TAG, "TEMPORAL_TRACER_EXPORT_FAILED", ex);
            Toast.makeText(this, "Save failed: " + ex.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void showSaved(String body) {
        TemporalTracerConfig.UiText ui = config.ui(language);
        Log.i(TAG, "TEMPORAL_TRACER_VISUAL_STAGE stage=saved screen=saved");
        View root = builder.savedScreen(ui, body, v -> finishOrBlack()).root;
        setContentView(root);

        if (!launch.shouldStaySaved() && (launch.shouldResumeCaller() || launch.shouldOpenNext())) {
            handler.postDelayed(this::finishOrBlack, launch.autoCloseDelayMs);
        }
    }

    private void finishOrBlack() {
        stopAudio();
        if (launch.shouldResumeCaller() || launch.shouldOpenNext()) {
            if (launch.hasReturnPendingIntent()) {
                try {
                    launch.sendReturnPendingIntent(this, lastExport, config);
                    Log.i(TAG, "TEMPORAL_TRACER_RETURN_PENDING_INTENT runId=" + launch.runId
                        + " triggerId=" + launch.triggerId
                        + " finishBehavior=" + launch.finishBehavior);
                    finish();
                    return;
                } catch (Exception ex) {
                    Log.e(TAG, "TEMPORAL_TRACER_RETURN_PENDING_INTENT_FAILED", ex);
                }
            }

            Intent completion = launch.completionIntent(this, lastExport, config);
            if (completion != null) {
                try {
                    startActivity(completion);
                } catch (Exception ex) {
                    Log.e(TAG, "TEMPORAL_TRACER_COMPLETION_LAUNCH_FAILED", ex);
                }
            }
            finish();
            return;
        }

        Log.i(TAG, "TEMPORAL_TRACER_VISUAL_STAGE stage=finished-black screen=black");
        setContentView(builder.blackScreen());
    }

    private static String screenText(CharSequence value) {
        return value == null ? "" : value.toString().trim();
    }

    private void playDimensionAudio(TemporalTracerConfig.TraceItem item, int index) {
        stopAudio();
        String assetPath = item.resolvedAudioFile(config.normalizeLanguage(language), index);
        if (tryPlayAudio(assetPath, index)) {
            return;
        }

        if (!"English".equals(config.normalizeLanguage(language))) {
            List<TemporalTracerConfig.TraceItem> englishItems = config.items("English");
            if (index >= 0 && index < englishItems.size()) {
                String fallbackPath = englishItems.get(index).resolvedAudioFile("English", index);
                if (tryPlayAudio(fallbackPath, index)) {
                    Log.i(TAG, "TEMPORAL_TRACER_AUDIO_FALLBACK index=" + index + " language=" + language + " asset=" + fallbackPath);
                }
            }
        }
    }

    private boolean tryPlayAudio(String assetPath, int index) {
        try {
            AssetFileDescriptor fd = getAssets().openFd(assetPath);
            audioPlayer = new MediaPlayer();
            audioPlayer.setDataSource(fd.getFileDescriptor(), fd.getStartOffset(), fd.getLength());
            fd.close();
            audioPlayer.setOnCompletionListener(mp -> stopAudio());
            audioPlayer.prepare();
            audioPlayer.start();
            Log.i(TAG, "TEMPORAL_TRACER_AUDIO_START index=" + index + " asset=" + assetPath);
            return true;
        } catch (Exception ex) {
            Log.w(TAG, "TEMPORAL_TRACER_AUDIO_MISSING_OR_FAILED index=" + index + " asset=" + assetPath + " error=" + ex.getMessage());
            stopAudio();
            return false;
        }
    }

    private void stopAudio() {
        if (audioPlayer == null) {
            return;
        }
        try {
            if (audioPlayer.isPlaying()) {
                audioPlayer.stop();
            }
        } catch (Exception ignored) {
        }
        try {
            audioPlayer.release();
        } catch (Exception ignored) {
        }
        audioPlayer = null;
    }
}
