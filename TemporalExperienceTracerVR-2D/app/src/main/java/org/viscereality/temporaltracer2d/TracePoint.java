package org.viscereality.temporaltracer2d;

final class TracePoint {
    final double u;
    final double v;
    final long timestampMillis;
    final String timestampUtc;

    TracePoint(double u, double v, long timestampMillis, String timestampUtc) {
        this.u = TemporalTracerConfig.clamp(u, 0.0, 1.0);
        this.v = TemporalTracerConfig.clamp(v, 0.0, 1.0);
        this.timestampMillis = timestampMillis;
        this.timestampUtc = timestampUtc == null ? "" : timestampUtc;
    }

    TracePoint withU(double nextU) {
        return new TracePoint(nextU, v, timestampMillis, timestampUtc);
    }
}
