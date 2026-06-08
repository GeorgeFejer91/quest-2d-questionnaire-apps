package org.questquestionnaire.questionnaires2d;

final class TracePoint {
    final double u;
    final double v;
    final long timestampMillis;
    final String timestampUtc;

    TracePoint(double u, double v, long timestampMillis, String timestampUtc) {
        this.u = TemporalTraceMath.clamp(u, 0.0, 1.0);
        this.v = TemporalTraceMath.clamp(v, 0.0, 1.0);
        this.timestampMillis = timestampMillis;
        this.timestampUtc = timestampUtc == null ? "" : timestampUtc;
    }
}
