package org.viscereality.temporaltracer2d;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.text.TextUtils;

final class TemporalTracerLaunchContext {
    static final String ACTION_RUN = "org.viscereality.temporaltracer2d.RUN";
    static final String EXTRA_SESSION_ID = "mq.sessionId";
    static final String EXTRA_INVOCATION_ID = "mq.invocationId";
    static final String EXTRA_EXPERIMENT_ID = "mq.experimentId";
    static final String EXTRA_SCENARIO_ID = "mq.scenarioId";
    static final String EXTRA_TRIAL_ID = "mq.trialId";
    static final String EXTRA_CHAIN_ID = "mq.chainId";
    static final String EXTRA_CHAIN_STEP_ID = "mq.chainStepId";
    static final String EXTRA_CHAIN_STEP_INDEX = "mq.chainStepIndex";
    static final String EXTRA_PARTICIPANT_ID = "mq.participantId";
    static final String EXTRA_PARTICIPANT_NAME = "mq.participantName";
    static final String EXTRA_LANGUAGE = "mq.language";
    static final String EXTRA_FINISH_BEHAVIOR = "mq.finishBehavior";
    static final String EXTRA_CALLER_PACKAGE = "mq.callerPackage";
    static final String EXTRA_CALLER_ACTIVITY = "mq.callerActivity";
    static final String EXTRA_NEXT_PACKAGE = "mq.nextPackage";
    static final String EXTRA_NEXT_ACTIVITY = "mq.nextActivity";
    static final String EXTRA_AUTO_CLOSE_DELAY_MS = "mq.autoCloseDelayMs";
    static final String EXTRA_RESULT_STATUS = "mq.resultStatus";
    static final String EXTRA_RUN_ID = "mq.runId";
    static final String EXTRA_TIMESTAMP_UTC = "mq.timestampUtc";
    static final String EXTRA_EXPORT_JSON_PATH = "mq.exportJsonPath";
    static final String EXTRA_EXPORT_CSV_PATH = "mq.exportCsvPath";
    static final String EXTRA_EXPORT_SVG_PATH = "mq.exportSvgPath";
    static final String EXTRA_TRACER_CONFIG_ID = "mq.tracerConfigId";
    static final String EXTRA_HANDOFF_SCHEMA = "mq.handoffSchema";
    static final String EXTRA_RETURN_PENDING_INTENT = "mq.returnPendingIntent";
    static final String EXTRA_TRIGGER_ID = "mq.triggerId";
    static final String EXTRA_BLOCK_NUMBER = "mq.blockNumber";
    static final String EXTRA_BLOCK_ID = "mq.blockId";
    static final String EXTRA_AUTO_TRACE = "mq.autoTrace";

    static final String FINISH_RESUME_CALLER = "resumeCaller";
    static final String FINISH_OPEN_NEXT = "openNext";
    static final String FINISH_STAY_SAVED = "staySaved";
    static final String HANDOFF_SCHEMA_V1 = "mq.handoff.v1";

    final String runId;
    final String sessionId;
    final String invocationId;
    final String experimentId;
    final String scenarioId;
    final String trialId;
    final String chainId;
    final String chainStepId;
    final int chainStepIndex;
    final String participantId;
    final String participantName;
    final String language;
    final String finishBehavior;
    final String callerPackage;
    final String callerActivity;
    final String nextPackage;
    final String nextActivity;
    final long autoCloseDelayMs;
    final PendingIntent returnPendingIntent;
    final String handoffSchema;
    final String triggerId;
    final String blockNumber;
    final String blockId;
    final boolean chained;
    final boolean autoTrace;

    private TemporalTracerLaunchContext(
        String runId,
        String sessionId,
        String invocationId,
        String experimentId,
        String scenarioId,
        String trialId,
        String chainId,
        String chainStepId,
        int chainStepIndex,
        String participantId,
        String participantName,
        String language,
        String finishBehavior,
        String callerPackage,
        String callerActivity,
        String nextPackage,
        String nextActivity,
        long autoCloseDelayMs,
        PendingIntent returnPendingIntent,
        String handoffSchema,
        String triggerId,
        String blockNumber,
        String blockId,
        boolean chained,
        boolean autoTrace) {
        this.runId = runId;
        this.sessionId = clean(sessionId);
        this.invocationId = clean(invocationId);
        this.experimentId = clean(experimentId);
        this.scenarioId = clean(scenarioId);
        this.trialId = clean(trialId);
        this.chainId = clean(chainId);
        this.chainStepId = clean(chainStepId);
        this.chainStepIndex = chainStepIndex;
        this.participantId = clean(participantId);
        this.participantName = clean(participantName);
        this.language = normalizeLanguage(language);
        this.finishBehavior = normalizeFinishBehavior(finishBehavior);
        this.callerPackage = clean(callerPackage);
        this.callerActivity = clean(callerActivity);
        this.nextPackage = clean(nextPackage);
        this.nextActivity = clean(nextActivity);
        this.autoCloseDelayMs = Math.max(0L, autoCloseDelayMs);
        this.returnPendingIntent = returnPendingIntent;
        this.handoffSchema = clean(handoffSchema);
        this.triggerId = clean(triggerId);
        this.blockNumber = clean(blockNumber);
        this.blockId = clean(blockId);
        this.chained = chained;
        this.autoTrace = autoTrace;
    }

