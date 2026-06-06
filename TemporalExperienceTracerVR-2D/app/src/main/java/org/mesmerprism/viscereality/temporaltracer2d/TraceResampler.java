package org.mesmerprism.viscereality.temporaltracer2d;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

final class TraceResampler {
    private TraceResampler() {
    }

    static List<TracePoint> normalizeAndResample(List<TracePoint> rawPoints, int targetCount) {
        if (rawPoints == null || rawPoints.size() < 2) {
            return Collections.emptyList();
        }

        List<TracePoint> monotonic = new ArrayList<>();
        double lastU = -1.0;
        for (TracePoint point : rawPoints) {
            if (point == null) {
                continue;
            }
            if (point.u + 1e-9 >= lastU) {
                monotonic.add(point);
                lastU = point.u;
            }
        }
        if (monotonic.size() < 2) {
            return Collections.emptyList();
        }

        List<TracePoint> anchored = new ArrayList<>(monotonic);
        TracePoint first = anchored.get(0);
        TracePoint last = anchored.get(anchored.size() - 1);
        anchored.set(0, new TracePoint(0.0, first.v, first.timestampMillis, first.timestampUtc));
        anchored.set(anchored.size() - 1, new TracePoint(1.0, last.v, last.timestampMillis, last.timestampUtc));

        int count = Math.max(2, targetCount);
        List<TracePoint> resampled = new ArrayList<>(count);
        int segment = 0;
        for (int i = 0; i < count; i++) {
            double targetU = count == 1 ? 0.0 : (double) i / (double) (count - 1);
            while (segment < anchored.size() - 2 && anchored.get(segment + 1).u < targetU) {
                segment++;
            }

            TracePoint a = anchored.get(segment);
            TracePoint b = anchored.get(Math.min(segment + 1, anchored.size() - 1));
            double span = b.u - a.u;
            double t = Math.abs(span) < 1e-9 ? 0.0 : (targetU - a.u) / span;
            t = TemporalTracerConfig.clamp(t, 0.0, 1.0);
            double v = a.v + ((b.v - a.v) * t);
            long millis = Math.round(a.timestampMillis + ((b.timestampMillis - a.timestampMillis) * t));
            String ts = i == 0 ? a.timestampUtc : i == count - 1 ? b.timestampUtc : "";
            resampled.add(new TracePoint(targetU, v, millis, ts));
        }
        return resampled;
    }
}
