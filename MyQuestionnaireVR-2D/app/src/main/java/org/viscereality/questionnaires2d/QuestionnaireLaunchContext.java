package org.viscereality.questionnaires2d;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.text.TextUtils;

final class QuestionnaireLaunchContext {
    static final String ACTION_RUN = "org.viscereality.questionnaires2d.RUN";
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
    static final String EXTRA_COMBINED_CSV_PATH = "mq.combinedCsvPath";
    static final String EXTRA_QUESTIONNAIRE_CONFIG_ID = "mq.questionnaireConfigId";
    static final String EXTRA_QUESTIONNAIRE_MODE = "mq.questionnaireMode";
    static final String EXTRA_FLOW_MODE = "mq.flowMode";
    static final String EXTRA_BLOCK_NUMBER = "mq.blockNumber";
    static final String EXTRA_BLOCK_ID = "mq.blockId";
    static final String EXTRA_SAVE_NAMESPACE = "mq.saveNamespace";
    static final String CHAINLINK_PACKAGE = "org.viscereality.chainlink";
    static final String CHAINLINK_COMMAND_ACTION = "org.viscereality.chainlink.COMMAND";
    static final String CHAINLINK_NEXT_BLOCK = "nextBlock";

    static final String FINISH_RESUME_CALLER = "resumeCaller";
    static final String FINISH_OPEN_NEXT = "openNext";
    static final String FINISH_STAY_SAVED = "staySaved";
    static final String MODE_FULL = "full";
    static final String MODE_BASELINE = "baseline";
    static final String MODE_PICTOGRAPHIC = "pictographic";

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
    final boolean chained;
    final String questionnaireMode;
    final String blockNumber;
    final String blockId;
    final String saveNamespace;

    private QuestionnaireLaunchContext(
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
        boolean chained,
        String questionnaireMode,
        String blockNumber,
        String blockId,
        String saveNamespace) {

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
        this.language = clean(language);
        this.finishBehavior = normalizeFinishBehavior(finishBehavior);
        this.callerPackage = clean(callerPackage);
        this.callerActivity = clean(callerActivity);
        this.nextPackage = clean(nextPackage);
        this.nextActivity = clean(nextActivity);
        this.autoCloseDelayMs = Math.max(0L, autoCloseDelayMs);
        this.chained = chained;
        this.questionnaireMode = normalizeQuestionnaireMode(questionnaireMode);
        this.blockNumber = clean(blockNumber);
        this.blockId = clean(blockId);
        this.saveNamespace = clean(saveNamespace);
    }