    static TemporalTracerLaunchContext fromIntent(Intent intent) {
        String runId = TimeUtil.newRunId();
        String invocationId = value(intent, EXTRA_INVOCATION_ID, "invocationId");
        if (TextUtils.isEmpty(invocationId)) {
            invocationId = runId;
        }

        return new TemporalTracerLaunchContext(
            runId,
            value(intent, EXTRA_SESSION_ID, "sessionId"),
            invocationId,
            value(intent, EXTRA_EXPERIMENT_ID, "experimentId"),
            value(intent, EXTRA_SCENARIO_ID, "scenarioId"),
            value(intent, EXTRA_TRIAL_ID, "trialId"),
            value(intent, EXTRA_CHAIN_ID, "chainId"),
            value(intent, EXTRA_CHAIN_STEP_ID, "chainStepId"),
            intValue(intent, EXTRA_CHAIN_STEP_INDEX, "chainStepIndex", -1),
            value(intent, EXTRA_PARTICIPANT_ID, "participantId"),
            value(intent, EXTRA_PARTICIPANT_NAME, "participantName"),
            value(intent, EXTRA_LANGUAGE, "language"),
            value(intent, EXTRA_FINISH_BEHAVIOR, "finishBehavior"),
            value(intent, EXTRA_CALLER_PACKAGE, "callerPackage"),
            value(intent, EXTRA_CALLER_ACTIVITY, "callerActivity"),
            value(intent, EXTRA_NEXT_PACKAGE, "nextPackage"),
            value(intent, EXTRA_NEXT_ACTIVITY, "nextActivity"),
            longValue(intent, EXTRA_AUTO_CLOSE_DELAY_MS, "autoCloseDelayMs", 2000L),
            pendingIntentExtra(intent, EXTRA_RETURN_PENDING_INTENT),
            firstNonBlank(value(intent, EXTRA_HANDOFF_SCHEMA, "handoffSchema"), HANDOFF_SCHEMA_V1),
            value(intent, EXTRA_TRIGGER_ID, "triggerId"),
            value(intent, EXTRA_BLOCK_NUMBER, "blockNumber"),
            value(intent, EXTRA_BLOCK_ID, "blockId"),
            hasMqExtras(intent) || ACTION_RUN.equals(intent != null ? intent.getAction() : null),
            boolValue(intent, EXTRA_AUTO_TRACE, "autoTrace", false));
    }

    boolean shouldResumeCaller() {
        return FINISH_RESUME_CALLER.equals(finishBehavior);
    }

    boolean shouldOpenNext() {
        return FINISH_OPEN_NEXT.equals(finishBehavior);
    }

    boolean shouldStaySaved() {
        return FINISH_STAY_SAVED.equals(finishBehavior);
    }

    boolean hasReturnPendingIntent() {
        return returnPendingIntent != null;
    }

    Intent completionIntent(Context context, TemporalTraceExporter.ExportResult lastExport, TemporalTracerConfig config) {
        String targetPackage = shouldResumeCaller() ? callerPackage : shouldOpenNext() ? nextPackage : "";
        String targetActivity = shouldResumeCaller() ? callerActivity : shouldOpenNext() ? nextActivity : "";
        if (TextUtils.isEmpty(targetPackage)) {
            return null;
        }

        Intent target;
        if (!TextUtils.isEmpty(targetActivity)) {
            target = new Intent();
            target.setClassName(targetPackage, targetActivity);
        } else {
            target = context.getPackageManager().getLaunchIntentForPackage(targetPackage);
            if (target == null) {
                return null;
            }
        }

        target.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        addCompletionExtras(target, lastExport, config);
        return target;
    }

    void sendReturnPendingIntent(Context context, TemporalTraceExporter.ExportResult lastExport, TemporalTracerConfig config) throws PendingIntent.CanceledException {
        Intent fillIn = new Intent();
        addCompletionExtras(fillIn, lastExport, config);
        returnPendingIntent.send(context, 0, fillIn);
    }

