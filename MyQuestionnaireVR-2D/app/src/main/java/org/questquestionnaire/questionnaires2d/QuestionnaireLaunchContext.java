package org.questquestionnaire.questionnaires2d;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.text.TextUtils;

import java.util.ArrayList;
import java.util.List;

final class QuestionnaireLaunchContext {
    static final String ACTION_RUN = "org.questquestionnaire.questionnaires2d.RUN";
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
    static final String EXTRA_HANDOFF_SCHEMA = "mq.handoffSchema";
    static final String EXTRA_RETURN_PENDING_INTENT = "mq.returnPendingIntent";
    static final String EXTRA_TRIGGER_ID = "mq.triggerId";
    static final String EXTRA_QUESTIONNAIRE_MODE = "mq.questionnaireMode";
    static final String EXTRA_QUESTIONNAIRE_SEQUENCE = "mq.questionnaireSequence";
    static final String EXTRA_FLOW_MODE = "mq.flowMode";
    static final String EXTRA_BLOCK_NUMBER = "mq.blockNumber";
    static final String EXTRA_BLOCK_ID = "mq.blockId";
    static final String EXTRA_SAVE_NAMESPACE = "mq.saveNamespace";
    static final String CHAINLINK_PACKAGE = "org.questquestionnaire.chainlink";
    static final String CHAINLINK_COMMAND_ACTION = "org.questquestionnaire.chainlink.COMMAND";
    static final String CHAINLINK_NEXT_BLOCK = "nextBlock";

