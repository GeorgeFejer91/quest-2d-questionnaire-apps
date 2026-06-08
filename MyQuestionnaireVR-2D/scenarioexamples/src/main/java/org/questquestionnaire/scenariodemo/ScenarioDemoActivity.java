package org.questquestionnaire.scenariodemo;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Bundle;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;

import java.util.Locale;

public final class ScenarioDemoActivity extends Activity {
    private static final String QUESTIONNAIRE_PACKAGE = "org.questquestionnaire.questionnaires2d";
    private static final String QUESTIONNAIRE_ACTION = "org.questquestionnaire.questionnaires2d.RUN";
    private final int[] colors = {
            Color.rgb(20, 220, 70),
            Color.rgb(20, 90, 255),
            Color.rgb(245, 30, 25)
    };
    private int triggerIndex = 0;
    private CircleView circleView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        circleView = new CircleView();
        setContentView(circleView);
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (event.getAction() == KeyEvent.ACTION_DOWN
                && (event.getKeyCode() == KeyEvent.KEYCODE_SPACE
                || event.getKeyCode() == KeyEvent.KEYCODE_ENTER
                || event.getKeyCode() == KeyEvent.KEYCODE_BUTTON_A
                || event.getKeyCode() == KeyEvent.KEYCODE_BUTTON_SELECT
                || event.getKeyCode() == KeyEvent.KEYCODE_BUTTON_R1
                || event.getKeyCode() == KeyEvent.KEYCODE_BUTTON_L1)) {
            fireCurrentTrigger();
            return true;
        }
        return super.dispatchKeyEvent(event);
    }

    private void fireCurrentTrigger() {
        if (triggerIndex >= BuildConfig.TRIGGER_COUNT) {
            return;
        }
        String triggerId = String.format(Locale.US, "trigger_%d_complete", triggerIndex + 1);
        Intent intent = new Intent(QUESTIONNAIRE_ACTION);
        intent.setPackage(QUESTIONNAIRE_PACKAGE);
        intent.putExtra("mq.triggerId", triggerId);
        intent.putExtra("mq.scenarioId", BuildConfig.SCENARIO_ID);
        intent.putExtra("mq.triggerSource", BuildConfig.TRIGGER_SOURCE);
        intent.putExtra("mq.finishBehavior", "resumeCaller");
        intent.putExtra("mq.callerPackage", getPackageName());
        intent.putExtra("mq.callerActivity", getClass().getName());
        intent.putExtra("mq.triggerTimestampUnixMs", String.valueOf(System.currentTimeMillis()));
        try {
            startActivity(intent);
        } catch (ActivityNotFoundException ignored) {
            // The demo remains usable as a visual/local scanner target when no questionnaire APK is installed.
        }
        triggerIndex += 1;
        if (triggerIndex >= BuildConfig.TRIGGER_COUNT) {
            triggerIndex = BuildConfig.TRIGGER_COUNT - 1;
        }
        if (circleView != null) {
            circleView.invalidate();
        }
    }

    private final class CircleView extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint textPaint = new Paint(Paint.ANTI_ALIAS_FLAG);

        CircleView() {
            super(ScenarioDemoActivity.this);
            setFocusable(true);
            setFocusableInTouchMode(true);
            textPaint.setColor(Color.WHITE);
            textPaint.setTextAlign(Paint.Align.CENTER);
            textPaint.setTextSize(42f);
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            if (event.getAction() == MotionEvent.ACTION_DOWN) {
                fireCurrentTrigger();
                return true;
            }
            return true;
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            canvas.drawColor(Color.BLACK);
            int index = Math.max(0, Math.min(triggerIndex, BuildConfig.TRIGGER_COUNT - 1));
            paint.setColor(colors[index % colors.length]);
            float radius = Math.min(getWidth(), getHeight()) * 0.32f;
            canvas.drawCircle(getWidth() / 2f, getHeight() / 2f, radius, paint);
            String label = String.format(Locale.US, "Trigger %d of %d", index + 1, BuildConfig.TRIGGER_COUNT);
            canvas.drawText(label, getWidth() / 2f, getHeight() - 96f, textPaint);
        }
    }
}
