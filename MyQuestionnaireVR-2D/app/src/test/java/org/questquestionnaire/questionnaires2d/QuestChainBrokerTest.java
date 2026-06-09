package org.questquestionnaire.questionnaires2d;

import android.content.ComponentName;
import android.content.Intent;

import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.RobolectricTestRunner;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public final class QuestChainBrokerTest {
    @Test
    public void startPlanLaunchesFirstScenarioAndPersistsState() throws Exception {
        deleteBrokerState();
        Intent start = new Intent(QuestChainBroker.ACTION_BROKER);
        start.putExtra(QuestChainBroker.EXTRA_BROKER_COMMAND, QuestChainBroker.COMMAND_START_PLAN);
        start.putExtra(QuestChainBroker.EXTRA_CHAIN_PLAN_JSON, twoStepScenarioQuestionnairePlan());
        start.putExtra(QuestionnaireLaunchContext.EXTRA_CHAIN_ID, "chain-001");
        start.putExtra(QuestionnaireLaunchContext.EXTRA_PARTICIPANT_NAME, "Participant A");

        QuestChainBroker.Result result = QuestChainBroker.handle(RuntimeEnvironment.getApplication(), start);

        assertEquals("app:scenario-a", result.status);
        assertNotNull(result.outgoingIntent);
        assertEquals(new ComponentName("org.example.scenario", "org.example.scenario.MainActivity"), result.outgoingIntent.getComponent());
        assertEquals("org.questquestionnaire.CHAIN_COMMAND", result.outgoingIntent.getAction());
        assertEquals("startScenario", result.outgoingIntent.getStringExtra(QuestChainBroker.EXTRA_HOOK_COMMAND));
        assertEquals(QuestChainBroker.ACTION_BROKER, result.outgoingIntent.getStringExtra(QuestChainBroker.EXTRA_BROKER_ACTION));
        assertEquals("org.questquestionnaire.questionnaires2d.QuestChainBrokerActivity", result.outgoingIntent.getStringExtra(QuestChainBroker.EXTRA_BROKER_ACTIVITY));
        assertEquals("chain-001", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_CHAIN_ID));
        assertEquals("scenario-a", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_CHAIN_STEP_ID));

        JSONObject state = readStateJson();
        assertEquals("chain-001", state.getString("chainId"));
        assertEquals(0, state.getInt("currentStepIndex"));
        assertEquals("running", state.getString("status"));
    }

    @Test
    public void continuePlanLaunchesQuestionnaireWithBrokerAsCaller() throws Exception {
        deleteBrokerState();
        Intent start = new Intent(QuestChainBroker.ACTION_BROKER);
        start.putExtra(QuestChainBroker.EXTRA_BROKER_COMMAND, QuestChainBroker.COMMAND_START_PLAN);
        start.putExtra(QuestChainBroker.EXTRA_CHAIN_PLAN_JSON, twoStepScenarioQuestionnairePlan());
        start.putExtra(QuestionnaireLaunchContext.EXTRA_CHAIN_ID, "chain-002");
        QuestChainBroker.handle(RuntimeEnvironment.getApplication(), start);

        Intent continueIntent = new Intent(QuestChainBroker.ACTION_BROKER);
        continueIntent.putExtra(QuestChainBroker.EXTRA_BROKER_COMMAND, QuestChainBroker.COMMAND_CONTINUE_PLAN);
        QuestChainBroker.Result result = QuestChainBroker.handle(RuntimeEnvironment.getApplication(), continueIntent);

        assertEquals("questionnaire:questionnaire-a", result.status);
        assertNotNull(result.outgoingIntent);
        assertEquals(new ComponentName(
            "org.questquestionnaire.questionnaires2d",
            "org.questquestionnaire.questionnaires2d.MainActivity"), result.outgoingIntent.getComponent());
        assertEquals(QuestionnaireLaunchContext.ACTION_RUN, result.outgoingIntent.getAction());
        assertEquals(QuestionnaireLaunchContext.FINISH_RESUME_CALLER, result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_FINISH_BEHAVIOR));
        assertEquals("org.questquestionnaire.questionnaires2d", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_CALLER_PACKAGE));
        assertEquals("org.questquestionnaire.questionnaires2d.QuestChainBrokerActivity", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_CALLER_ACTIVITY));
        assertEquals("chain-002", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_CHAIN_ID));
        assertEquals("questionnaire-a", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_CHAIN_STEP_ID));
        assertEquals("English", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_LANGUAGE));
    }

    @Test
    public void questionnaireCompletionAdvancesToNextScenarioWithResultExtras() throws Exception {
        deleteBrokerState();
        Intent start = new Intent(QuestChainBroker.ACTION_BROKER);
        start.putExtra(QuestChainBroker.EXTRA_BROKER_COMMAND, QuestChainBroker.COMMAND_START_PLAN);
        start.putExtra(QuestChainBroker.EXTRA_CHAIN_PLAN_JSON, questionnaireThenScenarioPlan());
        start.putExtra(QuestionnaireLaunchContext.EXTRA_CHAIN_ID, "chain-003");
        QuestChainBroker.handle(RuntimeEnvironment.getApplication(), start);

        Intent completion = new Intent(QuestChainBroker.ACTION_BROKER);
        completion.putExtra(QuestionnaireLaunchContext.EXTRA_RESULT_STATUS, "complete");
        completion.putExtra(QuestionnaireLaunchContext.EXTRA_RUN_ID, "run-123");
        completion.putExtra(QuestionnaireLaunchContext.EXTRA_EXPORT_JSON_PATH, "/device/export.json");
        completion.putExtra(QuestionnaireLaunchContext.EXTRA_EXPORT_CSV_PATH, "/device/export.csv");

        QuestChainBroker.Result result = QuestChainBroker.handle(RuntimeEnvironment.getApplication(), completion);

        assertEquals("app:scenario-b", result.status);
        assertNotNull(result.outgoingIntent);
        assertEquals(new ComponentName("org.example.next", "org.example.next.MainActivity"), result.outgoingIntent.getComponent());
        assertEquals("complete", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_RESULT_STATUS));
        assertEquals("run-123", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_RUN_ID));
        assertEquals("/device/export.json", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_EXPORT_JSON_PATH));
        assertEquals("chain-003", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_CHAIN_ID));

        JSONObject state = readStateJson();
        assertEquals(1, state.getInt("currentStepIndex"));
    }

    @Test
    public void triggerCommandRoutesByTriggerIdInsideQuestionnaireBroker() throws Exception {
        deleteBrokerState();
        Intent start = new Intent(QuestChainBroker.ACTION_BROKER);
        start.putExtra(QuestChainBroker.EXTRA_BROKER_COMMAND, QuestChainBroker.COMMAND_START_PLAN);
        start.putExtra(QuestChainBroker.EXTRA_CHAIN_PLAN_JSON, triggerRoutedPlan(false));
        start.putExtra(QuestionnaireLaunchContext.EXTRA_CHAIN_ID, "chain-trigger-001");
        QuestChainBroker.handle(RuntimeEnvironment.getApplication(), start);

        Intent trigger = new Intent(QuestChainBroker.ACTION_BROKER);
        trigger.putExtra(QuestChainBroker.EXTRA_BROKER_COMMAND, QuestChainBroker.COMMAND_TRIGGER);
        trigger.putExtra(QuestionnaireLaunchContext.EXTRA_TRIGGER_ID, "trigger_1_complete");
        QuestChainBroker.Result result = QuestChainBroker.handle(RuntimeEnvironment.getApplication(), trigger);

        assertEquals("questionnaire:questionnaire-after-trigger", result.status);
        assertNotNull(result.outgoingIntent);
        assertEquals(new ComponentName(
            "org.questquestionnaire.questionnaires2d",
            "org.questquestionnaire.questionnaires2d.MainActivity"), result.outgoingIntent.getComponent());
        assertEquals("trigger_1_complete", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_TRIGGER_ID));
        assertEquals("questionnaire-after-trigger", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_CHAIN_STEP_ID));
        assertEquals("English", result.outgoingIntent.getStringExtra(QuestionnaireLaunchContext.EXTRA_LANGUAGE));

        JSONObject state = readStateJson();
        assertEquals(1, state.getInt("currentStepIndex"));
        assertEquals("trigger_1_complete", state.getJSONObject("lastResult").getString(QuestionnaireLaunchContext.EXTRA_TRIGGER_ID));
    }

    @Test
    public void repeatedTriggerDoesNotReplayCompletedBlockUnlessRepeatable() throws Exception {
        deleteBrokerState();
        Intent start = new Intent(QuestChainBroker.ACTION_BROKER);
        start.putExtra(QuestChainBroker.EXTRA_BROKER_COMMAND, QuestChainBroker.COMMAND_START_PLAN);
        start.putExtra(QuestChainBroker.EXTRA_CHAIN_PLAN_JSON, triggerRoutedPlan(false));
        start.putExtra(QuestionnaireLaunchContext.EXTRA_CHAIN_ID, "chain-trigger-002");
        QuestChainBroker.handle(RuntimeEnvironment.getApplication(), start);

        Intent trigger = new Intent(QuestChainBroker.ACTION_BROKER);
        trigger.putExtra(QuestChainBroker.EXTRA_BROKER_COMMAND, QuestChainBroker.COMMAND_TRIGGER);
        trigger.putExtra(QuestionnaireLaunchContext.EXTRA_TRIGGER_ID, "trigger_1_complete");
        QuestChainBroker.handle(RuntimeEnvironment.getApplication(), trigger);

        QuestChainBroker.Result repeated = QuestChainBroker.handle(RuntimeEnvironment.getApplication(), trigger);

        assertEquals("trigger-unmapped:trigger_1_complete", repeated.status);
        assertNull(repeated.outgoingIntent);
        assertEquals(1, readStateJson().getInt("currentStepIndex"));
    }

    @Test
    public void goHomeBuildsHomeIntentAndClearPlanRemovesState() throws Exception {
        deleteBrokerState();
        Intent start = new Intent(QuestChainBroker.ACTION_BROKER);
        start.putExtra(QuestChainBroker.EXTRA_BROKER_COMMAND, QuestChainBroker.COMMAND_START_PLAN);
        start.putExtra(QuestChainBroker.EXTRA_CHAIN_PLAN_JSON, questionnaireThenScenarioPlan());
        QuestChainBroker.handle(RuntimeEnvironment.getApplication(), start);
        assertTrue(QuestChainBroker.stateFile(RuntimeEnvironment.getApplication()).exists());

        Intent home = new Intent(QuestChainBroker.ACTION_BROKER);
        home.putExtra(QuestChainBroker.EXTRA_BROKER_COMMAND, QuestChainBroker.COMMAND_GO_HOME);
        QuestChainBroker.Result homeResult = QuestChainBroker.handle(RuntimeEnvironment.getApplication(), home);
        assertEquals(Intent.ACTION_MAIN, homeResult.outgoingIntent.getAction());
        assertTrue(homeResult.outgoingIntent.getCategories().contains(Intent.CATEGORY_HOME));

        Intent clear = new Intent(QuestChainBroker.ACTION_BROKER);
        clear.putExtra(QuestChainBroker.EXTRA_BROKER_COMMAND, QuestChainBroker.COMMAND_CLEAR_PLAN);
        QuestChainBroker.handle(RuntimeEnvironment.getApplication(), clear);
        assertFalse(QuestChainBroker.stateFile(RuntimeEnvironment.getApplication()).exists());
    }

    private static String twoStepScenarioQuestionnairePlan() {
        return "{"
            + "\"schemaVersion\":\"my-questionnaire-2d.chain-plan.v1\","
            + "\"steps\":["
            + "{\"id\":\"scenario-a\",\"type\":\"scenario\",\"package\":\"org.example.scenario\",\"activity\":\"org.example.scenario.MainActivity\","
            + "\"action\":\"org.questquestionnaire.CHAIN_COMMAND\",\"command\":\"startScenario\"},"
            + "{\"id\":\"questionnaire-a\",\"type\":\"questionnaire\",\"package\":\"org.questquestionnaire.questionnaires2d\",\"activity\":\".MainActivity\","
            + "\"extras\":{\"mq.language\":\"English\",\"mq.sessionId\":\"session-a\"}}"
            + "]}";
    }

    private static String questionnaireThenScenarioPlan() {
        return "{"
            + "\"schemaVersion\":\"my-questionnaire-2d.chain-plan.v1\","
            + "\"steps\":["
            + "{\"id\":\"questionnaire-a\",\"type\":\"questionnaire\",\"package\":\"org.questquestionnaire.questionnaires2d\",\"activity\":\".MainActivity\","
            + "\"extras\":{\"mq.language\":\"English\",\"mq.autoCloseDelayMs\":0}},"
            + "{\"id\":\"scenario-b\",\"type\":\"scenario\",\"package\":\"org.example.next\",\"activity\":\"org.example.next.MainActivity\"}"
            + "]}";
    }

    private static String triggerRoutedPlan(boolean allowRepeat) {
        return "{"
            + "\"schemaVersion\":\"my-questionnaire-2d.chain-plan.v1\","
            + "\"steps\":["
            + "{\"id\":\"scenario-a\",\"type\":\"scenario\",\"package\":\"org.example.scenario\",\"activity\":\"org.example.scenario.MainActivity\"},"
            + "{\"id\":\"questionnaire-after-trigger\",\"type\":\"questionnaire\",\"package\":\"org.questquestionnaire.questionnaires2d\",\"activity\":\".MainActivity\","
            + "\"trigger\":{\"type\":\"apkManifestTrigger\",\"triggerId\":\"trigger_1_complete\",\"allowRepeat\":" + allowRepeat + "},"
            + "\"extras\":{\"mq.language\":\"English\",\"mq.autoCloseDelayMs\":0}}"
            + "]}";
    }

    private static JSONObject readStateJson() throws Exception {
        File state = QuestChainBroker.stateFile(RuntimeEnvironment.getApplication());
        return new JSONObject(new String(Files.readAllBytes(state.toPath()), StandardCharsets.UTF_8));
    }

    private static void deleteBrokerState() throws Exception {
        File folder = QuestChainBroker.brokerFolder(RuntimeEnvironment.getApplication());
        deleteRecursively(folder);
        assertTrue(folder.mkdirs() || folder.exists());
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
