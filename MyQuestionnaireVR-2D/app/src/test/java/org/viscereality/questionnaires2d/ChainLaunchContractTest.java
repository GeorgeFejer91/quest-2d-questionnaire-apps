package org.viscereality.questionnaires2d;

import android.content.ComponentName;
import android.content.Intent;
import android.net.Uri;
import android.os.Looper;

import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.shadows.ShadowLog;
import org.robolectric.RobolectricTestRunner;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.TimeUnit;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public final class ChainLaunchContractTest {
    @Test
    public void parsesExplicitIntentAndDeepLinkLaunchMetadata() throws Exception {
        QuestionnaireData.RuntimeConfig config = QuestionnaireData.RuntimeConfig.fromJson(
            "{\"schemaVersion\":\"my-questionnaire-vr.config.v1\",\"chainDefaults\":{\"finishBehavior\":\"staySaved\",\"autoCloseDelayMs\":2000}}");

        Intent explicit = new Intent(QuestionnaireLaunchContext.ACTION_RUN);
        explicit.putExtra(QuestionnaireLaunchContext.EXTRA_SESSION_ID, "session-a");
        explicit.putExtra(QuestionnaireLaunchContext.EXTRA_INVOCATION_ID, "invocation-a");
        explicit.putExtra(QuestionnaireLaunchContext.EXTRA_PARTICIPANT_NAME, "P001");
        explicit.putExtra(QuestionnaireLaunchContext.EXTRA_LANGUAGE, "Deutsch");
        explicit.putExtra(QuestionnaireLaunchContext.EXTRA_FINISH_BEHAVIOR, QuestionnaireLaunchContext.FINISH_OPEN_NEXT);
        explicit.putExtra(QuestionnaireLaunchContext.EXTRA_NEXT_PACKAGE, "org.example.next");
        explicit.putExtra(QuestionnaireLaunchContext.EXTRA_NEXT_ACTIVITY, "org.example.next.MainActivity");
        explicit.putExtra(QuestionnaireLaunchContext.EXTRA_AUTO_CLOSE_DELAY_MS, "0");

        QuestionnaireLaunchContext context = QuestionnaireLaunchContext.fromIntent(explicit, config);
        assertTrue(context.chained);
        assertEquals("session-a", context.sessionId);
        assertEquals("invocation-a", context.invocationId);
        assertEquals("P001", context.participantName);
        assertEquals("Deutsch", context.language);
        assertEquals(QuestionnaireLaunchContext.FINISH_OPEN_NEXT, context.finishBehavior);
        assertEquals(0L, context.autoCloseDelayMs);

        Intent deepLink = new Intent(Intent.ACTION_VIEW, Uri.parse("myquestionnaire2d://run?sessionId=session-b&finishBehavior=resumeCaller&callerPackage=org.example.caller"));
        QuestionnaireLaunchContext linkContext = QuestionnaireLaunchContext.fromIntent(deepLink, config);
        assertTrue(linkContext.chained);
        assertEquals("session-b", linkContext.sessionId);
        assertEquals(QuestionnaireLaunchContext.FINISH_RESUME_CALLER, linkContext.finishBehavior);
        assertEquals("org.example.caller", linkContext.callerPackage);
    }

    @Test
    public void packagedDefaultsCanStartDemographicsAndOpenUnity() throws Exception {
        QuestionnaireData.RuntimeConfig config = QuestionnaireData.RuntimeConfig.fromJson(
            "{\"schemaVersion\":\"my-questionnaire-vr.config.v1\",\"chainDefaults\":{"
                + "\"finishBehavior\":\"openNext\","
                + "\"nextPackage\":\"org.example.unity\","
                + "\"nextActivity\":\"org.example.unity.UnityPlayerActivity\","
                + "\"questionnaireMode\":\"demographics\","
                + "\"triggerId\":\"trigger_1_launch_questionnaire\","
                + "\"blockNumber\":\"001\","
                + "\"blockId\":\"001_trigger_trigger_1_launch_questionnaire\","
                + "\"saveNamespace\":\"trigger_trigger_1_launch_questionnaire\","
                + "\"autoCloseDelayMs\":0"
                + "}}");

        Intent launcher = new Intent(Intent.ACTION_MAIN);
        QuestionnaireLaunchContext context = QuestionnaireLaunchContext.fromIntent(launcher, config);

        assertFalse(context.chained);
        assertTrue(context.isDemographicsOnly());
        assertTrue(context.shouldOpenNext());
        assertEquals("org.example.unity", context.nextPackage);
        assertEquals("org.example.unity.UnityPlayerActivity", context.nextActivity);
        assertEquals("trigger_1_launch_questionnaire", context.triggerId);
        assertEquals("001", context.blockNumber);
        assertEquals("001_trigger_trigger_1_launch_questionnaire", context.blockId);
        assertEquals("trigger_trigger_1_launch_questionnaire", context.saveNamespace);
        assertEquals(0L, context.autoCloseDelayMs);
    }

    @Test
    public void openNextLaunchesTargetWithResultExtrasAfterCommandReplay() throws Exception {
        File filesDir = RuntimeEnvironment.getApplication().getExternalFilesDir(null);
        deleteRecursively(filesDir);
        assertTrue(filesDir.mkdirs() || filesDir.exists());
        File marker = new File(filesDir, "command-replay-english.json");
        Files.write(marker.toPath(), "{\"ParticipantName\":\"P001\"}".getBytes(StandardCharsets.UTF_8));

        Intent intent = new Intent(QuestionnaireLaunchContext.ACTION_RUN);
        intent.setClassName("org.viscereality.questionnaires2d", "org.viscereality.questionnaires2d.MainActivity");
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_SESSION_ID, "session-chain-test");
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_EXPERIMENT_ID, "experiment-a");
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_SCENARIO_ID, "scenario-01");
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_TRIAL_ID, "trial-01");
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_PARTICIPANT_ID, "P001");
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_FINISH_BEHAVIOR, QuestionnaireLaunchContext.FINISH_OPEN_NEXT);
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_NEXT_PACKAGE, "org.example.next");
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_NEXT_ACTIVITY, "org.example.next.MainActivity");
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_AUTO_CLOSE_DELAY_MS, 0L);

        ShadowLog.clear();
        ActivityController<MainActivity> controller = Robolectric.buildActivity(MainActivity.class, intent).setup();
        MainActivity activity = controller.get();
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS);

        Intent next = Shadows.shadowOf(activity).getNextStartedActivity();
        assertNotNull(next);
        assertEquals(new ComponentName("org.example.next", "org.example.next.MainActivity"), next.getComponent());
        assertEquals("complete", next.getStringExtra(QuestionnaireLaunchContext.EXTRA_RESULT_STATUS));
        assertEquals("session-chain-test", next.getStringExtra(QuestionnaireLaunchContext.EXTRA_SESSION_ID));
        QuestionnaireData.RuntimeConfig activeConfig = QuestionnaireLoader.loadRuntimeConfig(RuntimeEnvironment.getApplication());
        assertEquals(activeConfig.questionnaireId, next.getStringExtra(QuestionnaireLaunchContext.EXTRA_QUESTIONNAIRE_CONFIG_ID));
        assertTrue(next.getStringExtra(QuestionnaireLaunchContext.EXTRA_EXPORT_JSON_PATH).endsWith(".json"));
        assertTrue(next.getStringExtra(QuestionnaireLaunchContext.EXTRA_EXPORT_CSV_PATH).endsWith(".csv"));
        assertTrue(activity.isFinishing());

        String logs = joinedQuestionnaireLogs();
        assertTrue(logs.contains("MYQUESTIONNAIRE_CHAIN_RETURN finishBehavior=openNext"));
    }

    @Test
    public void demographicsModeExportsAfterParticipantFormOnly() throws Exception {
        File filesDir = RuntimeEnvironment.getApplication().getExternalFilesDir(null);
        deleteRecursively(filesDir);
        assertTrue(filesDir.mkdirs() || filesDir.exists());
        File marker = new File(filesDir, "command-replay-english.json");
        Files.write(marker.toPath(), "{\"ParticipantName\":\"Demo Participant\"}".getBytes(StandardCharsets.UTF_8));

        Intent intent = new Intent(QuestionnaireLaunchContext.ACTION_RUN);
        intent.setClassName("org.viscereality.questionnaires2d", "org.viscereality.questionnaires2d.MainActivity");
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_SESSION_ID, "session-demo");
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_TRIGGER_ID, "trigger_1_launch_questionnaire");
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_QUESTIONNAIRE_MODE, QuestionnaireLaunchContext.MODE_DEMOGRAPHICS);
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_FINISH_BEHAVIOR, QuestionnaireLaunchContext.FINISH_STAY_SAVED);
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_AUTO_CLOSE_DELAY_MS, 0L);

        ActivityController<MainActivity> controller = Robolectric.buildActivity(MainActivity.class, intent).setup();
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS);

        File index = new File(QuestionnaireExporter.exportFolder(RuntimeEnvironment.getApplication()), QuestionnaireExporter.SESSION_INDEX_NAME);
        assertTrue(index.exists());
        String indexText = new String(Files.readAllBytes(index.toPath()), StandardCharsets.UTF_8);
        assertTrue(indexText.contains("\"questionnaireMode\":\"demographics\""));

        String jsonPath = new JSONObject(indexText.trim()).getString("jsonPath");
        JSONObject record = new JSONObject(new String(Files.readAllBytes(new File(jsonPath).toPath()), StandardCharsets.UTF_8));
        assertEquals("trigger_1_launch_questionnaire", record.getString("triggerId"));
        assertEquals("demographics", record.getString("questionnaireMode"));
        assertEquals(0, record.getJSONArray("maia2Answers").length());
        assertEquals(0, record.getJSONArray("pictographicSelections").length());
        assertEquals(0, record.getJSONArray("questionnaireAnswers").length());
        assertTrue(controller.get().getClass().getName().contains("MainActivity"));
    }

    @Test
    public void writesUniqueFinalExportsDraftAndSessionIndexForRepeatedSameName() throws Exception {
        File filesDir = RuntimeEnvironment.getApplication().getExternalFilesDir(null);
        deleteRecursively(filesDir);
        assertTrue(filesDir.mkdirs() || filesDir.exists());

        QuestionnaireData.RuntimeConfig config = QuestionnaireLoader.loadRuntimeConfig(RuntimeEnvironment.getApplication());
        QuestionnaireData.SessionRecord first = AutoSessionRunner.buildRecord(
            new AutoSessionRunner.Mode("English", true, null),
            new AutoSessionRunner.Plan(),
            config,
            java.util.Collections.emptyList(),
            java.util.Arrays.asList("A", "B"),
            java.util.Collections.emptyList());
        first.runId = TimeUtil.newRunId();
        first.invocationId = first.runId;
        first.sessionId = "same-name-session";
        first.participant.name = "Same Name";
        first.participant.participantId = "SameName";
        first.finishBehavior = QuestionnaireLaunchContext.FINISH_STAY_SAVED;
        first.questionnaireMode = "baseline";
        first.blockNumber = "001";
        first.blockId = "001_baseline_questionnaire";

        QuestionnaireData.SessionRecord second = AutoSessionRunner.buildRecord(
            new AutoSessionRunner.Mode("English", true, null),
            new AutoSessionRunner.Plan(),
            config,
            java.util.Collections.emptyList(),
            java.util.Arrays.asList("A", "B"),
            java.util.Collections.emptyList());
        second.runId = TimeUtil.newRunId();
        second.invocationId = second.runId;
        second.sessionId = "same-name-session";
        second.participant.name = "Same Name";
        second.participant.participantId = "SameName";
        second.finishBehavior = QuestionnaireLaunchContext.FINISH_STAY_SAVED;
        second.questionnaireMode = "pictographic";
        second.blockNumber = "003";
        second.blockId = "003_pictographic_01";

        assertNotEquals(first.runId, second.runId);
        QuestionnaireExporter.writeDraft(RuntimeEnvironment.getApplication(), first, "launched");
        QuestionnaireExporter.ExportResult firstExport = QuestionnaireExporter.writeSession(RuntimeEnvironment.getApplication(), first);
        QuestionnaireExporter.ExportResult secondExport = QuestionnaireExporter.writeSession(RuntimeEnvironment.getApplication(), second);

        assertTrue(firstExport.jsonFile.exists());
        assertTrue(secondExport.jsonFile.exists());
        assertTrue(firstExport.combinedCsvFile.exists());
        assertTrue(secondExport.combinedCsvFile.exists());
        assertEquals(firstExport.combinedCsvFile.getName(), secondExport.combinedCsvFile.getName());
        assertNotEquals(firstExport.jsonFile.getName(), secondExport.jsonFile.getName());
        assertTrue(firstExport.jsonFile.getName().contains(first.runId));
        assertTrue(secondExport.jsonFile.getName().contains(second.runId));

        File draft = new File(QuestionnaireExporter.inProgressFolder(RuntimeEnvironment.getApplication()), first.runId + "_draft.json");
        assertTrue(draft.exists());
        JSONObject draftJson = new JSONObject(new String(Files.readAllBytes(draft.toPath()), StandardCharsets.UTF_8));
        assertEquals("complete", draftJson.getString("draftStatus"));

        File index = new File(QuestionnaireExporter.exportFolder(RuntimeEnvironment.getApplication()), QuestionnaireExporter.SESSION_INDEX_NAME);
        assertTrue(index.exists());
        String indexText = new String(Files.readAllBytes(index.toPath()), StandardCharsets.UTF_8);
        assertTrue(indexText.contains(first.runId));
        assertTrue(indexText.contains(second.runId));

        String combinedCsv = new String(Files.readAllBytes(secondExport.combinedCsvFile.toPath()), StandardCharsets.UTF_8);
        assertTrue(combinedCsv.startsWith("timestampUtc,participantId,name"));
        assertTrue(combinedCsv.contains(",baseline,001,001_baseline_questionnaire,"));
        assertTrue(combinedCsv.contains(",pictographic,003,003_pictographic_01,"));
        assertEquals(3, combinedCsv.split("\\R").length);
    }

    private static String joinedQuestionnaireLogs() {
        StringBuilder builder = new StringBuilder();
        for (ShadowLog.LogItem item : ShadowLog.getLogsForTag(AutoSessionRunner.TAG)) {
            builder.append(item.msg).append('\n');
        }
        return builder.toString();
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
