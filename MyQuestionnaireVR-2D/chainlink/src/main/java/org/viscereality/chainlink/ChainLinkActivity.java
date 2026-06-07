package org.viscereality.chainlink;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.BaseBundle;
import android.os.Bundle;
import android.util.Base64;
import android.util.Log;
import android.view.Gravity;
import android.view.KeyEvent;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

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
import java.util.Locale;
import java.util.TimeZone;
import java.util.UUID;

public final class ChainLinkActivity extends Activity {
    public static final String TAG = "ViscerealityChainLink";
    public static final String ACTION_RUN = "org.viscereality.chainlink.RUN";
    public static final String ACTION_COMMAND = "org.viscereality.chainlink.COMMAND";
    private static final String QUESTIONNAIRE_ACTION = "org.viscereality.questionnaires2d.RUN";
    private static final String TEMPORAL_TRACER_PACKAGE = "org.viscereality.temporaltracer2d";
    private static final String TEMPORAL_TRACER_ACTIVITY = "org.viscereality.temporaltracer2d.MainActivity";
    private static final String TEMPORAL_TRACER_ACTION = "org.viscereality.temporaltracer2d.RUN";
    private static final String EXTRA_COMMAND = "mq.command";
    private static final String EXTRA_TRIGGER_ID = "mq.triggerId";
    private static final String EXTRA_RETURN_PENDING_INTENT = "mq.returnPendingIntent";
    private static final String EXTRA_HANDOFF_SCHEMA = "mq.handoffSchema";
    private static final String EXTRA_PLAN_JSON = "mq.chainPlanJson";
    private static final String EXTRA_PLAN_BASE64 = "mq.chainPlanBase64";
    private static final String EXTRA_PLAN_PATH = "mq.chainPlanPath";
    private static final String EXTRA_RESULT_STATUS = "mq.resultStatus";
    private static final String COMMAND_START_PLAN = "startPlan";
    private static final String COMMAND_NEXT_BLOCK = "nextBlock";
    private static final String COMMAND_TRIGGER = "trigger";
    private static final String COMMAND_TRIGGER_COMPLETE = "triggerComplete";
    private static final String COMMAND_LAUNCH_APP = "launchApp";
    private static final String COMMAND_CLEAR = "clear";
    private static final String COMMAND_STATUS = "status";
    private static final String FOLDER_NAME = "ChainLink";
    private static final String STATE_FILE_NAME = "chainlink-state.json";
    private static final String EVENTS_FILE_NAME = "chainlink-events.jsonl";

