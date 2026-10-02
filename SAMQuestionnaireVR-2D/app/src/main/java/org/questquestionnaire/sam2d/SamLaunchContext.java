package org.questquestionnaire.sam2d;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.text.TextUtils;

final class SamLaunchContext {
    static final String ACTION_RUN = "org.questquestionnaire.sam2d.RUN";

    static final String EXTRA_HANDOFF_SCHEMA = "mq.handoffSchema";
    static final String EXTRA_SESSION_ID = "mq.sessionId";
    static final String EXTRA_INVOCATION_ID = "mq.invocationId";
    static final String EXTRA_EXPERIMENT_ID = "mq.experimentId";
    static final String EXTRA_SCENARIO_ID = "mq.scenarioId";
    static final String EXTRA_TRIAL_ID = "mq.trialId";
    static final String EXTRA_TRIGGER_ID = "mq.triggerId";
    static final String EXTRA_BLOCK_ID = "mq.blockId";
    static final String EXTRA_BLOCK_NUMBER = "mq.blockNumber";
    static final String EXTRA_PARTICIPANT_ID = "mq.participantId";
    static final String EXTRA_PARTICIPANT_NAME = "mq.participantName";
    static final String EXTRA_LANGUAGE = "mq.language";
    static final String EXTRA_FINISH_BEHAVIOR = "mq.finishBehavior";
    static final String EXTRA_CALLER_PACKAGE = "mq.callerPackage";
    static final String EXTRA_CALLER_ACTIVITY = "mq.callerActivity";
    static final String EXTRA_NEXT_PACKAGE = "mq.nextPackage";
    static final String EXTRA_NEXT_ACTIVITY = "mq.nextActivity";
    static final String EXTRA_AUTO_SAM = "mq.autoSam";
    static final String EXTRA_AUTO_VALENCE = "mq.autoSamValence";
    static final String EXTRA_AUTO_AROUSAL = "mq.autoSamArousal";
    static final String EXTRA_CAPTURE_PANEL = "mq.capturePanel";
    static final String EXTRA_CAPTURE_PANEL_STAGE = "mq.capturePanelStage";
    static final String EXTRA_RETURN_PENDING_INTENT = "mq.returnPendingIntent";

    static final String FINISH_STAY_SAVED = "staySaved";
    static final String FINISH_RESUME_CALLER = "resumeCaller";
    static final String FINISH_OPEN_NEXT = "openNext";

    final String runId;
    final String sessionId;
    final String invocationId;
    final String experimentId;
    final String scenarioId;
    final String trialId;
    final String triggerId;
    final String blockId;
    final String blockNumber;
    final String participantId;
    final String participantName;
    final String language;
    final String finishBehavior;
    final String callerPackage;
    final String callerActivity;
    final String nextPackage;
    final String nextActivity;
    final boolean autoSam;
    final int autoValence;
    final int autoArousal;
    final boolean capturePanel;
    final String capturePanelStage;
    final PendingIntent returnPendingIntent;

    private SamLaunchContext(
        String runId,
        String sessionId,
        String invocationId,
        String experimentId,
        String scenarioId,
        String trialId,
        String triggerId,
        String blockId,
        String blockNumber,
        String participantId,
        String participantName,
        String language,
        String finishBehavior,
        String callerPackage,
        String callerActivity,
        String nextPackage,
        String nextActivity,
        boolean autoSam,
        int autoValence,
        int autoArousal,
        boolean capturePanel,
        String capturePanelStage,
        PendingIntent returnPendingIntent) {
        this.runId = runId;
        this.sessionId = sessionId;
        this.invocationId = invocationId;
        this.experimentId = experimentId;
        this.scenarioId = scenarioId;
        this.trialId = trialId;
        this.triggerId = triggerId;
        this.blockId = blockId;
        this.blockNumber = blockNumber;
        this.participantId = participantId;
        this.participantName = participantName;
        this.language = language;
        this.finishBehavior = finishBehavior;
        this.callerPackage = callerPackage;
        this.callerActivity = callerActivity;
        this.nextPackage = nextPackage;
        this.nextActivity = nextActivity;
        this.autoSam = autoSam;
        this.autoValence = autoValence;
        this.autoArousal = autoArousal;
        this.capturePanel = capturePanel;
        this.capturePanelStage = capturePanelStage;
        this.returnPendingIntent = returnPendingIntent;
    }

