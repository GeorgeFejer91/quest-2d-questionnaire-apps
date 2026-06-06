package org.viscereality.chainlink;

import android.content.ComponentName;
import android.content.Intent;
import android.view.KeyEvent;

import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import org.robolectric.RobolectricTestRunner;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public final class ChainLinkActivityTest {
    @Test
    public void startPlanLaunchesFirstQuestionnaireAndWritesState() throws Exception {
        resetFiles();

        ActivityController<ChainLinkActivity> controller = Robolectric.buildActivity(
            ChainLinkActivity.class,
            startPlanIntent(planJson()));
        ChainLinkActivity activity = controller.setup().get();

        Intent launched = Shadows.shadowOf(activity).getNextStartedActivity();
        assertNotNull(launched);
        assertEquals(
            new ComponentName(
                "org.viscereality.questionnaires2d",
                "org.viscereality.questionnaires2d.MainActivity"),
            launched.getComponent());
        assertEquals("org.viscereality.questionnaires2d.RUN", launched.getAction());
        assertEquals("chain-test", launched.getStringExtra("mq.chainId"));
        assertEquals(0, launched.getIntExtra("mq.chainStepIndex", -1));
        assertEquals("001_baseline_questionnaire", launched.getStringExtra("mq.chainStepId"));
        assertEquals("resumeCaller", launched.getStringExtra("mq.finishBehavior"));
        assertEquals("org.viscereality.chainlink", launched.getStringExtra("mq.callerPackage"));
        assertEquals("session-test", launched.getStringExtra("mq.sessionId"));
        assertEquals("Participant One", launched.getStringExtra("mq.participantName"));

        JSONObject state = readState();
        assertEquals("running", state.getString("status"));
        assertEquals("chain-test", state.getString("chainId"));
        assertEquals(0, state.getInt("currentStepIndex"));

        String events = readEvents();
        assertTrue(events.contains("\"event\":\"command\""));
        assertTrue(events.contains("\"event\":\"plan-start\""));
        assertTrue(events.contains("\"event\":\"launch-step\""));
        assertTrue(events.contains("\"stepId\":\"001_baseline_questionnaire\""));
    }

    @Test
    public void nextBlockAdvancesThroughStepsAndPersistsCompletionResult() throws Exception {
        resetFiles();

        ActivityController<ChainLinkActivity> controller = Robolectric.buildActivity(
            ChainLinkActivity.class,
            startPlanIntent(planJson()));
        ChainLinkActivity activity = controller.setup().get();
        Shadows.shadowOf(activity).getNextStartedActivity();

        activity.onNewIntent(nextBlockIntent("unity-hook-1"));
        Intent scenario = Shadows.shadowOf(activity).getNextStartedActivity();
        assertNotNull(scenario);
        assertEquals(new ComponentName("org.example.scenario", "org.example.scenario.MainActivity"), scenario.getComponent());
        assertEquals(Intent.ACTION_MAIN, scenario.getAction());
        assertTrue(scenario.getCategories().contains(Intent.CATEGORY_LAUNCHER));
        assertEquals(1, scenario.getIntExtra("mq.chainStepIndex", -1));
        assertEquals("002_target_apk_start", scenario.getStringExtra("mq.chainStepId"));
        assertEquals("unity-hook-1", scenario.getStringExtra("mq.triggerSource"));
        assertEquals("session-test", scenario.getStringExtra("mq.sessionId"));
        assertEquals("Participant One", scenario.getStringExtra("mq.participantName"));

        activity.onNewIntent(nextBlockIntent("unity-hook-2"));
        Intent pictographic = Shadows.shadowOf(activity).getNextStartedActivity();
        assertNotNull(pictographic);
        assertEquals(
            new ComponentName(
                "org.viscereality.questionnaires2d",
                "org.viscereality.questionnaires2d.MainActivity"),
            pictographic.getComponent());
        assertEquals("pictographic", pictographic.getStringExtra("mq.questionnaireMode"));
        assertEquals("003_pictographic_01", pictographic.getStringExtra("mq.chainStepId"));
        assertEquals("session-test", pictographic.getStringExtra("mq.sessionId"));
        assertEquals("Participant One", pictographic.getStringExtra("mq.participantName"));

        Intent complete = new Intent(ChainLinkActivity.ACTION_COMMAND);
        complete.putExtra("mq.resultStatus", "complete");
        complete.putExtra("mq.runId", "run-003");
        complete.putExtra("mq.exportJsonPath", "/device/export/run-003.json");
        complete.putExtra("mq.exportCsvPath", "/device/export/run-003.csv");
        activity.onNewIntent(complete);

        JSONObject state = readState();
        assertEquals("complete", state.getString("status"));
        assertEquals(2, state.getInt("currentStepIndex"));
        assertEquals("run-003", state.getJSONObject("lastResult").getString("mq.runId"));
        assertEquals("/device/export/run-003.json", state.getJSONObject("lastResult").getString("mq.exportJsonPath"));

        String events = readEvents();
        assertEquals(3, count(events, "\"event\":\"launch-step\""));
        assertTrue(events.contains("\"event\":\"plan-complete\""));
    }

    @Test
    public void focusedControllerKeyEventSendsNextBlockCommand() throws Exception {
        resetFiles();

        ActivityController<ChainLinkActivity> controller = Robolectric.buildActivity(
            ChainLinkActivity.class,
            startPlanIntent(planJson()));
        ChainLinkActivity activity = controller.setup().get();
        Shadows.shadowOf(activity).getNextStartedActivity();

        boolean handled = activity.dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BUTTON_X));
        assertTrue(handled);

        Intent scenario = Shadows.shadowOf(activity).getNextStartedActivity();
        assertNotNull(scenario);
        assertEquals(new ComponentName("org.example.scenario", "org.example.scenario.MainActivity"), scenario.getComponent());

        String events = readEvents();
        assertTrue(events.contains("\"event\":\"controller-trigger\""));
        assertTrue(events.contains("keyCode=" + KeyEvent.KEYCODE_BUTTON_X));
    }

    @Test
    public void clearCommandDeletesPersistedState() throws Exception {
        resetFiles();

        ActivityController<ChainLinkActivity> controller = Robolectric.buildActivity(
            ChainLinkActivity.class,
            startPlanIntent(planJson()));
        ChainLinkActivity activity = controller.setup().get();
        assertTrue(stateFile().exists());

        Intent clear = new Intent(ChainLinkActivity.ACTION_COMMAND);
        clear.putExtra("mq.command", "clear");
        activity.onNewIntent(clear);

        assertFalse(stateFile().exists());
    }

    private static Intent startPlanIntent(String planJson) {
        Intent intent = new Intent(ChainLinkActivity.ACTION_RUN);
        intent.setClassName("org.viscereality.chainlink", "org.viscereality.chainlink.ChainLinkActivity");
        intent.putExtra("mq.command", "startPlan");
        intent.putExtra("mq.chainPlanJson", planJson);
        intent.putExtra("mq.chainId", "chain-test");
        intent.putExtra("mq.sessionId", "session-test");
        intent.putExtra("mq.participantName", "Participant One");
        intent.putExtra("mq.language", "English");
        return intent;
    }

    private static Intent nextBlockIntent(String triggerSource) {
        Intent intent = new Intent(ChainLinkActivity.ACTION_COMMAND);
        intent.setClassName("org.viscereality.chainlink", "org.viscereality.chainlink.ChainLinkActivity");
        intent.putExtra("mq.command", "nextBlock");
        intent.putExtra("mq.triggerSource", triggerSource);
        intent.putExtra("mq.triggerTimestampUtc", "2026-06-05T12:00:00.000Z");
        return intent;
    }

    private static String planJson() {
        return "{"
            + "\"schemaVersion\":\"viscereality.chainlink.plan.v1\","
            + "\"chainId\":\"chain-test\","
            + "\"steps\":["
            + "{"
            + "\"id\":\"001_baseline_questionnaire\","
            + "\"blockNumber\":\"001\","
            + "\"type\":\"questionnaire\","
            + "\"package\":\"org.viscereality.questionnaires2d\","
            + "\"activity\":\"org.viscereality.questionnaires2d.MainActivity\","
            + "\"action\":\"org.viscereality.questionnaires2d.RUN\","
            + "\"extras\":{\"mq.questionnaireMode\":\"baseline\",\"mq.finishBehavior\":\"resumeCaller\",\"mq.autoCloseDelayMs\":0}"
            + "},"
            + "{"
            + "\"id\":\"002_target_apk_start\","
            + "\"blockNumber\":\"002\","
            + "\"type\":\"scenario\","
            + "\"package\":\"org.example.scenario\","
            + "\"activity\":\"org.example.scenario.MainActivity\","
            + "\"action\":\"android.intent.action.MAIN\","
            + "\"extras\":{\"mq.targetRole\":\"experiment-apk\"}"
            + "},"
            + "{"
            + "\"id\":\"003_pictographic_01\","
            + "\"blockNumber\":\"003\","
            + "\"type\":\"questionnaire\","
            + "\"package\":\"org.viscereality.questionnaires2d\","
            + "\"activity\":\"org.viscereality.questionnaires2d.MainActivity\","
            + "\"action\":\"org.viscereality.questionnaires2d.RUN\","
            + "\"extras\":{\"mq.questionnaireMode\":\"pictographic\",\"mq.finishBehavior\":\"resumeCaller\",\"mq.blockInstance\":1,\"mq.autoCloseDelayMs\":0}"
            + "}"
            + "]"
            + "}";
    }

    private static JSONObject readState() throws Exception {
        return new JSONObject(new String(Files.readAllBytes(stateFile().toPath()), StandardCharsets.UTF_8));
    }

    private static String readEvents() throws Exception {
        return new String(Files.readAllBytes(eventsFile().toPath()), StandardCharsets.UTF_8);
    }

    private static File stateFile() {
        return new File(chainLinkFolder(), "chainlink-state.json");
    }

    private static File eventsFile() {
        return new File(chainLinkFolder(), "chainlink-events.jsonl");
    }

    private static File chainLinkFolder() {
        return new File(RuntimeEnvironment.getApplication().getExternalFilesDir(null), "ChainLink");
    }

    private static void resetFiles() {
        deleteRecursively(RuntimeEnvironment.getApplication().getExternalFilesDir(null));
    }

    private static int count(String text, String needle) {
        int count = 0;
        int index = 0;
        while ((index = text.indexOf(needle, index)) >= 0) {
            count++;
            index += needle.length();
        }
        return count;
    }

    private static void deleteRecursively(File file) {
        if (file == null || !file.exists()) {
            return;
        }
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) {
                deleteRecursively(child);
            }
        }
        if (!file.delete()) {
            throw new IllegalStateException("Could not delete " + file.getAbsolutePath());
        }
    }
}