    private JSONObject activePlan;
    private JSONObject activeContextExtras = new JSONObject();
    private String activeChainId = "";
    private int currentStepIndex = -1;
    private TextView statusText;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        showPanel();
        handleIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIntent(intent);
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (event.getAction() == KeyEvent.ACTION_DOWN && isControllerTrigger(event)) {
            try {
                appendEvent("controller-trigger", "keyCode=" + event.getKeyCode() + " keyName=" + KeyEvent.keyCodeToString(event.getKeyCode()), getIntent(), null);
                continuePlan(getIntent());
                return true;
            } catch (Exception exception) {
                showStatus("Controller trigger failed: " + exception.getMessage());
                Log.e(TAG, "CHAINLINK_CONTROLLER_TRIGGER_FAILED " + exception.getMessage(), exception);
            }
        }
        return super.dispatchKeyEvent(event);
    }

    private void showPanel() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(dp(32), dp(24), dp(32), dp(24));
        root.setBackgroundColor(0xff12151c);

        TextView title = new TextView(this);
        title.setText("ChainLink");
        title.setTextColor(0xfff5f8fa);
        title.setTextSize(30);
        title.setGravity(Gravity.LEFT);
        root.addView(title);

        statusText = new TextView(this);
        statusText.setTextColor(0xffc8d0dc);
        statusText.setTextSize(18);
        statusText.setPadding(0, dp(16), 0, dp(16));
        root.addView(statusText);

        LinearLayout buttons = new LinearLayout(this);
        buttons.setOrientation(LinearLayout.HORIZONTAL);
        buttons.setGravity(Gravity.LEFT);
        Button next = button("Next block");
        next.setOnClickListener(view -> handleCommandButton(COMMAND_NEXT_BLOCK));
        Button status = button("Status");
        status.setOnClickListener(view -> handleCommandButton(COMMAND_STATUS));
        buttons.addView(next);
        buttons.addView(status);
        root.addView(buttons);

        ScrollView scroll = new ScrollView(this);
        TextView note = new TextView(this);
        note.setTextColor(0xffaeb8c8);
        note.setTextSize(16);
        note.setText("ChainLink starts APK blocks with Android intents. Controller buttons are received here only while this panel has focus; immersive scenarios should forward their controller event to ChainLink with the COMMAND intent.");
        scroll.addView(note);
        root.addView(scroll, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));
        setContentView(root);
        showStatus("Ready");
    }

    private Button button(String text) {
        Button button = new Button(this);
        button.setText(text);
        button.setAllCaps(false);
        button.setTextSize(18);
        button.setMinHeight(dp(56));
        return button;
    }

    private void handleCommandButton(String command) {
        Intent intent = new Intent(getIntent());
        intent.putExtra(EXTRA_COMMAND, command);
        handleIntent(intent);
    }

    private void handleIntent(Intent intent) {
        try {
            String command = commandFromIntent(intent);
            appendEvent("command", command, intent, null);
            if (COMMAND_START_PLAN.equals(command)) {
                startPlan(intent);
            } else if (COMMAND_NEXT_BLOCK.equals(command)) {
                continuePlan(intent);
            } else if (COMMAND_TRIGGER.equals(command)) {
                routeTrigger(intent);
            } else if (COMMAND_TRIGGER_COMPLETE.equals(command)) {
                completeTriggerBlock(intent);
            } else if (COMMAND_LAUNCH_APP.equals(command)) {
                launchDirect(intent);
            } else if (COMMAND_CLEAR.equals(command)) {
                clearState();
                showStatus("State cleared");
            } else {
                loadStateIfPresent();
                showStatus(stateSummary("Status"));
            }
        } catch (Exception exception) {
            showStatus("ChainLink error: " + exception.getMessage());
            Log.e(TAG, "CHAINLINK_ERROR " + exception.getMessage(), exception);
        }
    }

    private void startPlan(Intent intent) throws IOException, JSONException {
        activePlan = readPlan(intent);
        activeChainId = firstNonBlank(extra(intent, "mq.chainId"), activePlan.optString("chainId", ""), newRunId());
        activeContextExtras = persistentContextExtras(intent);
        currentStepIndex = -1;
        writeState("running", null);
        appendEvent("plan-start", activeChainId, intent, null);
        continuePlan(intent);
    }

    private void continuePlan(Intent triggerIntent) throws IOException, JSONException {
        loadStateIfPresent();
        if (activePlan == null) {
            showStatus("No active plan. Launch with mq.command=startPlan and mq.chainPlanJson/path.");
            appendEvent("no-active-plan", "", triggerIntent, null);
            return;
        }
        mergePersistentContextExtras(triggerIntent);

        JSONArray steps = activePlan.optJSONArray("steps");
        if (steps == null) {
            showStatus("Active plan has no steps.");
            appendEvent("plan-invalid", "missing-steps", triggerIntent, null);
            return;
        }

        int nextStep = currentStepIndex + 1;
        if (nextStep >= steps.length()) {
            currentStepIndex = steps.length() - 1;
            writeState("complete", resultJson(triggerIntent));
            appendEvent("plan-complete", activeChainId, triggerIntent, null);
            showStatus("Plan complete: " + activeChainId);
            return;
        }

        JSONObject step = steps.optJSONObject(nextStep);
        if (step == null) {
            showStatus("Invalid step " + nextStep);
            appendEvent("step-invalid", Integer.toString(nextStep), triggerIntent, null);
            return;
        }

        currentStepIndex = nextStep;
        writeState("running", resultJson(triggerIntent));
        Intent launch = intentForStep(step, triggerIntent);
        appendEvent("launch-step", step.optString("id", "step-" + nextStep), triggerIntent, step);
        showStatus("Launching block " + step.optString("blockNumber", blockNumber(nextStep)) + ": " + step.optString("id", ""));
        startActivity(launch);
    }

    private void completeTriggerBlock(Intent intent) throws IOException, JSONException {
        loadStateIfPresent();
        writeState("waitingForTrigger", resultJson(intent));
        appendEvent("trigger-complete", extra(intent, EXTRA_TRIGGER_ID), intent, null);
        if (returnToTriggerSource(intent)) {
            showStatus("Trigger block complete. Returning to source app.");
            return;
        }
        showStatus("Trigger block complete. Waiting for next trigger.");
    }

    private void routeTrigger(Intent intent) throws IOException, JSONException {
        loadStateIfPresent();
        if (activePlan == null && hasPlanPayload(intent)) {
            activePlan = readPlan(intent);
            activeChainId = firstNonBlank(extra(intent, "mq.chainId"), activePlan.optString("chainId", ""), newRunId());
            activeContextExtras = persistentContextExtras(intent);
            currentStepIndex = -1;
            writeState("running", null);
            appendEvent("plan-start", activeChainId, intent, null);
        }
        if (activePlan == null) {
            showStatus("No active plan. Trigger routing needs mq.chainPlanJson/path/base64 or a started plan.");
            appendEvent("trigger-no-active-plan", extra(intent, EXTRA_TRIGGER_ID), intent, null);
            return;
        }

        mergePersistentContextExtras(intent);
        String triggerId = firstNonBlank(extra(intent, EXTRA_TRIGGER_ID), query(intent, "triggerId"));
        if (isBlank(triggerId)) {
            showStatus("Trigger command is missing mq.triggerId.");
            appendEvent("trigger-invalid", "missing-trigger-id", intent, null);
            return;
        }

        JSONArray steps = activePlan.optJSONArray("steps");
        if (steps == null) {
            showStatus("Active plan has no steps.");
            appendEvent("plan-invalid", "missing-steps", intent, null);
            return;
        }

        int match = findStepForTrigger(steps, triggerId, currentStepIndex + 1);
        if (match < 0) {
            match = findStepForTrigger(steps, triggerId, 0);
        }
        if (match < 0) {
            showStatus("No block mapped for trigger: " + triggerId);
            appendEvent("trigger-unmapped", triggerId, intent, null);
            return;
        }

        JSONObject step = steps.optJSONObject(match);
        currentStepIndex = match - 1;
        writeState("running", null);
        appendEvent("trigger-route", triggerId, intent, step);
        continuePlan(intent);
    }

    private void launchDirect(Intent intent) throws JSONException, IOException {
        JSONObject step = new JSONObject();
        step.put("id", "direct-launch");
        step.put("type", "scenario");
        step.put("package", firstNonBlank(extra(intent, "mq.targetPackage"), extra(intent, "targetPackage")));
        step.put("activity", firstNonBlank(extra(intent, "mq.targetActivity"), extra(intent, "targetActivity")));
        step.put("action", firstNonBlank(extra(intent, "mq.targetAction"), extra(intent, "targetAction")));
        Intent launch = intentForStep(step, intent);
        appendEvent("direct-launch", step.optString("package", ""), intent, step);
        showStatus("Launching " + step.optString("package", ""));
        startActivity(launch);
    }

    private Intent intentForStep(JSONObject step, Intent triggerIntent) throws JSONException {
        String type = step.optString("type", "");
        String packageName = step.optString("package", "");
        String activityValue = step.optString("activity", "");
        String action = step.optString("action", "");
        if ("temporalTracer".equals(type)) {
            packageName = firstNonBlank(packageName, TEMPORAL_TRACER_PACKAGE);
            activityValue = firstNonBlank(activityValue, TEMPORAL_TRACER_ACTIVITY);
            action = firstNonBlank(action, TEMPORAL_TRACER_ACTION);
        }
        String activityName = normalizeActivity(packageName, activityValue);

        Intent intent;
        if (!isBlank(activityName)) {
            intent = isBlank(action) ? new Intent() : new Intent(action);
            intent.setClassName(packageName, activityName);
        } else if (!isBlank(packageName)) {
            intent = getPackageManager().getLaunchIntentForPackage(packageName);
            if (intent == null) {
                intent = isBlank(action) ? new Intent(Intent.ACTION_MAIN) : new Intent(action);
                intent.setPackage(packageName);
            }
        } else if (!isBlank(action)) {
            intent = new Intent(action);
        } else {
            throw new JSONException("Step has no package, activity, or action: " + step.optString("id", ""));
        }

        if (Intent.ACTION_MAIN.equals(intent.getAction())) {
            intent.addCategory(Intent.CATEGORY_LAUNCHER);
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        if ("questionnaire".equals(type) && isBlank(intent.getAction())) {
            intent.setAction(QUESTIONNAIRE_ACTION);
        }

        copyJsonExtras(intent, activeContextExtras);
        copyMqExtras(triggerIntent, intent);
        JSONObject extras = step.optJSONObject("extras");
        if (extras != null) {
            copyJsonExtras(intent, extras);
        }
        intent.putExtra("mq.chainId", activeChainId);
        intent.putExtra("mq.chainStepIndex", currentStepIndex);
        intent.putExtra("mq.chainStepId", step.optString("id", blockNumber(currentStepIndex)));
        intent.putExtra("mq.callerPackage", getPackageName());
        intent.putExtra("mq.callerActivity", getClass().getName());
        if ("questionnaire".equals(type) || "temporalTracer".equals(type)) {
            intent.putExtra(EXTRA_HANDOFF_SCHEMA, "mq.handoff.v1");
            intent.putExtra(EXTRA_RETURN_PENDING_INTENT, returnPendingIntentForCurrentStep(step));
        }
        if (!intent.hasExtra("mq.finishBehavior") && "questionnaire".equals(type)) {
            intent.putExtra("mq.finishBehavior", "resumeCaller");
        }
        return intent;
    }

    private PendingIntent returnPendingIntentForCurrentStep(JSONObject step) {
        Intent callback = new Intent(ACTION_COMMAND);
        callback.setClassName(getPackageName(), getClass().getName());
        callback.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        callback.putExtra(EXTRA_COMMAND, isTriggerRoutedStep(step) ? COMMAND_TRIGGER_COMPLETE : COMMAND_NEXT_BLOCK);
        callback.putExtra("mq.returnTarget", "chainlink");
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 31) {
            flags |= PendingIntent.FLAG_MUTABLE;
        }
        return PendingIntent.getActivity(this, (activeChainId + ":" + currentStepIndex).hashCode(), callback, flags);
    }

    private void loadStateIfPresent() throws IOException, JSONException {
        File file = stateFile();
        if (!file.exists()) {
            return;
        }
        JSONObject state = new JSONObject(new String(Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8));
        activePlan = state.optJSONObject("plan");
        JSONObject contextExtras = state.optJSONObject("contextExtras");
        activeContextExtras = contextExtras != null ? contextExtras : new JSONObject();
        activeChainId = state.optString("chainId", "");
        currentStepIndex = state.optInt("currentStepIndex", -1);
    }

    private void writeState(String status, JSONObject result) throws IOException, JSONException {
        JSONObject state = new JSONObject();
        state.put("schemaVersion", "viscereality.chainlink.state.v1");
        state.put("chainId", activeChainId);
        state.put("currentStepIndex", currentStepIndex);
        state.put("status", status);
        state.put("updatedUtc", utcIsoNow());
        state.put("plan", activePlan);
        state.put("contextExtras", activeContextExtras);
        if (result != null && result.length() > 0) {
            state.put("lastResult", result);
        }
        atomicWriteUtf8(stateFile(), state.toString(2));
    }

    private void clearState() throws IOException {
        File file = stateFile();
        if (file.exists() && !file.delete()) {
            throw new IOException("Could not delete " + file);
        }
        activePlan = null;
        activeContextExtras = new JSONObject();
        activeChainId = "";
        currentStepIndex = -1;
    }

    private JSONObject readPlan(Intent intent) throws IOException, JSONException {
        String json = firstNonBlank(extra(intent, EXTRA_PLAN_JSON), query(intent, "chainPlanJson"));
        if (isBlank(json)) {
            String encoded = firstNonBlank(extra(intent, EXTRA_PLAN_BASE64), query(intent, "chainPlanBase64"));
            if (!isBlank(encoded)) {
                json = new String(Base64.decode(encoded, Base64.DEFAULT), StandardCharsets.UTF_8);
            }
        }
        if (isBlank(json)) {
            String path = firstNonBlank(extra(intent, EXTRA_PLAN_PATH), query(intent, "chainPlanPath"));
            if (!isBlank(path)) {
                json = new String(Files.readAllBytes(new File(path).toPath()), StandardCharsets.UTF_8);
            }
        }
        if (isBlank(json)) {
            throw new JSONException("Missing chain plan JSON/base64/path");
        }
        return new JSONObject(json);
    }

    private String commandFromIntent(Intent intent) {
        String command = firstNonBlank(extra(intent, EXTRA_COMMAND), query(intent, "command"));
        if (!isBlank(command)) {
            return command;
        }
        if (!isBlank(extra(intent, EXTRA_TRIGGER_ID)) || !isBlank(query(intent, "triggerId"))) {
            return COMMAND_TRIGGER;
        }
        if ("complete".equals(extra(intent, EXTRA_RESULT_STATUS))) {
            return COMMAND_NEXT_BLOCK;
        }
        if (!isBlank(extra(intent, EXTRA_PLAN_JSON)) || !isBlank(extra(intent, EXTRA_PLAN_PATH)) || !isBlank(extra(intent, EXTRA_PLAN_BASE64))) {
            return COMMAND_START_PLAN;
        }
        return COMMAND_STATUS;
    }

    private boolean isControllerTrigger(KeyEvent event) {
        int code = event.getKeyCode();
        return code == KeyEvent.KEYCODE_BUTTON_L1
            || code == KeyEvent.KEYCODE_BUTTON_L2
            || code == KeyEvent.KEYCODE_BUTTON_THUMBL
            || code == KeyEvent.KEYCODE_BUTTON_X
            || code == KeyEvent.KEYCODE_BUTTON_Y;
    }

    private void appendEvent(String event, String value, Intent intent, JSONObject step) throws IOException, JSONException {
        JSONObject json = new JSONObject();
        json.put("timestampUtc", utcIsoNow());
        json.put("event", event);
        json.put("value", value == null ? "" : value);
        json.put("chainId", activeChainId);
        json.put("currentStepIndex", currentStepIndex);
        json.put("intentAction", intent != null ? intent.getAction() : "");
        json.put("intentComponent", intent != null && intent.getComponent() != null ? intent.getComponent().flattenToString() : "");
        if (step != null) {
            json.put("stepId", step.optString("id", ""));
            json.put("blockNumber", step.optString("blockNumber", ""));
            json.put("targetPackage", step.optString("package", ""));
            json.put("targetActivity", step.optString("activity", ""));
        }
        File log = new File(chainLinkFolder(), EVENTS_FILE_NAME);
        try (FileOutputStream output = new FileOutputStream(log, true)) {
            output.write((json.toString() + System.lineSeparator()).getBytes(StandardCharsets.UTF_8));
            output.getFD().sync();
        }
        Log.i(TAG, "CHAINLINK_EVENT " + event + " value=" + value);
    }

    private JSONObject resultJson(Intent intent) throws JSONException {
        JSONObject json = new JSONObject();
        if (intent == null || intent.getExtras() == null) {
            return json;
        }
        BaseBundle extras = intent.getExtras();
        for (String key : extras.keySet()) {
            if (key != null && (key.startsWith("mq.result") || key.startsWith("mq.export") || key.startsWith("mq.combined") || key.equals("mq.runId") || key.equals("mq.triggerId") || key.equals("mq.timestampUtc") || key.equals("mq.tracerConfigId") || key.equals("mq.questionnaireConfigId"))) {
                Object value = extras.get(key);
                if (value != null) {
                    json.put(key, String.valueOf(value));
                }
            }
        }
        return json;
    }

    private void copyMqExtras(Intent from, Intent to) {
        if (from == null || from.getExtras() == null) {
            return;
        }
        Bundle extras = from.getExtras();
        for (String key : extras.keySet()) {
            if (key == null || !key.startsWith("mq.") || to.hasExtra(key) || EXTRA_COMMAND.equals(key) || EXTRA_PLAN_JSON.equals(key) || EXTRA_PLAN_BASE64.equals(key) || EXTRA_PLAN_PATH.equals(key)) {
                continue;
            }
            putExtra(to, key, extras.get(key));
        }
    }

    private JSONObject persistentContextExtras(Intent intent) throws JSONException {
        JSONObject json = new JSONObject();
        if (intent == null || intent.getExtras() == null) {
            return json;
        }
        Bundle extras = intent.getExtras();
        for (String key : extras.keySet()) {
            if (isPersistentContextExtra(key)) {
                Object value = extras.get(key);
                if (value != null) {
                    json.put(key, String.valueOf(value));
                }
            }
        }
        return json;
    }

    private void mergePersistentContextExtras(Intent intent) throws JSONException {
        JSONObject latest = persistentContextExtras(intent);
        Iterator<String> keys = latest.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            activeContextExtras.put(key, latest.opt(key));
        }
    }

    private boolean isPersistentContextExtra(String key) {
        return "mq.sessionId".equals(key)
            || "mq.experimentId".equals(key)
            || "mq.scenarioId".equals(key)
            || "mq.trialId".equals(key)
            || "mq.participantId".equals(key)
            || "mq.participantName".equals(key)
            || "mq.language".equals(key)
            || "mq.sourcePackage".equals(key)
            || "mq.sourceActivity".equals(key)
            || "mq.callerPackage".equals(key)
            || "mq.callerActivity".equals(key);
    }

    private boolean returnToTriggerSource(Intent completedIntent) throws IOException, JSONException {
        String packageName = firstNonBlank(
            extra(completedIntent, "mq.sourcePackage"),
            activeContextExtras.optString("mq.sourcePackage", ""),
            activeContextExtras.optString("mq.callerPackage", ""));
        String activityName = firstNonBlank(
            extra(completedIntent, "mq.sourceActivity"),
            activeContextExtras.optString("mq.sourceActivity", ""),
            activeContextExtras.optString("mq.callerActivity", ""));
        if (isBlank(packageName)) {
            appendEvent("trigger-source-missing", extra(completedIntent, EXTRA_TRIGGER_ID), completedIntent, null);
            return false;
        }

        Intent source = new Intent();
        if (!isBlank(activityName)) {
            source.setClassName(packageName, normalizeActivity(packageName, activityName));
        } else {
            Intent launch = getPackageManager().getLaunchIntentForPackage(packageName);
            if (launch == null) {
                appendEvent("trigger-source-missing", packageName, completedIntent, null);
                return false;
            }
            source = launch;
        }
        source.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        copyMqExtras(completedIntent, source);
        source.putExtra("mq.returnTarget", "triggerSource");
        appendEvent("trigger-return-source", packageName, completedIntent, null);
        startActivity(source);
        return true;
    }

    private boolean hasPlanPayload(Intent intent) {
        return !isBlank(extra(intent, EXTRA_PLAN_JSON))
            || !isBlank(extra(intent, EXTRA_PLAN_PATH))
            || !isBlank(extra(intent, EXTRA_PLAN_BASE64))
            || !isBlank(query(intent, "chainPlanJson"))
            || !isBlank(query(intent, "chainPlanPath"))
            || !isBlank(query(intent, "chainPlanBase64"));
    }

    private boolean isTriggerRoutedStep(JSONObject step) {
        JSONObject trigger = step != null ? step.optJSONObject("trigger") : null;
        return trigger != null && "apkManifestTrigger".equals(trigger.optString("type", ""));
    }

    private int findStepForTrigger(JSONArray steps, String triggerId, int startIndex) {
        String wanted = triggerId.trim();
        for (int i = Math.max(0, startIndex); i < steps.length(); i++) {
            JSONObject step = steps.optJSONObject(i);
            if (step != null && stepMatchesTrigger(step, wanted)) {
                return i;
            }
        }
        return -1;
    }

    private boolean stepMatchesTrigger(JSONObject step, String triggerId) {
        if (triggerId.equals(step.optString("triggerId", "")) || triggerId.equals(step.optString("id", ""))) {
            return true;
        }
        JSONObject trigger = step.optJSONObject("trigger");
        if (trigger != null && (triggerId.equals(trigger.optString("triggerId", "")) || triggerId.equals(trigger.optString("id", "")))) {
            return true;
        }
        JSONObject extras = step.optJSONObject("extras");
        return extras != null && triggerId.equals(extras.optString(EXTRA_TRIGGER_ID, ""));
    }

    private void copyJsonExtras(Intent intent, JSONObject extras) {
        Iterator<String> keys = extras.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            putExtra(intent, key, extras.opt(key));
        }
    }

    private void putExtra(Intent intent, String key, Object value) {
        if (value == null || JSONObject.NULL.equals(value)) {
            return;
        }
        if (value instanceof Boolean) {
            intent.putExtra(key, (Boolean) value);
        } else if (value instanceof Integer) {
            intent.putExtra(key, (Integer) value);
        } else if (value instanceof Long) {
            intent.putExtra(key, (Long) value);
        } else if (value instanceof Number) {
            intent.putExtra(key, String.valueOf(value));
        } else {
            intent.putExtra(key, String.valueOf(value));
        }
    }

    private File chainLinkFolder() throws IOException {
        File base = getExternalFilesDir(null);
        if (base == null) {
            base = getFilesDir();
        }
        File folder = new File(base, FOLDER_NAME);
        if (!folder.exists() && !folder.mkdirs()) {
            throw new IOException("Could not create " + folder);
        }
        return folder;
    }

    private File stateFile() throws IOException {
        return new File(chainLinkFolder(), STATE_FILE_NAME);
    }

    private void atomicWriteUtf8(File file, String value) throws IOException {
        File temp = new File(file.getParentFile(), file.getName() + ".tmp");
        try (FileOutputStream output = new FileOutputStream(temp)) {
            output.write(value.getBytes(StandardCharsets.UTF_8));
            output.getFD().sync();
        }
        if (file.exists() && !file.delete()) {
            throw new IOException("Could not replace " + file);
        }
        if (!temp.renameTo(file)) {
            throw new IOException("Could not move " + temp + " to " + file);
        }
    }

    private void showStatus(String text) {
        if (statusText != null) {
            statusText.setText(text);
        }
    }

    private String stateSummary(String prefix) {
        return prefix + "\nchainId=" + activeChainId + "\ncurrentStepIndex=" + currentStepIndex;
    }

    private String extra(Intent intent, String key) {
        return intent != null ? clean(intent.getStringExtra(key)) : "";
    }

    private String query(Intent intent, String key) {
        if (intent == null) {
            return "";
        }
        Uri data = intent.getData();
        return data != null ? clean(data.getQueryParameter(key)) : "";
    }

    private String normalizeActivity(String packageName, String activityName) {
        String cleaned = clean(activityName);
        if (cleaned.startsWith(".")) {
            return packageName + cleaned;
        }
        return cleaned;
    }

    private String firstNonBlank(String... values) {
        for (String value : values) {
            if (!isBlank(value)) {
                return clean(value);
            }
        }
        return "";
    }

    private String blockNumber(int index) {
        return String.format(Locale.US, "%03d", index + 1);
    }

    private String newRunId() {
        String uuid = UUID.randomUUID().toString().replace("-", "").substring(0, 8);
        return new SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(new Date()) + "_" + uuid;
    }

    private String utcIsoNow() {
        SimpleDateFormat format = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
        format.setTimeZone(TimeZone.getTimeZone("UTC"));
        return format.format(new Date());
    }

    private String clean(String value) {
        return value == null ? "" : value.trim();
    }

    private boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
