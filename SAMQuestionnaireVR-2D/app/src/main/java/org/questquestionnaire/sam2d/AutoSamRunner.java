package org.questquestionnaire.sam2d;

import android.content.Context;
import android.os.SystemClock;
import android.util.Log;

final class AutoSamRunner {
    private static final String TAG = "SAM2D";

    private AutoSamRunner() {
    }

    static SamExporter.ExportResult run(Context context, SamLaunchContext launch, long startedElapsedMs) throws Exception {
        int valence = SamLaunchContext.clampScore(launch.autoValence);
        int arousal = SamLaunchContext.clampScore(launch.autoArousal);
        int sliderValence = Math.round((valence - 1) * 100f / 4f);
        int sliderArousal = Math.round((arousal - 1) * 100f / 4f);
        long nowElapsed = SystemClock.elapsedRealtime();
        String nowUtc = TimeUtil.utcIsoNowMillis();
        long nowUnix = TimeUtil.unixMillisNow();

        SamResponseRecord record = SamResponseRecord.create(launch, startedElapsedMs);
        record.inputPath = "command-replay";
        record.valenceScore = valence;
        record.arousalScore = arousal;
        record.valenceLabel = SamResponseRecord.valenceLabel(valence);
        record.arousalLabel = SamResponseRecord.arousalLabel(arousal);
        record.valenceResponseTimestampUtc = nowUtc;
        record.arousalResponseTimestampUtc = nowUtc;
        record.valenceResponseUnixMs = nowUnix;
        record.arousalResponseUnixMs = nowUnix;
        record.valenceResponseElapsedMs = nowElapsed;
        record.arousalResponseElapsedMs = nowElapsed;
        record.sliderValence = sliderValence;
        record.sliderArousal = sliderArousal;
        record.sliderValenceResponseTimestampUtc = nowUtc;
        record.sliderArousalResponseTimestampUtc = nowUtc;
        record.sliderValenceResponseUnixMs = nowUnix;
        record.sliderArousalResponseUnixMs = nowUnix;
        record.sliderValenceResponseElapsedMs = nowElapsed;
        record.sliderArousalResponseElapsedMs = nowElapsed;
        record.submittedUnixMs = TimeUtil.unixMillisNow();
        record.submittedElapsedMs = SystemClock.elapsedRealtime();

        Log.i(TAG, "SAM_COMMAND_REPLAY_START runId=" + launch.runId);
        Log.i(TAG, "SAM_INPUT action=Select dimension=valence score=" + valence + " source=command-replay");
        Log.i(TAG, "SAM_INPUT action=Select dimension=arousal score=" + arousal + " source=command-replay");
        Log.i(TAG, "SAM_INPUT action=SliderAdjust dimension=valence value=" + sliderValence + " source=command-replay");
        Log.i(TAG, "SAM_INPUT action=SliderAdjust dimension=arousal value=" + sliderArousal + " source=command-replay");
        SamExporter.ExportResult export = SamExporter.writeSession(context, record);
        Log.i(TAG, "SAM_EXPORT_COMPLETE csv=\"" + export.csvFile.getAbsolutePath()
            + "\" json=\"" + export.jsonFile.getAbsolutePath()
            + "\" runId=" + launch.runId
            + " valence=" + valence
            + " arousal=" + arousal
            + " sliderValence=" + sliderValence
            + " sliderArousal=" + sliderArousal);
        Log.i(TAG, "SAM_COMMAND_REPLAY_EXPORT_MATCH runId=" + launch.runId);
        return export;
    }
}