    private void addCompletionExtras(Intent target, TemporalTraceExporter.ExportResult lastExport, TemporalTracerConfig config) {
        target.putExtra(EXTRA_HANDOFF_SCHEMA, HANDOFF_SCHEMA_V1);
        target.putExtra(EXTRA_RESULT_STATUS, "complete");
        target.putExtra(EXTRA_TRIGGER_ID, triggerId);
        target.putExtra(EXTRA_RUN_ID, runId);
        target.putExtra(EXTRA_SESSION_ID, sessionId);
        target.putExtra(EXTRA_CHAIN_ID, chainId);
        target.putExtra(EXTRA_CHAIN_STEP_ID, chainStepId);
        target.putExtra(EXTRA_CHAIN_STEP_INDEX, chainStepIndex);
        target.putExtra(EXTRA_BLOCK_NUMBER, blockNumber);
        target.putExtra(EXTRA_BLOCK_ID, blockId);
        target.putExtra(EXTRA_TIMESTAMP_UTC, TimeUtil.utcIsoNowMillis());
        target.putExtra(EXTRA_TRACER_CONFIG_ID, config.tracerId);
        target.putExtra(EXTRA_PARTICIPANT_ID, participantId);
        target.putExtra(EXTRA_PARTICIPANT_NAME, participantName);
        target.putExtra(EXTRA_LANGUAGE, language);
        if (lastExport != null) {
            target.putExtra(EXTRA_EXPORT_JSON_PATH, lastExport.jsonFile.getAbsolutePath());
            target.putExtra(EXTRA_EXPORT_CSV_PATH, lastExport.csvFile.getAbsolutePath());
            target.putExtra(EXTRA_EXPORT_SVG_PATH, lastExport.svgFile.getAbsolutePath());
        }
    }

    private static String normalizeLanguage(String value) {
        String clean = clean(value);
        if (clean.equalsIgnoreCase("de") || clean.equalsIgnoreCase("german") || clean.equalsIgnoreCase("deutsch")) {
            return "Deutsch";
        }
        if (clean.equalsIgnoreCase("en") || clean.equalsIgnoreCase("english")) {
            return "English";
        }
        return clean;
    }

    private static String normalizeFinishBehavior(String value) {
        String clean = clean(value);
        if (FINISH_RESUME_CALLER.equals(clean) || FINISH_OPEN_NEXT.equals(clean) || FINISH_STAY_SAVED.equals(clean)) {
            return clean;
        }
        return FINISH_STAY_SAVED;
    }

    private static boolean hasMqExtras(Intent intent) {
        if (intent == null) {
            return false;
        }
        Bundle extras = intent.getExtras();
        if (extras == null) {
            return false;
        }
        for (String key : extras.keySet()) {
            if (key != null && key.startsWith("mq.")) {
                return true;
            }
        }
        return false;
    }

    private static String value(Intent intent, String extraName, String legacyName) {
        if (intent == null) {
            return "";
        }
        String value = intent.getStringExtra(extraName);
        if (TextUtils.isEmpty(value) && !TextUtils.isEmpty(legacyName)) {
            value = intent.getStringExtra(legacyName);
        }
        return clean(value);
    }

    private static int intValue(Intent intent, String extraName, String legacyName, int defaultValue) {
        if (intent == null) {
            return defaultValue;
        }
        if (intent.hasExtra(extraName)) {
            return intent.getIntExtra(extraName, defaultValue);
        }
        if (!TextUtils.isEmpty(legacyName) && intent.hasExtra(legacyName)) {
            return intent.getIntExtra(legacyName, defaultValue);
        }
        return defaultValue;
    }

    private static long longValue(Intent intent, String extraName, String legacyName, long defaultValue) {
        if (intent == null) {
            return defaultValue;
        }
        if (intent.hasExtra(extraName)) {
            return intent.getLongExtra(extraName, defaultValue);
        }
        if (!TextUtils.isEmpty(legacyName) && intent.hasExtra(legacyName)) {
            return intent.getLongExtra(legacyName, defaultValue);
        }
        return defaultValue;
    }

    private static boolean boolValue(Intent intent, String extraName, String legacyName, boolean defaultValue) {
        if (intent == null) {
            return defaultValue;
        }
        if (intent.hasExtra(extraName)) {
            return boolExtraValue(intent, extraName, defaultValue);
        }
        if (!TextUtils.isEmpty(legacyName) && intent.hasExtra(legacyName)) {
            return boolExtraValue(intent, legacyName, defaultValue);
        }
        return defaultValue;
    }

    private static boolean boolExtraValue(Intent intent, String extraName, boolean defaultValue) {
        Bundle extras = intent.getExtras();
        if (extras != null) {
            Object value = extras.get(extraName);
            if (value instanceof Boolean) {
                return (Boolean) value;
            }
            if (value instanceof String) {
                String clean = clean((String) value);
                if (clean.equalsIgnoreCase("true") || clean.equals("1") || clean.equalsIgnoreCase("yes")) {
                    return true;
                }
                if (clean.equalsIgnoreCase("false") || clean.equals("0") || clean.equalsIgnoreCase("no")) {
                    return false;
                }
            }
        }
        return intent.getBooleanExtra(extraName, defaultValue);
    }

    private static PendingIntent pendingIntentExtra(Intent intent, String extraName) {
        if (intent == null || !intent.hasExtra(extraName)) {
            return null;
        }
        if (Build.VERSION.SDK_INT >= 33) {
            return intent.getParcelableExtra(extraName, PendingIntent.class);
        }
        return intent.getParcelableExtra(extraName);
    }

    private static String firstNonBlank(String... values) {
        if (values == null) {
            return "";
        }
        for (String value : values) {
            String clean = clean(value);
            if (!TextUtils.isEmpty(clean)) {
                return clean;
            }
        }
        return "";
    }

    static String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
