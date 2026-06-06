package org.mesmerprism.viscereality.temporaltracer2d;

import android.util.Log;

import java.util.ArrayList;
import java.util.List;

final class TemporalTraceAutoRunner {
    private static final String TAG = "TemporalTraceAutoRunner";

    private TemporalTraceAutoRunner() {
    }

    static TemporalTraceExporter.ExportResult run(
        TemporalTraceExporter exporter,
        TemporalTracerLaunchContext launch,
        TemporalTracerConfig config,
        String language,
        String participantId,
        String participantName) throws Exception {
        Log.i(TAG, "TEMPORAL_TRACER_COMMAND_REPLAY_START runId=" + launch.runId + " language=" + language);
        List<TemporalTracerConfig.TraceItem> items = config.items(language);
        TemporalTraceExporter.ExportResult last = null;
        for (int i = 0; i < items.size(); i++) {
            List<TracePoint> raw = fixturePoints(i);
            List<TracePoint> resampled = TraceResampler.normalizeAndResample(raw, config.axis.targetSampleCount);
            last = exporter.exportTrace(launch, config, language, participantId, participantName, i, items.get(i), raw, resampled);
            exporter.writeDraft(launch, config, language, participantId, participantName, i + 1, i + 1);
        }
        exporter.markDraftComplete(launch);
        Log.i(TAG, "TEMPORAL_TRACER_COMMAND_REPLAY_PASS runId=" + launch.runId + " traceCount=" + items.size());
        return last;
    }

    static List<TracePoint> fixturePoints(int traceIndex) {
        List<TracePoint> points = new ArrayList<>();
        long base = TimeUtil.unixMillisNow();
        double phase = traceIndex * 0.23;
        for (int i = 0; i < 96; i++) {
            double u = (double) i / 95.0;
            double v = 0.45 + (0.30 * Math.sin((u * Math.PI * 1.35) + phase));
            points.add(new TracePoint(u, v, base + (i * 100L), i == 0 || i == 95 ? TimeUtil.utcIsoNowMillis() : ""));
        }
        return points;
    }
}
