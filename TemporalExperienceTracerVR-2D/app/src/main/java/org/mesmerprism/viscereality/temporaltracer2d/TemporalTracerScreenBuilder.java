package org.mesmerprism.viscereality.temporaltracer2d;

import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.List;
import java.util.Locale;

final class TemporalTracerScreenBuilder {
    private static final int BG = Color.rgb(17, 19, 24);
    private static final int PANEL = Color.rgb(27, 31, 38);
    private static final int TEXT = Color.rgb(244, 245, 247);
    private static final int MUTED = Color.rgb(166, 174, 186);
    private static final int ACCENT = Color.rgb(40, 209, 124);

    private final Context context;

    TemporalTracerScreenBuilder(Context context) {
        this.context = context;
    }

    LanguageScreen languageScreen(TemporalTracerConfig config, View.OnClickListener english, View.OnClickListener german) {
        LinearLayout root = baseRoot();
        root.setGravity(Gravity.CENTER);

        TextView title = title(config.ui("English").languageTitle + " / " + config.ui("Deutsch").languageTitle);
        title.setGravity(Gravity.CENTER);
        root.addView(title, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        LinearLayout row = new LinearLayout(context);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER);
        row.setPadding(0, dp(28), 0, 0);
        Button en = primaryButton("English");
        en.setOnClickListener(english);
        Button de = secondaryButton("Deutsch");
        de.setOnClickListener(german);
        row.addView(en, new LinearLayout.LayoutParams(dp(220), dp(64)));
        LinearLayout.LayoutParams deParams = new LinearLayout.LayoutParams(dp(220), dp(64));
        deParams.leftMargin = dp(18);
        row.addView(de, deParams);
        root.addView(row);
        return new LanguageScreen(root);
    }

    ParticipantScreen participantScreen(TemporalTracerConfig.UiText ui, TemporalTracerLaunchContext launch, View.OnClickListener onContinue, View.OnClickListener onBack) {
        LinearLayout root = baseRoot();
        root.setGravity(Gravity.CENTER);

        LinearLayout panel = panel();
        panel.setPadding(dp(36), dp(32), dp(36), dp(32));
        TextView title = title(ui.participantTitle);
        panel.addView(title);

        EditText participantName = editText(ui.participantNameHint);
        participantName.setText(launch.participantName);
        panel.addView(participantName, lpMatchWrap(dp(18)));

        EditText participantId = editText(ui.participantIdHint);
        participantId.setText(launch.participantId);
        panel.addView(participantId, lpMatchWrap(dp(12)));

        LinearLayout row = buttonRow();
        Button back = secondaryButton(ui.backLabel);
        back.setOnClickListener(onBack);
        Button next = primaryButton(ui.continueLabel);
        next.setOnClickListener(onContinue);
        row.addView(back, new LinearLayout.LayoutParams(dp(180), dp(56)));
        LinearLayout.LayoutParams nextParams = new LinearLayout.LayoutParams(dp(220), dp(56));
        nextParams.leftMargin = dp(12);
        row.addView(next, nextParams);
        panel.addView(row, lpMatchWrap(dp(22)));

        root.addView(panel, new LinearLayout.LayoutParams(Math.min(dp(620), screenWidthFallback()), ViewGroup.LayoutParams.WRAP_CONTENT));
        return new ParticipantScreen(root, participantName, participantId);
    }