    static QuestionnaireLaunchContext fromIntent(Intent intent, QuestionnaireData.RuntimeConfig config) {
        QuestionnaireData.RuntimeChainDefaults defaults = config != null ? config.chainDefaults : new QuestionnaireData.RuntimeChainDefaults();
        String runId = TimeUtil.newRunId();
        boolean chained = isChainIntent(intent) || hasMqExtras(intent);
        String invocationId = value(intent, EXTRA_INVOCATION_ID, "invocationId");
        if (TextUtils.isEmpty(invocationId)) {
            invocationId = runId;
        }

        return new QuestionnaireLaunchContext(
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
            normalizeLanguage(value(intent, EXTRA_LANGUAGE, "language")),
            firstNonEmpty(value(intent, EXTRA_FINISH_BEHAVIOR, "finishBehavior"), defaults.finishBehavior),
            firstNonEmpty(value(intent, EXTRA_CALLER_PACKAGE, "callerPackage"), defaults.callerPackage),
            firstNonEmpty(value(intent, EXTRA_CALLER_ACTIVITY, "callerActivity"), defaults.callerActivity),
            firstNonEmpty(value(intent, EXTRA_NEXT_PACKAGE, "nextPackage"), defaults.nextPackage),
            firstNonEmpty(value(intent, EXTRA_NEXT_ACTIVITY, "nextActivity"), defaults.nextActivity),
            longValue(intent, EXTRA_AUTO_CLOSE_DELAY_MS, "autoCloseDelayMs", defaults.autoCloseDelayMs),
            chained,
            firstNonEmpty(value(intent, EXTRA_QUESTIONNAIRE_MODE, "questionnaireMode"), value(intent, EXTRA_FLOW_MODE, "flowMode")),
            value(intent, EXTRA_BLOCK_NUMBER, "blockNumber"),
            value(intent, EXTRA_BLOCK_ID, "blockId"),
            value(intent, EXTRA_SAVE_NAMESPACE, "saveNamespace"));
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

    boolean isBaselineOnly() {
        return MODE_BASELINE.equals(questionnaireMode);
    }

    boolean isPictographicOnly() {
        return MODE_PICTOGRAPHIC.equals(questionnaireMode);
    }

    String participantIdOrRunId() {
        return TextUtils.isEmpty(participantId) ? runId : participantId;
    }

    Intent completionIntent(Context context, QuestionnaireExporter.ExportResult export, QuestionnaireData.SessionRecord record) {
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
        if (shouldResumeCaller() && CHAINLINK_PACKAGE.equals(targetPackage)) {
            target.setAction(CHAINLINK_COMMAND_ACTION);
            target.putExtra("mq.command", CHAINLINK_NEXT_BLOCK);
            target.putExtra("mq.triggerSource", "questionnaire-complete");
        }
        target.putExtra(EXTRA_RESULT_STATUS, "complete");
        target.putExtra(EXTRA_RUN_ID, record.runId);
        target.putExtra(EXTRA_SESSION_ID, record.sessionId);
        target.putExtra(EXTRA_CHAIN_ID, record.chainId);
        target.putExtra(EXTRA_CHAIN_STEP_ID, record.chainStepId);
        target.putExtra(EXTRA_CHAIN_STEP_INDEX, record.chainStepIndex);
        target.putExtra(EXTRA_TIMESTAMP_UTC, record.timestampUtc);
        target.putExtra(EXTRA_EXPORT_JSON_PATH, export.jsonFile.getAbsolutePath());
        target.putExtra(EXTRA_EXPORT_CSV_PATH, export.csvFile.getAbsolutePath());
        if (export.combinedCsvFile != null) {
            target.putExtra(EXTRA_COMBINED_CSV_PATH, export.combinedCsvFile.getAbsolutePath());
        }
        target.putExtra(EXTRA_QUESTIONNAIRE_CONFIG_ID, record.questionnaireConfigId);
        if (record.participant != null) {
            target.putExtra(EXTRA_PARTICIPANT_ID, record.participant.participantId);
            target.putExtra(EXTRA_PARTICIPANT_NAME, record.participant.name);
            target.putExtra(EXTRA_LANGUAGE, record.participant.language);
        }
        return target;
    }

    private static boolean isChainIntent(Intent intent) {
        if (intent == null) {
            return false;
        }
        if (ACTION_RUN.equals(intent.getAction())) {
            return true;
        }
        Uri data = intent.getData();
        return data != null && "myquestionnaire2d".equals(data.getScheme()) && "run".equals(data.getHost());
    }

    private static boolean hasMqExtras(Intent intent) {
        if (intent == null || intent.getExtras() == null) {
            return false;
        }
        Bundle extras = intent.getExtras();
        for (String key : extras.keySet()) {
            if (key != null && key.startsWith("mq.")) {
                return true;
            }
        }
        return false;
    }

    private static String value(Intent intent, String extraName, String queryName) {
        if (intent == null) {
            return "";
        }
        String extra = intent.getStringExtra(extraName);
        if (!TextUtils.isEmpty(extra)) {
            return extra;
        }
        Uri data = intent.getData();
        return data != null ? clean(data.getQueryParameter(queryName)) : "";
    }

    private static long longValue(Intent intent, String extraName, String queryName, long fallback) {
        if (intent == null) {
            return fallback;
        }
        if (intent.hasExtra(extraName)) {
            Object rawExtra = intent.getExtras() != null ? intent.getExtras().get(extraName) : null;
            if (rawExtra instanceof Number) {
                return Math.max(0L, ((Number) rawExtra).longValue());
            }
            if (rawExtra != null) {
                try {
                    return Math.max(0L, Long.parseLong(String.valueOf(rawExtra)));
                } catch (NumberFormatException ignored) {
                    return fallback;
                }
            }
        }
        Uri data = intent.getData();
        if (data != null) {
            String raw = data.getQueryParameter(queryName);
            if (!TextUtils.isEmpty(raw)) {
                try {
                    return Math.max(0L, Long.parseLong(raw));
                } catch (NumberFormatException ignored) {
                    return fallback;
                }
            }
        }
        return fallback;
    }

    private static int intValue(Intent intent, String extraName, String queryName, int fallback) {
        if (intent == null) {
            return fallback;
        }
        if (intent.hasExtra(extraName)) {
            Object rawExtra = intent.getExtras() != null ? intent.getExtras().get(extraName) : null;
            if (rawExtra instanceof Number) {
                return ((Number) rawExtra).intValue();
            }
            if (rawExtra != null) {
                try {
                    return Integer.parseInt(String.valueOf(rawExtra));
                } catch (NumberFormatException ignored) {
                    return fallback;
                }
            }
        }
        Uri data = intent.getData();
        if (data != null) {
            String raw = data.getQueryParameter(queryName);
            if (!TextUtils.isEmpty(raw)) {
                try {
                    return Integer.parseInt(raw);
                } catch (NumberFormatException ignored) {
                    return fallback;
                }
            }
        }
        return fallback;
    }

    private static String normalizeFinishBehavior(String value) {
        String cleaned = clean(value);
        if (FINISH_RESUME_CALLER.equals(cleaned) || FINISH_OPEN_NEXT.equals(cleaned) || FINISH_STAY_SAVED.equals(cleaned)) {
            return cleaned;
        }
        return FINISH_STAY_SAVED;
    }

    private static String normalizeLanguage(String value) {
        String cleaned = clean(value);
        return TextUtils.isEmpty(cleaned) ? "" : QuestionnaireLoader.normalizeLanguage(cleaned);
    }

    private static String normalizeQuestionnaireMode(String value) {
        String cleaned = clean(value);
        if (MODE_BASELINE.equals(cleaned) || MODE_PICTOGRAPHIC.equals(cleaned) || MODE_FULL.equals(cleaned)) {
            return cleaned;
        }
        return MODE_FULL;
    }

    private static String firstNonEmpty(String value, String fallback) {
        return TextUtils.isEmpty(clean(value)) ? clean(fallback) : clean(value);
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
