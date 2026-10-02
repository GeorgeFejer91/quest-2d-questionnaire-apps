package org.questquestionnaire.sam2d;

final class SamResponseRecord {
    static final String APP_VERSION = "0.1.1";
    static final String RATING_TARGET = "previous_session";

    String runId;
    String sessionId;
    String invocationId;
    String experimentId;
    String scenarioId;
    String trialId;
    String triggerId;
    String blockId;
    String blockNumber;
    String participantId;
    String participantName;
    String language;
    String finishBehavior;
    String callerPackage;
    String callerActivity;
    String nextPackage;
    String nextActivity;
    String timestampUtc;
    long startedUnixMs;
    long startedElapsedMs;
    long submittedUnixMs;
    long submittedElapsedMs;
    int valenceScore;
    int arousalScore;
    String valenceLabel;
    String arousalLabel;
    String valenceResponseTimestampUtc;
    String arousalResponseTimestampUtc;
    long valenceResponseUnixMs;
    long arousalResponseUnixMs;
    long valenceResponseElapsedMs;
    long arousalResponseElapsedMs;
    int sliderValence;
    int sliderArousal;
    String sliderValenceResponseTimestampUtc;
    String sliderArousalResponseTimestampUtc;
    long sliderValenceResponseUnixMs;
    long sliderArousalResponseUnixMs;
    long sliderValenceResponseElapsedMs;
    long sliderArousalResponseElapsedMs;
    String inputPath;

    static SamResponseRecord create(SamLaunchContext launch, long startedElapsedMs) {
        SamResponseRecord record = new SamResponseRecord();
        record.runId = launch.runId;
        record.sessionId = launch.sessionId;
        record.invocationId = launch.invocationId;
        record.experimentId = launch.experimentId;
        record.scenarioId = launch.scenarioId;
        record.trialId = launch.trialId;
        record.triggerId = launch.triggerId;
        record.blockId = launch.blockId;
        record.blockNumber = launch.blockNumber;
        record.participantId = launch.participantId;
        record.participantName = launch.participantName;
        record.language = launch.language;
        record.finishBehavior = launch.finishBehavior;
        record.callerPackage = launch.callerPackage;
        record.callerActivity = launch.callerActivity;
        record.nextPackage = launch.nextPackage;
        record.nextActivity = launch.nextActivity;
        record.timestampUtc = TimeUtil.utcIsoNowMillis();
        record.startedUnixMs = TimeUtil.unixMillisNow();
        record.startedElapsedMs = startedElapsedMs;
        record.inputPath = "manual";
        return record;
    }

    static double normalized(int score) {
        return (SamLaunchContext.clampScore(score) - 1) / 4.0;
    }

    static String valenceLabel(int score) {
        switch (SamLaunchContext.clampScore(score)) {
            case 1: return "very_unpleasant";
            case 2: return "unpleasant";
            case 3: return "neutral";
            case 4: return "pleasant";
            default: return "very_pleasant";
        }
    }

    static String arousalLabel(int score) {
        switch (SamLaunchContext.clampScore(score)) {
            case 1: return "very_calm";
            case 2: return "calm";
            case 3: return "neutral";
            case 4: return "aroused";
            default: return "very_aroused";
        }
    }
}
