package org.mesmerprism.viscereality.questionnaires2d;

import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.SeekBar;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.Robolectric;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.shadows.ShadowLog;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public final class ManualInputLoggingTest {
    @Test
    public void logsManualPanelActivationTouchAndBackKey() {
        ShadowLog.clear();
        MainActivity activity = Robolectric.buildActivity(MainActivity.class).setup().get();

        activity.dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK));
        MotionEvent touch = MotionEvent.obtain(0L, 0L, MotionEvent.ACTION_DOWN, 20f, 20f, 0);
        try {
            activity.dispatchTouchEvent(touch);
        } finally {
            touch.recycle();
        }
        Button english = findButtonWithText(activity.findViewById(android.R.id.content), "English");
        assertTrue(english != null);
        english.performClick();

        String logs = joinedQuestionnaireLogs();
        assertTrue(logs.contains("MYQUESTIONNAIRE_INPUT_KEY action=down"));
        assertTrue(logs.contains("keyCode=4"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_INPUT_TOUCH action=down"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_INPUT action=Activate source=language-English"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_VISUAL_STAGE stage=language"));
    }

    @Test
    public void manualHardwareGateMarkerLaunchesValidationPanelAndLogsEvents() throws Exception {
        File filesDir = RuntimeEnvironment.getApplication().getExternalFilesDir(null);
        deleteRecursively(filesDir);
        assertTrue(filesDir.mkdirs() || filesDir.exists());
        File marker = new File(filesDir, AutoSessionRunner.MANUAL_HARDWARE_GATE);
        Files.write(marker.toPath(), "manual hardware validation".getBytes(StandardCharsets.UTF_8));

        ShadowLog.clear();
        MainActivity activity = Robolectric.buildActivity(MainActivity.class).setup().get();
        assertFalse(marker.exists());

        View root = activity.findViewById(android.R.id.content);
        Button target1 = findButtonWithText(root, "Target 1");
        Button target2 = findButtonWithText(root, "Target 2");
        Button back = findButtonWithText(root, "Back");
        Button done = findButtonWithText(root, "Done");
        EditText keyboard = findViewWithContentDescription(root, "manual-gate.keyboard", EditText.class);
        SeekBar slider = findViewWithContentDescription(root, "manual-gate.joystick-slider", SeekBar.class);

        assertTrue(target1 != null);
        assertTrue(target2 != null);
        assertTrue(back != null);
        assertTrue(done != null);
        assertTrue(keyboard != null);
        assertTrue(slider != null);

        target1.performClick();
        target2.performClick();
        back.performClick();
        keyboard.performClick();
        slider.setProgress(80, true);
        activity.onBackPressed();
        done.performClick();

        String logs = joinedQuestionnaireLogs();
        assertTrue(logs.contains("MYQUESTIONNAIRE_MANUAL_GATE_START"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_VISUAL_STAGE stage=manual-hardware-gate"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_INPUT action=Activate source=manual-gate-controller-target"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_INPUT action=Activate source=manual-gate-hand-target"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_INPUT action=Back source=manual-gate-visible-back"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_MANUAL_GATE_EVENT event=hardware-back"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_MANUAL_GATE_EVENT event=keyboard-focus"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_MANUAL_GATE_EVENT event=slider-adjust"));
        assertTrue(logs.contains("MYQUESTIONNAIRE_MANUAL_GATE_READY status=operator-window-complete"));
    }

    private static String joinedQuestionnaireLogs() {
        StringBuilder builder = new StringBuilder();
        for (ShadowLog.LogItem item : ShadowLog.getLogsForTag(AutoSessionRunner.TAG)) {
            builder.append(item.msg).append('\n');
        }
        return builder.toString();
    }

    private static Button findButtonWithText(View view, String text) {
        if (view instanceof Button && text.contentEquals(((Button) view).getText())) {
            return (Button) view;
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                Button found = findButtonWithText(group.getChildAt(i), text);
                if (found != null) {
                    return found;
                }
            }
        }
        return null;
    }

    private static <T extends View> T findViewWithContentDescription(View view, String description, Class<T> type) {
        CharSequence contentDescription = view.getContentDescription();
        if (type.isInstance(view) && contentDescription != null && description.contentEquals(contentDescription)) {
            return type.cast(view);
        }
        if (view instanceof ViewGroup) {
            ViewGroup group = (ViewGroup) view;
            for (int i = 0; i < group.getChildCount(); i++) {
                T found = findViewWithContentDescription(group.getChildAt(i), description, type);
                if (found != null) {
                    return found;
                }
            }
        }
        return null;
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