    static final String FINISH_RESUME_CALLER = "resumeCaller";
    static final String FINISH_OPEN_NEXT = "openNext";
    static final String FINISH_STAY_SAVED = "staySaved";
    static final String HANDOFF_SCHEMA_V1 = "mq.handoff.v1";
    static final String MODE_NONE = "none";
    static final String MODE_FULL = "full";
    static final String MODE_DEMOGRAPHICS = "demographics";
    static final String MODE_BASELINE = "baseline";
    static final String MODE_PICTOGRAPHIC = "pictographic";
    static final String MODE_MAIA2 = "maia2";
    static final String MODE_SLIDER = "slider";
    static final String MODE_TEMPORAL_TRACER = "temporalTracer";
    static final String MODULE_DEMOGRAPHICS = "demographics";
    static final String MODULE_MAIA2 = "maia2";
    static final String MODULE_PICTOGRAPHIC = "pictographic";
    static final String MODULE_SLIDER = "slider";
    static final String MODULE_TEMPORAL_TRACER = "temporalTracer";

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
    final boolean chained;
    final String questionnaireMode;
    final List<String> questionnaireSequence;
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
        PendingIntent returnPendingIntent,
        String handoffSchema,
        String triggerId,
        boolean chained,
        String questionnaireMode,
        List<String> questionnaireSequence,
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
        this.returnPendingIntent = returnPendingIntent;
        this.handoffSchema = clean(handoffSchema);
        this.triggerId = clean(triggerId);
        this.chained = chained;
        this.questionnaireMode = normalizeQuestionnaireMode(questionnaireMode);
        this.questionnaireSequence = normalizeQuestionnaireSequence(questionnaireSequence, this.questionnaireMode);
        this.blockNumber = clean(blockNumber);
        this.blockId = clean(blockId);
        this.saveNamespace = clean(saveNamespace);
    }

    static QuestionnaireLaunchContext fromIntent(Intent intent, QuestionnaireData.RuntimeConfig config) {
        QuestionnaireData.RuntimeChainDefaults defaults = config != null ? config.chainDefaults : new QuestionnaireData.RuntimeChainDefaults();
        String runId = TimeUtil.newRunId();
        boolean chained = isChainIntent(intent) || hasMqExtras(intent);
        String explicitTriggerId = value(intent, EXTRA_TRIGGER_ID, "triggerId");
        String triggerId = firstNonEmpty(explicitTriggerId, defaults.triggerId);
        QuestionnaireData.RuntimeTriggerMapping triggerMapping = config != null && !TextUtils.isEmpty(explicitTriggerId)
            ? config.findTriggerMapping(explicitTriggerId)
            : null;
        String invocationId = value(intent, EXTRA_INVOCATION_ID, "invocationId");
        if (TextUtils.isEmpty(invocationId)) {
            invocationId = runId;
        }
        String explicitQuestionnaireMode = firstNonEmpty(value(intent, EXTRA_QUESTIONNAIRE_MODE, "questionnaireMode"), value(intent, EXTRA_FLOW_MODE, "flowMode"));
        String questionnaireMode = firstNonEmpty(
            firstNonEmpty(explicitQuestionnaireMode, triggerMapping != null ? triggerMapping.questionnaireMode : ""),
            defaults.questionnaireMode);
        List<String> explicitQuestionnaireSequence = sequenceValue(intent, EXTRA_QUESTIONNAIRE_SEQUENCE, "questionnaireSequence");
        List<String> questionnaireSequence = explicitQuestionnaireSequence;
        if (questionnaireSequence.isEmpty() && triggerMapping != null && !triggerMapping.questionnaireSequence.isEmpty()) {
            questionnaireSequence = triggerMapping.questionnaireSequence;
        } else if (questionnaireSequence.isEmpty() && TextUtils.isEmpty(explicitQuestionnaireMode)) {
            questionnaireSequence = defaults.questionnaireSequence;
        }
        long autoCloseDelayFallback = triggerMapping != null ? triggerMapping.autoCloseDelayMs : defaults.autoCloseDelayMs;

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
            normalizeLanguage(firstNonEmpty(value(intent, EXTRA_LANGUAGE, "language"), triggerMapping != null ? triggerMapping.language : "")),
            firstNonEmpty(value(intent, EXTRA_FINISH_BEHAVIOR, "finishBehavior"), defaults.finishBehavior),
            firstNonEmpty(value(intent, EXTRA_CALLER_PACKAGE, "callerPackage"), defaults.callerPackage),
            firstNonEmpty(value(intent, EXTRA_CALLER_ACTIVITY, "callerActivity"), defaults.callerActivity),
            firstNonEmpty(value(intent, EXTRA_NEXT_PACKAGE, "nextPackage"), defaults.nextPackage),
            firstNonEmpty(value(intent, EXTRA_NEXT_ACTIVITY, "nextActivity"), defaults.nextActivity),
            longValue(intent, EXTRA_AUTO_CLOSE_DELAY_MS, "autoCloseDelayMs", autoCloseDelayFallback),
            pendingIntentExtra(intent, EXTRA_RETURN_PENDING_INTENT),
            firstNonEmpty(value(intent, EXTRA_HANDOFF_SCHEMA, "handoffSchema"), HANDOFF_SCHEMA_V1),
            triggerId,
            chained,
            questionnaireMode,
            questionnaireSequence,
            firstNonEmpty(firstNonEmpty(value(intent, EXTRA_BLOCK_NUMBER, "blockNumber"), triggerMapping != null ? triggerMapping.blockNumber : ""), defaults.blockNumber),
            firstNonEmpty(firstNonEmpty(value(intent, EXTRA_BLOCK_ID, "blockId"), triggerMapping != null ? triggerMapping.blockId : ""), defaults.blockId),
            firstNonEmpty(firstNonEmpty(value(intent, EXTRA_SAVE_NAMESPACE, "saveNamespace"), triggerMapping != null ? triggerMapping.saveNamespace : ""), defaults.saveNamespace));
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

    boolean isDemographicsOnly() {
        return questionnaireSequence.size() == 1 && MODULE_DEMOGRAPHICS.equals(questionnaireSequence.get(0));
    }

    boolean isBaselineOnly() {
        return questionnaireSequence.size() == 2
            && MODULE_DEMOGRAPHICS.equals(questionnaireSequence.get(0))
            && MODULE_MAIA2.equals(questionnaireSequence.get(1));
    }

    boolean isPictographicOnly() {
        return questionnaireSequence.size() == 1 && MODULE_PICTOGRAPHIC.equals(questionnaireSequence.get(0));
    }

    boolean shouldRunDemographics() {
        return questionnaireSequence.contains(MODULE_DEMOGRAPHICS);
    }

    boolean shouldRunMaia2() {
        return questionnaireSequence.contains(MODULE_MAIA2);
    }

    boolean shouldRunPictographic() {
        return questionnaireSequence.contains(MODULE_PICTOGRAPHIC);
    }

    boolean shouldRunSlider() {
        return questionnaireSequence.contains(MODULE_SLIDER);
    }

    boolean shouldRunTemporalTracer() {
        return questionnaireSequence.contains(MODULE_TEMPORAL_TRACER);
    }

    String questionnaireSequenceCsv() {
        return TextUtils.join(",", questionnaireSequence);
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
        addCompletionExtras(target, export, record);
        return target;
    }

    void sendReturnPendingIntent(Context context, QuestionnaireExporter.ExportResult export, QuestionnaireData.SessionRecord record) throws PendingIntent.CanceledException {
        Intent fillIn = new Intent();
        addCompletionExtras(fillIn, export, record);
        returnPendingIntent.send(context, 0, fillIn);
    }

    private void addCompletionExtras(Intent target, QuestionnaireExporter.ExportResult export, QuestionnaireData.SessionRecord record) {
        target.putExtra(EXTRA_HANDOFF_SCHEMA, HANDOFF_SCHEMA_V1);
        target.putExtra(EXTRA_RESULT_STATUS, "complete");
        target.putExtra(EXTRA_TRIGGER_ID, triggerId);
        target.putExtra(EXTRA_QUESTIONNAIRE_SEQUENCE, record.questionnaireSequence);
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

    private static List<String> sequenceValue(Intent intent, String extraName, String queryName) {
        List<String> values = new ArrayList<>();
        String raw = value(intent, extraName, queryName);
        if (TextUtils.isEmpty(raw)) {
            return values;
        }
        for (String part : raw.split(",")) {
            String cleaned = clean(part);
            if (!TextUtils.isEmpty(cleaned)) {
                values.add(cleaned);
            }
        }
        return values;
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
        if (MODE_NONE.equals(cleaned)
            || MODE_DEMOGRAPHICS.equals(cleaned)
            || MODE_BASELINE.equals(cleaned)
            || MODE_PICTOGRAPHIC.equals(cleaned)
            || MODE_MAIA2.equals(cleaned)
            || MODE_SLIDER.equals(cleaned)
            || MODE_TEMPORAL_TRACER.equals(cleaned)
            || MODE_FULL.equals(cleaned)) {
            return cleaned;
        }
        return MODE_FULL;
    }

    private static List<String> normalizeQuestionnaireSequence(List<String> rawSequence, String fallbackMode) {
        List<String> sequence = new ArrayList<>();
        if (rawSequence != null) {
            for (String module : rawSequence) {
                appendModule(sequence, module);
            }
        }
        if (!sequence.isEmpty()) {
            return sequence;
        }
        return sequenceForMode(fallbackMode);
    }

    private static List<String> sequenceForMode(String mode) {
        List<String> sequence = new ArrayList<>();
        String cleaned = normalizeQuestionnaireMode(mode);
        if (MODE_NONE.equals(cleaned)) {
            return sequence;
        } else if (MODE_DEMOGRAPHICS.equals(cleaned)) {
            sequence.add(MODULE_DEMOGRAPHICS);
        } else if (MODE_BASELINE.equals(cleaned)) {
            sequence.add(MODULE_DEMOGRAPHICS);
            sequence.add(MODULE_MAIA2);
        } else if (MODE_MAIA2.equals(cleaned)) {
            sequence.add(MODULE_MAIA2);
        } else if (MODE_PICTOGRAPHIC.equals(cleaned)) {
            sequence.add(MODULE_PICTOGRAPHIC);
        } else if (MODE_SLIDER.equals(cleaned)) {
            sequence.add(MODULE_SLIDER);
        } else if (MODE_TEMPORAL_TRACER.equals(cleaned)) {
            sequence.add(MODULE_TEMPORAL_TRACER);
        } else {
            sequence.add(MODULE_DEMOGRAPHICS);
            sequence.add(MODULE_MAIA2);
            sequence.add(MODULE_PICTOGRAPHIC);
            sequence.add(MODULE_SLIDER);
            sequence.add(MODULE_TEMPORAL_TRACER);
        }
        return sequence;
    }

    private static void appendModule(List<String> sequence, String module) {
        String cleaned = clean(module);
        if (MODE_BASELINE.equals(cleaned)) {
            appendModule(sequence, MODULE_DEMOGRAPHICS);
            appendModule(sequence, MODULE_MAIA2);
            return;
        }
        if (MODE_FULL.equals(cleaned)) {
            appendModule(sequence, MODULE_DEMOGRAPHICS);
            appendModule(sequence, MODULE_MAIA2);
            appendModule(sequence, MODULE_PICTOGRAPHIC);
            appendModule(sequence, MODULE_SLIDER);
            appendModule(sequence, MODULE_TEMPORAL_TRACER);
            return;
        }
        if ((MODULE_DEMOGRAPHICS.equals(cleaned)
            || MODULE_MAIA2.equals(cleaned)
            || MODULE_PICTOGRAPHIC.equals(cleaned)
            || MODULE_SLIDER.equals(cleaned)
            || MODULE_TEMPORAL_TRACER.equals(cleaned))
            && !sequence.contains(cleaned)) {
            sequence.add(cleaned);
        }
    }

    private static List<String> firstNonEmptyList(List<String> values, List<String> fallback) {
        return values != null && !values.isEmpty() ? values : fallback;
    }

    private static String firstNonEmpty(String value, String fallback) {
        return TextUtils.isEmpty(clean(value)) ? clean(fallback) : clean(value);
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }
}
