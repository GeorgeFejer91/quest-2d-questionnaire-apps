package org.viscereality.sourcehookstub;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Gravity;
import android.widget.TextView;

public final class SourceHookStubActivity extends Activity {
    public static final String ACTION_CHAIN_COMMAND = "org.viscereality.CHAIN_COMMAND";
    public static final String ACTION_BROKER = "org.viscereality.questionnaires2d.BROKER";
    public static final String QUESTIONNAIRE_PACKAGE = "org.viscereality.questionnaires2d";
    public static final String BROKER_ACTIVITY = "org.viscereality.questionnaires2d.QuestChainBrokerActivity";
    public static final String TAG = "ViscerealitySourceHook";

    private final Handler handler = new Handler(Looper.getMainLooper());

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        showStatus("Source hook scenario stub");
        handleIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        handleIntent(intent);
    }

    private void handleIntent(Intent intent) {
        handler.removeCallbacksAndMessages(null);
        String command = stringExtra(intent, "mq.hookCommand", "startScenario");
        long autoContinueDelayMs = longExtra(intent, "mq.autoContinueDelayMs", longExtra(intent, "autoContinueDelayMs", -1L));

        Log.i(TAG, "SOURCE_HOOK_STUB_RECEIVED command=" + command
            + " autoContinueDelayMs=" + autoContinueDelayMs
            + " chainId=" + stringExtra(intent, "mq.chainId", "")
            + " chainStepId=" + stringExtra(intent, "mq.chainStepId", "")
            + " scenarioId=" + firstNonBlank(
                stringExtra(intent, "mq.scenarioId", ""),
                stringExtra(intent, "scenarioId", "")));

        if ("continuePlan".equals(command)) {
            continueBroker(intent);
            finish();
            return;
        }

        if (autoContinueDelayMs >= 0L) {
            handler.postDelayed(() -> {
                continueBroker(intent);
                finish();
            }, autoContinueDelayMs);
        }
    }

    private void continueBroker(Intent source) {
        String brokerAction = firstNonBlank(stringExtra(source, "mq.brokerAction", ""), ACTION_BROKER);
        String brokerPackage = firstNonBlank(stringExtra(source, "mq.brokerPackage", ""), QUESTIONNAIRE_PACKAGE);
        String brokerActivity = firstNonBlank(stringExtra(source, "mq.brokerActivity", ""), BROKER_ACTIVITY);

        Intent broker = new Intent(brokerAction);
        broker.setClassName(brokerPackage, normalizeActivity(brokerPackage, brokerActivity));
        broker.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT | Intent.FLAG_ACTIVITY_SINGLE_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
        broker.putExtra("mq.brokerCommand", "continuePlan");
        broker.putExtra("mq.resultStatus", "scenarioComplete");
        broker.putExtra("mq.scenarioResultStatus", "complete");
        broker.putExtra("mq.scenarioVersion", firstNonBlank(stringExtra(source, "mq.scenarioVersion", ""), "source-hook-stub"));
        broker.putExtra(
            "mq.scenarioParticipantDataPath",
            firstNonBlank(stringExtra(source, "mq.scenarioParticipantDataPath", ""), "/sdcard/source-hook-stub/participant-data.csv"));
        copyChainExtras(source, broker);

        try {
            startActivity(broker);
            Log.i(TAG, "SOURCE_HOOK_STUB_BROKER_CONTINUE broker=" + brokerPackage + "/" + brokerActivity
                + " chainId=" + stringExtra(source, "mq.chainId", ""));
        } catch (Exception exception) {
            Log.e(TAG, "SOURCE_HOOK_STUB_BROKER_CONTINUE_FAILED " + exception.getMessage(), exception);
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
