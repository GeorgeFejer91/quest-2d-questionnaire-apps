package org.mesmerprism.viscereality.orchestrator;

import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ResolveInfo;
import android.net.Uri;
import android.os.Bundle;
import android.util.Base64;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;
import java.util.UUID;

final class ExperimentOrchestratorBroker {
    static final String TAG = "ViscerealityOrchestrator";
    static final String ACTION_BROKER = "org.mesmerprism.viscereality.orchestrator.BROKER";
    static final String ACTION_CHAIN_HOOK = "org.mesmerprism.viscereality.CHAIN_COMMAND";
    static final String ACTION_QUESTIONNAIRE_RUN = "org.mesmerprism.viscereality.questionnaires2d.RUN";
    static final String QUESTIONNAIRE_PACKAGE = "org.mesmerprism.viscereality.questionnaires2d";
    static final String QUESTIONNAIRE_ACTIVITY = "org.mesmerprism.viscereality.questionnaires2d.MainActivity";
    static final String ORCHESTRATOR_ACTIVITY = "org.mesmerprism.viscereality.orchestrator.ExperimentOrchestratorActivity";

    static final String EXTRA_BROKER_COMMAND = "mq.brokerCommand";
    static final String EXTRA_BROKER_ACTION = "mq.brokerAction";
    static final String EXTRA_BROKER_PACKAGE = "mq.brokerPackage";
    static final String EXTRA_BROKER_ACTIVITY = "mq.brokerActivity";
    static final String EXTRA_HOOK_COMMAND = "mq.hookCommand";
    static final String EXTRA_CHAIN_PLAN_JSON = "mq.chainPlanJson";
    static final String EXTRA_CHAIN_PLAN_BASE64 = "mq.chainPlanBase64";
    static final String EXTRA_CHAIN_PLAN_PATH = "mq.chainPlanPath";

    static final String COMMAND_START_PLAN = "startPlan";
    static final String COMMAND_CONTINUE_PLAN = "continuePlan";
    static final String COMMAND_CLEAR_PLAN = "clearPlan";
    static final String COMMAND_DISCOVER_HOOKS = "discoverHooks";
    static final String COMMAND_OPEN_APP = "openApp";
    static final String COMMAND_GO_HOME = "goHome";
    static final String COMMAND_PING = "ping";

    static final String EXTRA_SESSION_ID = "mq.sessionId";
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
    static final String EXTRA_AUTO_CLOSE_DELAY_MS = "mq.autoCloseDelayMs";
    static final String EXTRA_RESULT_STATUS = "mq.resultStatus";
    static final String EXTRA_RUN_ID = "mq.runId";
    static final String EXTRA_TIMESTAMP_UTC = "mq.timestampUtc";
    static final String EXTRA_EXPORT_JSON_PATH = "mq.exportJsonPath";
    static final String EXTRA_EXPORT_CSV_PATH = "mq.exportCsvPath";
    static final String EXTRA_QUESTIONNAIRE_CONFIG_ID = "mq.questionnaireConfigId";
    static final String EXTRA_SCENARIO_RESULT_STATUS = "mq.scenarioResultStatus";
    static final String EXTRA_SCENARIO_VERSION = "mq.scenarioVersion";
    static final String EXTRA_SCENARIO_PARTICIPANT_DATA_PATH = "mq.scenarioParticipantDataPath";

    private static final String FOLDER_NAME = "ExperimentOrchestrator";
    private static final String STATE_FILE_NAME = "orchestrator-state.json";
    private static final String HOOK_REGISTRY_FILE_NAME = "hook-registry.json";
    private static final String LOG_FILE_NAME = "orchestrator-events.jsonl";

    private ExperimentOrchestratorBroker() {
    }

