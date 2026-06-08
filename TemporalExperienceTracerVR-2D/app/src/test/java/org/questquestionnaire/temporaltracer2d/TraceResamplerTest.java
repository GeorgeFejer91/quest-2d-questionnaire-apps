package org.questquestionnaire.temporaltracer2d;

import org.junit.Test;

import java.util.ArrayList;
import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;

public final class TraceResamplerTest {
    @Test
    public void resampledTraceIsAnchoredToAxisEdges() {
        List<TracePoint> raw = new ArrayList<>();
        raw.add(new TracePoint(0.03, 0.20, 10L, "start"));
        raw.add(new TracePoint(0.45, 0.60, 20L, ""));
        raw.add(new TracePoint(0.98, 0.40, 30L, "end"));

        List<TracePoint> resampled = TraceResampler.normalizeAndResample(raw, 5);

        assertEquals(5, resampled.size());
        assertEquals(0.0, resampled.get(0).u, 0.000001);
        assertEquals(1.0, resampled.get(4).u, 0.000001);
        assertEquals(0.20, resampled.get(0).v, 0.000001);
        assertEquals(0.40, resampled.get(4).v, 0.000001);
    }

    @Test
    public void backtrackingPointsAreIgnored() {
        List<TracePoint> raw = new ArrayList<>();
        raw.add(new TracePoint(0.00, 0.10, 10L, ""));
        raw.add(new TracePoint(0.50, 0.50, 20L, ""));
        raw.add(new TracePoint(0.30, 0.90, 30L, ""));
        raw.add(new TracePoint(1.00, 0.20, 40L, ""));

        List<TracePoint> resampled = TraceResampler.normalizeAndResample(raw, 4);

        assertFalse(resampled.isEmpty());
        assertEquals(1.0, resampled.get(resampled.size() - 1).u, 0.000001);
    }
}
