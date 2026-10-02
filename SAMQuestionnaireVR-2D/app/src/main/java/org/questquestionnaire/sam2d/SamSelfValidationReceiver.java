package org.questquestionnaire.sam2d;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.SystemClock;
import android.util.Log;

public final class SamSelfValidationReceiver extends BroadcastReceiver {
    static final String ACTION_SELF_VALIDATE = "org.questquestionnaire.sam2d.SELF_VALIDATE";
    private static final String TAG = "SAM2D";

    @Override
    public void onReceive(Context context, Intent intent) {
        PendingResult pending = goAsync();
        Context appContext = context.getApplicationContext();
        new Thread(() -> {
            try {
                runSelfValidation(appContext, intent);
            } catch (Exception ex) {
                Log.e(TAG, "SAM_SELF_VALIDATE_FAIL", ex);
            } finally {
                pending.finish();
            }
        }, "sam-self-validation").start();
    }

    private static void runSelfValidation(Context context, Intent intent) throws Exception {
        SamLaunchContext launch = SamLaunchContext.fromIntent(intent);
        int valence = SamLaunchContext.clampScore(launch.autoValence);
        int arousal = SamLaunchContext.clampScore(launch.autoArousal);
        int sliderValence = Math.round((valence - 1) * 100f / 4f);
        int sliderArousal = Math.round((arousal - 1) * 100f / 4f);

        Log.i(TAG, "SAM_SELF_VALIDATE_START runId=" + launch.runId + " sessionId=" + launch.sessionId);
        logRender(SamScreenRenderer.renderSamSelected(context, launch.runId, valence, arousal));
        logRender(SamScreenRenderer.renderSliderSelected(context, launch.runId, sliderValence, sliderArousal));
        logRender(SamScreenRenderer.renderSaved(context, launch.runId));

        SamExporter.ExportResult export = AutoSamRunner.run(context, launch, SystemClock.elapsedRealtime());
        Log.i(TAG, "SAM_SELF_VALIDATE_PASS runId=" + launch.runId
            + " csv=\"" + export.csvFile.getAbsolutePath()
            + "\" json=\"" + export.jsonFile.getAbsolutePath() + "\"");
    }

    private static void logRender(SamScreenRenderer.RenderResult result) {
        String line = " stage=" + result.stage
            + " path=\"" + result.pngFile.getAbsolutePath()
            + "\" width=" + result.width
            + " height=" + result.height
            + " bytes=" + result.bytes
            + " nonBackgroundPixels=" + result.nonBackgroundPixels
            + " sha256=" + result.sha256;
        if (result.pass) {
            Log.i(TAG, "SAM_PANEL_CAPTURE_PASS" + line);
        } else {
            Log.e(TAG, "SAM_PANEL_CAPTURE_FAIL" + line);
        }
    }
}