    static Result handle(Context context, Intent intent) throws IOException, JSONException {
        String command = commandFromIntent(intent);
        appendEvent(context, "command", command, intent);

        if (COMMAND_START_PLAN.equals(command)) {
            return startPlan(context, intent);
        }
        if (COMMAND_CONTINUE_PLAN.equals(command)) {
            return continuePlan(context, intent);
        }
        if (COMMAND_CLEAR_PLAN.equals(command)) {
            clearState(context);
            return new Result(null, "cleared");
        }
        if (COMMAND_DISCOVER_HOOKS.equals(command)) {
            int hookCount = writeHookRegistry(context);
            return new Result(null, "hooks:" + hookCount);
        }
        if (COMMAND_OPEN_APP.equals(command)) {
            return openApp(context, intent);
        }
        if (COMMAND_GO_HOME.equals(command)) {
            return new Result(homeIntent(), "home");
        }
        return new Result(null, "pong");
    }

    private static Result startPlan(Context context, Intent intent) throws IOException, JSONException {
        JSONObject plan = readPlanFromIntent(intent);
        String chainId = firstNonBlank(
            stringValue(intent, EXTRA_CHAIN_ID, "chainId"),
            plan.optString("chainId", ""),
            newRunId());
        int stepIndex = intValue(intent, EXTRA_CHAIN_STEP_INDEX, "chainStepIndex", 0);
        writeState(context, plan, chainId, stepIndex, "running", resultJson(intent));
        return executeStep(context, plan, chainId, stepIndex, intent);
    }

    private static Result continuePlan(Context context, Intent intent) throws IOException, JSONException {
        State state = readState(context);
        if (state == null) {
            appendEvent(context, "complete-without-active-plan", "", intent);
            return new Result(null, "no-active-plan");
        }

        int nextStep = state.stepIndex + 1;
        JSONArray steps = state.plan.optJSONArray("steps");
        if (steps == null || nextStep >= steps.length()) {
            writeState(context, state.plan, state.chainId, state.stepIndex, "complete", resultJson(intent));
            appendEvent(context, "plan-complete", state.chainId, intent);
            return new Result(null, "plan-complete");
        }

        writeState(context, state.plan, state.chainId, nextStep, "running", resultJson(intent));
        return executeStep(context, state.plan, state.chainId, nextStep, intent);
    }

    private static Result openApp(Context context, Intent intent) throws JSONException {
        String packageName = firstNonBlank(stringValue(intent, "targetPackage", "targetPackage"), stringValue(intent, "mq.targetPackage", "targetPackage"));
        String activityName = firstNonBlank(stringValue(intent, "targetActivity", "targetActivity"), stringValue(intent, "mq.targetActivity", "targetActivity"));
        if (isBlank(packageName)) {
            return new Result(null, "missing-target-package");
        }
        Intent outgoing = appIntent(context, packageName, activityName, "");
        copyJsonExtras(outgoing, intentExtrasAsJson(intent));
        copyResultExtras(intent, outgoing);
        return new Result(outgoing, "app");
    }

    private static Result executeStep(Context context, JSONObject plan, String chainId, int stepIndex, Intent triggerIntent) throws JSONException {
        JSONArray steps = plan.optJSONArray("steps");
        if (steps == null || stepIndex < 0 || stepIndex >= steps.length()) {
            return new Result(null, "missing-step");
        }

        JSONObject step = steps.optJSONObject(stepIndex);
        if (step == null) {
            return new Result(null, "invalid-step");
        }

        String type = step.optString("type", "scenario");
        String stepId = step.optString("id", "step-" + stepIndex);
        String packageName = step.optString("package", "");
        String activityName = step.optString("activity", "");

        if ("questionnaire".equalsIgnoreCase(type)) {
            Intent outgoing = questionnaireIntent(context, packageName, activityName, chainId, stepIndex, stepId, triggerIntent, step);
            return new Result(outgoing, "questionnaire:" + stepId);
        }

        String action = step.optString("action", ACTION_CHAIN_HOOK);
        Intent outgoing = appIntent(context, packageName, activityName, action);
        String hookCommand = step.optString("command", "");
        if (!isBlank(hookCommand)) {
            outgoing.putExtra(EXTRA_HOOK_COMMAND, hookCommand);
        }
        outgoing.putExtra(EXTRA_BROKER_ACTION, ACTION_BROKER);
        outgoing.putExtra(EXTRA_BROKER_PACKAGE, context.getPackageName());
        outgoing.putExtra(EXTRA_BROKER_ACTIVITY, ORCHESTRATOR_ACTIVITY);
        JSONObject extras = step.optJSONObject("extras");
        if (extras != null) {
            copyJsonExtras(outgoing, extras);
        }
        copyResultExtras(triggerIntent, outgoing);
        outgoing.putExtra(EXTRA_CHAIN_ID, chainId);
        outgoing.putExtra(EXTRA_CHAIN_STEP_ID, stepId);
        outgoing.putExtra(EXTRA_CHAIN_STEP_INDEX, stepIndex);
        return new Result(outgoing, "app:" + stepId);
    }

