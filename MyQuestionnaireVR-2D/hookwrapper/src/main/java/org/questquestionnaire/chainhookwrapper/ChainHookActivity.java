package org.questquestionnaire.chainhookwrapper;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Gravity;
import android.widget.TextView;

public final class ChainHookActivity extends Activity {
    public static final String ACTION_CHAIN_COMMAND = "org.questquestionnaire.CHAIN_COMMAND";
    public static final String ACTION_BROKER = "org.questquestionnaire.questionnaires2d.BROKER";
    public static final String QUESTIONNAIRE_PACKAGE = "org.questquestionnaire.questionnaires2d";
    public static final String BROKER_ACTIVITY = "org.questquestionnaire.questionnaires2d.QuestChainBrokerActivity";
    public static final String TAG = "QuestQuestionnaireChainHook";

    private final Handler handler = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        showStatus("Chain hook");
        handleHook(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleHook(intent);
    }

    private void handleHook(Intent intent) {
        handler.removeCallbacksAndMessages(null);
        String hookCommand = stringExtra(intent, "mq.hookCommand", "launchTarget");
        String targetPackage = firstNonBlank(
            stringExtra(intent, "targetPackage", ""),
            stringExtra(intent, "mq.targetPackage", ""),
            stringExtra(intent, "target.package", ""));
        String targetActivity = firstNonBlank(
            stringExtra(intent, "targetActivity", ""),
            stringExtra(intent, "mq.targetActivity", ""),
            stringExtra(intent, "target.activity", ""));
        long autoContinueDelayMs = longExtra(intent, "mq.autoContinueDelayMs", longExtra(intent, "autoContinueDelayMs", -1L));

        Log.i(TAG, "CHAIN_HOOK_RECEIVED command=" + hookCommand
            + " targetPackage=" + targetPackage
            + " targetActivity=" + targetActivity
            + " autoContinueDelayMs=" + autoContinueDelayMs
            + " chainId=" + stringExtra(intent, "mq.chainId", ""));

        if ("continuePlan".equals(hookCommand)) {
            startBrokerContinue(intent);
            finish();
            return;
        }

        if (!isBlank(targetPackage)) {
            Intent target = targetIntent(targetPackage, targetActivity);
            copyChainExtras(intent, target);
            try {
                startActivity(target);
                Log.i(TAG, "CHAIN_HOOK_TARGET_STARTED component=" + target.getComponent() + " package=" + target.getPackage());
            } catch (Exception exception) {
                Log.e(TAG, "CHAIN_HOOK_TARGET_START_FAILED " + exception.getMessage(), exception);
            }
        } else {
            Log.w(TAG, "CHAIN_HOOK_TARGET_MISSING");
        }

        if (autoContinueDelayMs >= 0L) {
            handler.postDelayed(() -> {
                startBrokerContinue(intent);
                finish();
            }, autoContinueDelayMs);
        } else {
            finish();
        }
    }

    private Intent targetIntent(String packageName, String activityName) {
        Intent target;
        if (!isBlank(activityName)) {
            target = new Intent();
            target.setClassName(packageName, normalizeActivity(packageName, activityName));
        } else {
            target = getPackageManager().getLaunchIntentForPackage(packageName);
            if (target == null) {
                target = new Intent(Intent.ACTION_MAIN);
                target.addCategory(Intent.CATEGORY_LAUNCHER);
                target.setPackage(packageName);
            }
        }
        target.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
        return target;
    }

    private void startBrokerContinue(Intent source) {
        String brokerAction = firstNonBlank(stringExtra(source, "mq.brokerAction", ""), ACTION_BROKER);
        String brokerPackage = firstNonBlank(stringExtra(source, "mq.brokerPackage", ""), QUESTIONNAIRE_PACKAGE);
        String brokerActivity = firstNonBlank(stringExtra(source, "mq.brokerActivity", ""), BROKER_ACTIVITY);
        Intent broker = new Intent(brokerAction);
        broker.setClassName(brokerPackage, normalizeActivity(brokerPackage, brokerActivity));
        broker.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
        broker.putExtra("mq.brokerCommand", "continuePlan");
        copyChainExtras(source, broker);
        try {
            startActivity(broker);
            Log.i(TAG, "CHAIN_HOOK_BROKER_CONTINUE chainId=" + stringExtra(source, "mq.chainId", ""));
        } catch (Exception exception) {
            Log.e(TAG, "CHAIN_HOOK_BROKER_CONTINUE_FAILED " + exception.getMessage(), exception);
        }
    }

    private void copyChainExtras(Intent from, Intent to) {
        if (from == null || from.getExtras() == null) {
            return;
        }
        String[] keys = new String[] {
            "mq.chainId",
            "mq.chainStepId",
            "mq.chainStepIndex",
            "mq.sessionId",
            "mq.experimentId",
            "mq.scenarioId",
            "mq.trialId",
            "mq.participantId",
            "mq.participantName",
            "scenarioId",
            "trialId"
        };
        for (String key : keys) {
            if (from.hasExtra(key)) {
                Object value = from.getExtras().get(key);
                if (value instanceof Integer) {
                    to.putExtra(key, (Integer) value);
                } else if (value instanceof Long) {
                    to.putExtra(key, (Long) value);
                } else if (value != null) {
                    to.putExtra(key, String.valueOf(value));
                }
            }
        }
    }

    private void showStatus(String text) {
        TextView view = new TextView(this);
        view.setGravity(Gravity.CENTER);
        view.setText(text);
        view.setTextSize(20f);
        setContentView(view);
    }

    private static String normalizeActivity(String packageName, String activityName) {
        String cleaned = activityName == null ? "" : activityName.trim();
        return cleaned.startsWith(".") ? packageName + cleaned : cleaned;
    }

    private static String stringExtra(Intent intent, String key, String fallback) {
        if (intent == null) {
            return fallback;
        }
        String value = intent.getStringExtra(key);
        return isBlank(value) ? fallback : value.trim();
    }

    private static long longExtra(Intent intent, String key, long fallback) {
        if (intent == null || !intent.hasExtra(key) || intent.getExtras() == null) {
            return fallback;
        }
        Object raw = intent.getExtras().get(key);
        if (raw instanceof Number) {
            return ((Number) raw).longValue();
        }
        if (raw != null) {
            try {
                return Long.parseLong(String.valueOf(raw));
            } catch (NumberFormatException ignored) {
                return fallback;
            }
        }
        return fallback;
    }

    private static String firstNonBlank(String... values) {
        if (values == null) {
            return "";
        }
        for (String value : values) {
            if (!isBlank(value)) {
                return value.trim();
            }
        }
        return "";
    }

    private static boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }
}
