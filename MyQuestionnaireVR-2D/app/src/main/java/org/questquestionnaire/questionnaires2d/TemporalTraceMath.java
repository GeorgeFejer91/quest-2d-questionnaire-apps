package org.questquestionnaire.questionnaires2d;

final class TemporalTraceMath {
    private TemporalTraceMath() {
    }

    static double clamp(double value, double min, double max) {
        return Math.max(min, Math.min(max, value));
    }
}