    private static Intent questionnaireIntent(
        Context context,
        String packageName,
        String activityName,
        String chainId,
        int stepIndex,
        String stepId,
        Intent triggerIntent,
        JSONObject step) {

        String targetPackage = firstNonBlank(packageName, QUESTIONNAIRE_PACKAGE);
        String targetActivity = firstNonBlank(activityName, QUESTIONNAIRE_ACTIVITY);
        Intent outgoing = new Intent(ACTION_QUESTIONNAIRE_RUN);
        outgoing.setClassName(targetPackage, normalizeActivity(targetPackage, targetActivity));
        outgoing.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
        copyMqExtras(triggerIntent, outgoing);
        JSONObject extras = step != null ? step.optJSONObject("extras") : null;
        if (extras != null) {
            copyJsonExtras(outgoing, extras);
        }
        outgoing.putExtra(EXTRA_CHAIN_ID, chainId);
        outgoing.putExtra(EXTRA_CHAIN_STEP_ID, stepId);
        outgoing.putExtra(EXTRA_CHAIN_STEP_INDEX, stepIndex);
        putIfMissing(outgoing, EXTRA_FINISH_BEHAVIOR, "resumeCaller");
        putIfMissing(outgoing, EXTRA_CALLER_PACKAGE, context.getPackageName());
        putIfMissing(outgoing, EXTRA_CALLER_ACTIVITY, ORCHESTRATOR_ACTIVITY);
        return outgoing;
    }

    private static Intent appIntent(Context context, String packageName, String activityName, String action) {
        Intent outgoing;
        if (!isBlank(activityName)) {
            outgoing = isBlank(action) ? new Intent() : new Intent(action);
            outgoing.setClassName(packageName, normalizeActivity(packageName, activityName));
        } else if (!isBlank(action)) {
            outgoing = new Intent(action);
            outgoing.addCategory(Intent.CATEGORY_DEFAULT);
            if (!isBlank(packageName)) {
                outgoing.setPackage(packageName);
            }
            ComponentName hook = resolveHookActivity(context, packageName, action);
            if (hook != null) {
                outgoing.setComponent(hook);
            }
        } else {
            outgoing = context.getPackageManager().getLaunchIntentForPackage(packageName);
            if (outgoing == null) {
                outgoing = new Intent();
                outgoing.setPackage(packageName);
            }
        }
        outgoing.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
        return outgoing;
    }

    private static ComponentName resolveHookActivity(Context context, String packageName, String action) {
        Intent query = new Intent(action);
        query.addCategory(Intent.CATEGORY_DEFAULT);
        if (!isBlank(packageName)) {
            query.setPackage(packageName);
        }
        List<ResolveInfo> matches = context.getPackageManager().queryIntentActivities(query, 0);
        if (matches == null || matches.isEmpty()) {
            return null;
        }
        ResolveInfo first = matches.get(0);
        if (first.activityInfo == null) {
            return null;
        }
        return new ComponentName(first.activityInfo.packageName, first.activityInfo.name);
    }

    private static int writeHookRegistry(Context context) throws IOException, JSONException {
        JSONArray hooks = new JSONArray();
        Intent query = new Intent(ACTION_CHAIN_HOOK);
        List<ResolveInfo> matches = context.getPackageManager().queryIntentActivities(query, 0);
        if (matches != null) {
            for (ResolveInfo match : matches) {
                if (match.activityInfo == null) {
                    continue;
                }
                JSONObject hook = new JSONObject();
                hook.put("package", match.activityInfo.packageName);
                hook.put("activity", match.activityInfo.name);
                hook.put("action", ACTION_CHAIN_HOOK);
                hooks.put(hook);
            }
        }

        JSONObject root = new JSONObject();
        root.put("schemaVersion", "viscereality.orchestrator.hook-registry.v1");
        root.put("updatedUtc", utcIsoNow());
        root.put("hookCount", hooks.length());
        root.put("hooks", hooks);
        atomicWriteUtf8(new File(orchestratorFolder(context), HOOK_REGISTRY_FILE_NAME), root.toString(2));
        return hooks.length();
    }

