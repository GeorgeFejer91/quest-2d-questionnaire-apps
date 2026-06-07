package org.viscereality.questionnaires2d;

import android.content.Intent;
import android.os.Looper;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.Shadows;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowLog;
import org.robolectric.RobolectricTestRunner;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.concurrent.TimeUnit;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public final class CommandReplayActivityTest {
    @Test
    public void commandReplayWalksUiStagesAndExports() throws Exception {
        QuestionnaireData.RuntimeConfig config = QuestionnaireLoader.loadRuntimeConfig(RuntimeEnvironment.getApplication());
        File filesDir = RuntimeEnvironment.getApplication().getExternalFilesDir(null);
        deleteRecursively(filesDir);
        assertTrue(filesDir.mkdirs() || filesDir.exists());

        File marker = new File(filesDir, "command-replay-english.json");
        Files.write(marker.toPath(), "{}".getBytes(StandardCharsets.UTF_8));
        ShadowLog.clear();

        Intent intent = new Intent(QuestionnaireLaunchContext.ACTION_RUN);
        intent.setClassName("org.viscereality.questionnaires2d", "org.viscereality.questionnaires2d.MainActivity");
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_QUESTIONNAIRE_MODE, QuestionnaireLaunchContext.MODE_FULL);
        intent.putExtra(QuestionnaireLaunchContext.EXTRA_FINISH_BEHAVIOR, QuestionnaireLaunchContext.FINISH_STAY_SAVED);

        Robolectric.buildActivity(MainActivity.class, intent).setup();
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(3, TimeUnit.SECONDS);

        String logs = joinedQuestionnaireLogs();
        assertTrue(logs.contains("MYQUESTIONNAIRE_COMMAND_REPLAY_START language=English"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_VISUAL_STAGE stage=language"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_VISUAL_STAGE stage=demographics"));
        if (config.findBlock("maia2") != null) {
            assertTrue(logs.contains("MYQUESTIONNAIRE_VISUAL_STAGE stage=maia2"));
        }
        if (config.findBlock("pictographic") != null) {
            assertTrue(logs.contains("MYQUESTIONNAIRE_VISUAL_STAGE stage=pictographic"));
        }
        assertTrue(logs.contains("MYQUESTIONNAIRE_VISUAL_STAGE stage=slider"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_VISUAL_STAGE stage=saved-confirmation"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_COMMAND command=TextInput source=demographics-name"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_COMMAND_REPLAY_EXPORT_MATCH participant=George language=English"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_NAVIGATION_SUMMARY status=pass mode=command-replay"));
        assertFalse(marker.exists());

        File exportDir = new File(filesDir, "QuestionnaireExports");
        File[] jsonExports = exportDir.listFiles((dir, name) -> name.endsWith(".json"));
        assertTrue(jsonExports != null && jsonExports.length > 0);
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