    TraceScreen traceScreen(
        TemporalTracerConfig.UiText ui,
        TemporalTracerConfig.AxisConfig axis,
        String language,
        TemporalTracerConfig.TraceItem item,
        int index,
        int total,
        View.OnClickListener onBack,
        View.OnClickListener onClear,
        View.OnClickListener onSave) {
        LinearLayout root = baseRoot();
        root.setPadding(dp(18), dp(14), dp(18), dp(14));

        LinearLayout header = new LinearLayout(context);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = text(ui.appTitle, 22, true, TEXT);
        header.addView(title, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        TextView progress = text(String.format(Locale.US, "%d / %d", index + 1, total), 16, true, MUTED);
        progress.setGravity(Gravity.RIGHT);
        header.addView(progress, new LinearLayout.LayoutParams(dp(120), ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(header);

        TextView label = text(item.label, 18, true, ACCENT);
        label.setPadding(0, dp(8), 0, dp(2));
        root.addView(label);

        ScrollView messageScroll = new ScrollView(context);
        TextView message = text(item.message, 15, false, TEXT);
        message.setLineSpacing(dp(2), 1.0f);
        message.setPadding(dp(2), dp(2), dp(2), dp(8));
        messageScroll.addView(message);
        root.addView(messageScroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(116)));

        TraceCanvasView canvas = new TraceCanvasView(context);
        canvas.configure(axis, language);
        root.addView(canvas, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        LinearLayout footer = new LinearLayout(context);
        footer.setOrientation(LinearLayout.HORIZONTAL);
        footer.setGravity(Gravity.CENTER_VERTICAL);
        TextView status = text(ui.completeToSaveLabel, 15, true, MUTED);
        footer.addView(status, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        Button back = secondaryButton(ui.backLabel);
        back.setOnClickListener(onBack);
        footer.addView(back, new LinearLayout.LayoutParams(dp(130), dp(54)));
        Button clear = secondaryButton(ui.clearLabel);
        clear.setOnClickListener(onClear);
        LinearLayout.LayoutParams clearParams = new LinearLayout.LayoutParams(dp(170), dp(54));
        clearParams.leftMargin = dp(10);
        footer.addView(clear, clearParams);
        Button save = primaryButton(ui.saveNextLabel);
        save.setEnabled(false);
        save.setOnClickListener(onSave);
        LinearLayout.LayoutParams saveParams = new LinearLayout.LayoutParams(dp(170), dp(54));
        saveParams.leftMargin = dp(10);
        footer.addView(save, saveParams);
        root.addView(footer, lpMatchWrap(dp(12)));

        return new TraceScreen(root, canvas, status, save);
    }

    SavedScreen savedScreen(TemporalTracerConfig.UiText ui, String body, View.OnClickListener onDone) {
        LinearLayout root = baseRoot();
        root.setGravity(Gravity.CENTER);
        LinearLayout panel = panel();
        panel.setPadding(dp(36), dp(32), dp(36), dp(32));
        TextView title = title(ui.savedTitle);
        panel.addView(title);
        TextView text = text(body, 15, false, TEXT);
        text.setPadding(0, dp(16), 0, dp(20));
        panel.addView(text);
        Button done = primaryButton(ui.continueLabel);
        done.setOnClickListener(onDone);
        panel.addView(done, new LinearLayout.LayoutParams(dp(220), dp(56)));
        root.addView(panel, new LinearLayout.LayoutParams(Math.min(dp(760), screenWidthFallback()), ViewGroup.LayoutParams.WRAP_CONTENT));
        return new SavedScreen(root);
    }

    View blackScreen() {
        TextView view = new TextView(context);
        view.setBackgroundColor(Color.BLACK);
        view.setTextColor(Color.BLACK);
        view.setText("");
        return view;
    }

    private LinearLayout baseRoot() {
        LinearLayout root = new LinearLayout(context);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);
        root.setPadding(dp(28), dp(24), dp(28), dp(24));
        return root;
    }

    private LinearLayout panel() {
        LinearLayout panel = new LinearLayout(context);
        panel.setOrientation(LinearLayout.VERTICAL);
        panel.setBackgroundColor(PANEL);
        return panel;
    }

    private LinearLayout buttonRow() {
        LinearLayout row = new LinearLayout(context);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.RIGHT);
        return row;
    }

    private TextView title(String value) {
        return text(value, 26, true, TEXT);
    }

    private TextView text(String value, int sp, boolean bold, int color) {
        TextView view = new TextView(context);
        view.setText(value);
        view.setTextColor(color);
        view.setTextSize(sp);
        view.setIncludeFontPadding(true);
        if (bold) {
            view.setTypeface(Typeface.DEFAULT, Typeface.BOLD);
        }
        return view;
    }

    private EditText editText(String hint) {
        EditText input = new EditText(context);
        input.setHint(hint);
        input.setSingleLine(true);
        input.setTextColor(Color.BLACK);
        input.setHintTextColor(Color.rgb(90, 96, 106));
        input.setTextSize(17);
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_NORMAL);
        return input;
    }

    private Button primaryButton(String label) {
        Button button = new Button(context);
        button.setText(label);
        button.setTextSize(15);
        button.setAllCaps(false);
        button.setTextColor(Color.rgb(5, 22, 16));
        return button;
    }

    private Button secondaryButton(String label) {
        Button button = new Button(context);
        button.setText(label);
        button.setTextSize(15);
        button.setAllCaps(false);
        return button;
    }

    private LinearLayout.LayoutParams lpMatchWrap(int topMargin) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.topMargin = topMargin;
        return params;
    }

    private int dp(float value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }

    private int screenWidthFallback() {
        return Math.max(dp(360), context.getResources().getDisplayMetrics().widthPixels - dp(56));
    }

    static final class LanguageScreen {
        final View root;

        LanguageScreen(View root) {
            this.root = root;
        }
    }

    static final class ParticipantScreen {
        final View root;
        final EditText participantName;
        final EditText participantId;

        ParticipantScreen(View root, EditText participantName, EditText participantId) {
            this.root = root;
            this.participantName = participantName;
            this.participantId = participantId;
        }
    }

    static final class TraceScreen {
        final View root;
        final TraceCanvasView traceCanvas;
        final TextView status;
        final Button saveButton;

        TraceScreen(View root, TraceCanvasView traceCanvas, TextView status, Button saveButton) {
            this.root = root;
            this.traceCanvas = traceCanvas;
            this.status = status;
            this.saveButton = saveButton;
        }
    }

    static final class SavedScreen {
        final View root;

        SavedScreen(View root) {
            this.root = root;
        }
    }
}