    private static File orchestratorFolder(Context context) throws IOException {
        File base = context.getExternalFilesDir(null);
        if (base == null) {
            base = context.getFilesDir();
        }
        File folder = new File(base, FOLDER_NAME);
        if (!folder.exists() && !folder.mkdirs()) {
            throw new IOException("Could not create orchestrator folder: " + folder);
        }
        return folder;
    }

    private static File stateFile(Context context) throws IOException {
        return new File(orchestratorFolder(context), STATE_FILE_NAME);
    }

    private static JSONObject readPlanFromIntent(Intent intent) throws IOException, JSONException {
        String planJson = stringValue(intent, EXTRA_CHAIN_PLAN_JSON, "chainPlanJson");
        if (isBlank(planJson)) {
            String encoded = stringValue(intent, EXTRA_CHAIN_PLAN_BASE64, "chainPlanBase64");
            if (!isBlank(encoded)) {
                planJson = new String(Base64.decode(encoded, Base64.DEFAULT), StandardCharsets.UTF_8);
            }
        }
        if (isBlank(planJson)) {
            String path = stringValue(intent, EXTRA_CHAIN_PLAN_PATH, "chainPlanPath");
            if (!isBlank(path)) {
                planJson = new String(Files.readAllBytes(new File(path).toPath()), StandardCharsets.UTF_8);
            }
        }
        if (isBlank(planJson)) {
            throw new JSONException("startPlan requires mq.chainPlanJson, mq.chainPlanBase64, or mq.chainPlanPath");
        }
        return new JSONObject(planJson.trim());
    }