    static SamLaunchContext fromIntent(Intent intent) {
        String runId = TimeUtil.newRunId();
        String sessionId = value(intent, EXTRA_SESSION_ID, "sessionId");
        if (TextUtils.isEmpty(sessionId)) {
            sessionId = runId;
        }
        String invocationId = value(intent, EXTRA_INVOCATION_ID, "invocationId");
        if (TextUtils.isEmpty(invocationId)) {
            invocationId = runId;
        }
        String participantId = value(intent, EXTRA_PARTICIPANT_ID, "participantId");
        if (TextUtils.isEmpty(participantId)) {
            participantId = "SAM_" + runId;
        }
        String finishBehavior = value(intent, EXTRA_FINISH_BEHAVIOR, "finishBehavior");
        if (TextUtils.isEmpty(finishBehavior)) {
            finishBehavior = FINISH_STAY_SAVED;
        }

        return new SamLaunchContext(
            runId,
            sessionId,
            invocationId,
            value(intent, EXTRA_EXPERIMENT_ID, "experimentId"),
            value(intent, EXTRA_SCENARIO_ID, "scenarioId"),
            value(intent, EXTRA_TRIAL_ID, "trialId"),
            value(intent, EXTRA_TRIGGER_ID, "triggerId"),
            value(intent, EXTRA_BLOCK_ID, "blockId"),
            value(intent, EXTRA_BLOCK_NUMBER, "blockNumber"),
            participantId,
            value(intent, EXTRA_PARTICIPANT_NAME, "participantName"),
            value(intent, EXTRA_LANGUAGE, "language"),
            finishBehavior,
            value(intent, EXTRA_CALLER_PACKAGE, "callerPackage"),
            value(intent, EXTRA_CALLER_ACTIVITY, "callerActivity"),
            value(intent, EXTRA_NEXT_PACKAGE, "nextPackage"),
            value(intent, EXTRA_NEXT_ACTIVITY, "nextActivity"),
            boolValue(intent, EXTRA_AUTO_SAM, "autoSam"),
            clampScore(intValue(intent, EXTRA_AUTO_VALENCE, "autoSamValence", 3)),
            clampScore(intValue(intent, EXTRA_AUTO_AROUSAL, "autoSamArousal", 4)),
            boolValue(intent, EXTRA_CAPTURE_PANEL, "capturePanel"),
            capturePanelStageValue(intent),
            pendingIntentValue(intent));
    }

    boolean shouldCaptureStage(String stage) {
        return capturePanel
            && ("all".equals(capturePanelStage)
                || capturePanelStage.equals(stage)
                || stage.startsWith(capturePanelStage + "-"));
    }

    boolean shouldResumeCaller() {
        return FINISH_RESUME_CALLER.equals(finishBehavior);
    }

    boolean shouldOpenNext() {
        return FINISH_OPEN_NEXT.equals(finishBehavior);
    }

    boolean shouldStaySaved() {
        return !shouldResumeCaller() && !shouldOpenNext();
    }

    boolean hasReturnPendingIntent() {
        return returnPendingIntent != null;
    }

    Intent completionIntent(Context context, SamExporter.ExportResult export, SamResponseRecord record) {
        String targetPackage = shouldOpenNext() ? nextPackage : callerPackage;
        String targetActivity = shouldOpenNext() ? nextActivity : callerActivity;
        if (TextUtils.isEmpty(targetPackage)) {
            return null;
        }
        Intent intent = new Intent();
        if (!TextUtils.isEmpty(targetActivity)) {
            intent.setClassName(targetPackage, targetActivity);
        } else {
            intent.setPackage(targetPackage);
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        addCompletionExtras(intent, export, record, context);
        return intent;
    }

    void sendReturnPendingIntent(Context context, SamExporter.ExportResult export, SamResponseRecord record) throws PendingIntent.CanceledException {
        Intent fillIn = new Intent();
        addCompletionExtras(fillIn, export, record, context);
        returnPendingIntent.send(context, 0, fillIn);
    }

    private void addCompletionExtras(Intent target, SamExporter.ExportResult export, SamResponseRecord record, Context context) {
        target.putExtra("mq.resultStatus", "complete");
        target.putExtra("mq.resultSourcePackage", context.getPackageName());
        target.putExtra("mq.resultRunId", runId);
        target.putExtra("mq.sessionId", sessionId);
        target.putExtra("mq.invocationId", invocationId);
        target.putExtra("mq.triggerId", triggerId);
        target.putExtra("mq.blockId", blockId);
        target.putExtra("mq.blockNumber", blockNumber);
        target.putExtra("mq.samValence1To5", record.valenceScore);
        target.putExtra("mq.samArousal1To5", record.arousalScore);
        target.putExtra("mq.exportJsonPath", export.jsonFile.getAbsolutePath());
        target.putExtra("mq.exportCsvPath", export.csvFile.getAbsolutePath());
    }

    private static String value(Intent intent, String key, String legacyKey) {
        if (intent == null) {
            return "";
        }
        String value = intent.getStringExtra(key);
        if (TextUtils.isEmpty(value) && !TextUtils.isEmpty(legacyKey)) {
            value = intent.getStringExtra(legacyKey);
        }
        return value == null ? "" : value.trim();
    }

    private static boolean boolValue(Intent intent, String key, String legacyKey) {
        if (intent == null) {
            return false;
        }
        if (intent.hasExtra(key)) {
            return intent.getBooleanExtra(key, false);
        }
        return !TextUtils.isEmpty(legacyKey) && intent.getBooleanExtra(legacyKey, false);
    }

    private static int intValue(Intent intent, String key, String legacyKey, int fallback) {
        if (intent == null) {
            return fallback;
        }
        if (intent.hasExtra(key)) {
            return intent.getIntExtra(key, fallback);
        }
        if (!TextUtils.isEmpty(legacyKey) && intent.hasExtra(legacyKey)) {
            return intent.getIntExtra(legacyKey, fallback);
        }
        return fallback;
    }

    private static PendingIntent pendingIntentValue(Intent intent) {
        if (intent == null) {
            return null;
        }
        return intent.getParcelableExtra(EXTRA_RETURN_PENDING_INTENT);
    }

    private static String capturePanelStageValue(Intent intent) {
        String value = value(intent, EXTRA_CAPTURE_PANEL_STAGE, "capturePanelStage");
        if (TextUtils.isEmpty(value)) {
            return "all";
        }
        if ("sam".equals(value) || "affective-slider".equals(value) || "saved".equals(value) || "all".equals(value)) {
            return value;
        }
        return "all";
    }

    static int clampScore(int value) {
        return Math.max(1, Math.min(5, value));
    }
}