    private static State readState(Context context) throws IOException, JSONException {
        File file = stateFile(context);
        if (!file.exists()) {
            return null;
        }
        JSONObject root = new JSONObject(new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8));
        State state = new State();
        state.chainId = root.optString("chainId", "");
        state.stepIndex = root.optInt("currentStepIndex", -1);
        state.plan = root.optJSONObject("plan");
        return state.plan == null ? null : state;
    }

    private static void writeState(Context context, JSONObject plan, String chainId, int stepIndex, String status, JSONObject lastResult) throws IOException, JSONException {
        JSONObject state = new JSONObject();
        state.put("schemaVersion", "viscereality.orchestrator.state.v1");
        state.put("chainId", chainId);
        state.put("currentStepIndex", stepIndex);
        state.put("status", status);
        state.put("updatedUtc", utcIsoNow());
        state.put("plan", plan);
        if (lastResult != null && lastResult.length() > 0) {
            state.put("lastResult", lastResult);
        }
        atomicWriteUtf8(stateFile(context), state.toString(2));
    }

    private static void clearState(Context context) throws IOException {
        File file = stateFile(context);
        if (file.exists() && !file.delete()) {
            throw new IOException("Could not delete orchestrator state: " + file);
        }
    }

    private static void appendEvent(Context context, String event, String value, Intent intent) throws IOException, JSONException {
        JSONObject json = new JSONObject();
        json.put("timestampUtc", utcIsoNow());
        json.put("event", event);
        json.put("value", value);
        json.put("action", intent != null ? intent.getAction() : "");
        json.put("component", intent != null && intent.getComponent() != null ? intent.getComponent().flattenToString() : "");
        File log = new File(orchestratorFolder(context), LOG_FILE_NAME);
        try (FileOutputStream output = new FileOutputStream(log, true)) {
            output.write((json.toString() + System.lineSeparator()).getBytes(StandardCharsets.UTF_8));
            output.getFD().sync();
        }
    }

    private static void copyMqExtras(Intent from, Intent to) {
        if (from == null || from.getExtras() == null) {
            return;
        }
        Bundle extras = from.getExtras();
        for (String key : extras.keySet()) {
            if (key == null || !key.startsWith("mq.") || isBrokerOnlyExtra(key) || to.hasExtra(key)) {
                continue;
            }
            putExtraValue(to, key, extras.get(key));
        }
    }

    private static void copyResultExtras(Intent from, Intent to) {
        if (from == null || from.getExtras() == null) {
            return;
        }
        String[] keys = new String[] {
            EXTRA_RESULT_STATUS,
            EXTRA_RUN_ID,
            EXTRA_SESSION_ID,
            EXTRA_CHAIN_ID,
            EXTRA_CHAIN_STEP_ID,
            EXTRA_CHAIN_STEP_INDEX,
            EXTRA_TIMESTAMP_UTC,
            EXTRA_EXPORT_JSON_PATH,
            EXTRA_EXPORT_CSV_PATH,
            EXTRA_QUESTIONNAIRE_CONFIG_ID,
            EXTRA_SCENARIO_RESULT_STATUS,
            EXTRA_SCENARIO_VERSION,
            EXTRA_SCENARIO_PARTICIPANT_DATA_PATH
        };
        for (String key : keys) {
            if (from.hasExtra(key)) {
                putExtraValue(to, key, from.getExtras().get(key));
            }
        }
    }

    private static void copyJsonExtras(Intent to, JSONObject extras) {
        if (extras == null) {
            return;
        }
        Iterator<String> keys = extras.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            putExtraValue(to, key, extras.opt(key));
        }
    }

    private static JSONObject intentExtrasAsJson(Intent intent) throws JSONException {
        JSONObject json = new JSONObject();
        if (intent == null || intent.getExtras() == null) {
            return json;
        }
        Bundle extras = intent.getExtras();
        for (String key : extras.keySet()) {
            if (key != null && !isBrokerOnlyExtra(key)) {
                Object value = extras.get(key);
                if (value != null) {
                    json.put(key, String.valueOf(value));
                }
            }
        }
        return json;
    }

    private static JSONObject resultJson(Intent intent) throws JSONException {
        JSONObject json = new JSONObject();
        if (intent == null || intent.getExtras() == null) {
            return json;
        }
        Bundle extras = intent.getExtras();
        for (String key : extras.keySet()) {
            if (key != null && (EXTRA_RESULT_STATUS.equals(key)
                || EXTRA_RUN_ID.equals(key)
                || EXTRA_EXPORT_JSON_PATH.equals(key)
                || EXTRA_EXPORT_CSV_PATH.equals(key)
                || EXTRA_SCENARIO_RESULT_STATUS.equals(key)
                || EXTRA_SCENARIO_VERSION.equals(key)
                || EXTRA_SCENARIO_PARTICIPANT_DATA_PATH.equals(key))) {
                Object value = extras.get(key);
                if (value != null) {
                    json.put(key, String.valueOf(value));
                }
            }
        }
        return json;
    }

    private static void putExtraValue(Intent intent, String key, Object value) {
        if (value == null || JSONObject.NULL.equals(value)) {
            return;
        }
        if (value instanceof Boolean) {
            intent.putExtra(key, (Boolean) value);
        } else if (value instanceof Integer) {
            intent.putExtra(key, (Integer) value);
        } else if (value instanceof Long) {
            intent.putExtra(key, (Long) value);
        } else if (value instanceof Number && EXTRA_AUTO_CLOSE_DELAY_MS.equals(key)) {
            intent.putExtra(key, ((Number) value).longValue());
        } else if (value instanceof Number) {
            intent.putExtra(key, String.valueOf(value));
        } else {
            intent.putExtra(key, String.valueOf(value));
        }
    }

    private static void putIfMissing(Intent intent, String key, String value) {
        if (!intent.hasExtra(key) || isBlank(intent.getStringExtra(key))) {
            intent.putExtra(key, value);
        }
    }

    private static String commandFromIntent(Intent intent) {
        String command = stringValue(intent, EXTRA_BROKER_COMMAND, "command");
        if (!isBlank(command)) {
            return command;
        }
        if (intent != null && "complete".equals(intent.getStringExtra(EXTRA_RESULT_STATUS))) {
            return COMMAND_CONTINUE_PLAN;
        }
        if (!isBlank(stringValue(intent, EXTRA_CHAIN_PLAN_JSON, "chainPlanJson"))
            || !isBlank(stringValue(intent, EXTRA_CHAIN_PLAN_BASE64, "chainPlanBase64"))
            || !isBlank(stringValue(intent, EXTRA_CHAIN_PLAN_PATH, "chainPlanPath"))) {
            return COMMAND_START_PLAN;
        }
        return COMMAND_PING;
    }

    private static String stringValue(Intent intent, String extraName, String queryName) {
        if (intent == null) {
            return "";
        }
        String extra = intent.getStringExtra(extraName);
        if (!isBlank(extra)) {
            return extra;
        }
        Uri data = intent.getData();
        return data != null ? clean(data.getQueryParameter(queryName)) : "";
    }

    private static int intValue(Intent intent, String extraName, String queryName, int fallback) {
        if (intent == null) {
            return fallback;
        }
        if (intent.hasExtra(extraName) && intent.getExtras() != null) {
            Object raw = intent.getExtras().get(extraName);
            if (raw instanceof Number) {
                return ((Number) raw).intValue();
            }
            if (raw != null) {
                try {
                    return Integer.parseInt(String.valueOf(raw));
                } catch (NumberFormatException ignored) {
                    return fallback;
                }
            }
        }
        Uri data = intent.getData();
        if (data != null) {
            try {
                return Integer.parseInt(clean(data.getQueryParameter(queryName)));
            } catch (NumberFormatException ignored) {
                return fallback;
            }
        }
        return fallback;
    }

    private static boolean isBrokerOnlyExtra(String key) {
        return EXTRA_BROKER_COMMAND.equals(key)
            || EXTRA_BROKER_ACTION.equals(key)
            || EXTRA_BROKER_PACKAGE.equals(key)
            || EXTRA_BROKER_ACTIVITY.equals(key)
            || EXTRA_CHAIN_PLAN_JSON.equals(key)
            || EXTRA_CHAIN_PLAN_BASE64.equals(key)
            || EXTRA_CHAIN_PLAN_PATH.equals(key);
    }

    private static Intent homeIntent() {
        Intent home = new Intent(Intent.ACTION_MAIN);
        home.addCategory(Intent.CATEGORY_HOME);
        home.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return home;
    }

    private static String normalizeActivity(String packageName, String activityName) {
        String cleaned = clean(activityName);
        if (cleaned.startsWith(".")) {
            return packageName + cleaned;
        }
        return cleaned;
    }

    private static String firstNonBlank(String... values) {
        if (values == null) {
            return "";
        }
        for (String value : values) {
            if (!isBlank(value)) {
                return clean(value);
            }
        }
        return "";
    }

    private static void atomicWriteUtf8(File file, String value) throws IOException {
        File parent = file.getParentFile();
        if (parent != null && !parent.exists() && !parent.mkdirs()) {
            throw new IOException("Could not create folder: " + parent);
        }
        File temp = new File(parent, file.getName() + ".tmp");
        try (FileOutputStream output = new FileOutputStream(temp)) {
            output.write(value.getBytes(StandardCharsets.UTF_8));
            output.getFD().sync();
        }
        if (file.exists() && !file.delete()) {
            throw new IOException("Could not replace file: " + file);
        }
        if (!temp.renameTo(file)) {
            throw new IOException("Could not move temp file into place: " + temp);
        }
    }

    private static String newRunId() {
        String uuid = UUID.randomUUID().toString().replace("-", "").substring(0, 8);
        return new SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(new Date()) + "_" + uuid;
    }

    private static String utcIsoNow() {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date());
    }

    private static String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private static boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    static final class Result {
        final Intent outgoingIntent;
        final String status;

        Result(Intent outgoingIntent, String status) {
            this.outgoingIntent = outgoingIntent;
            this.status = status;
        }
    }

    private static final class State {
        String chainId;
        int stepIndex;
        JSONObject plan;
    }
}
