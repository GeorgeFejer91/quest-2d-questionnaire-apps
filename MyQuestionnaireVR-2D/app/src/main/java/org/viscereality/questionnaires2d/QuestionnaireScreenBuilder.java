package org.viscereality.questionnaires2d;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.text.InputType;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;

import java.util.List;
import java.util.Locale;

final class QuestionnaireScreenBuilder {
    static final int BACKGROUND = Color.rgb(18, 21, 28);
    static final int PANEL = Color.rgb(31, 36, 48);
    static final int TEXT = Color.rgb(245, 248, 250);
    static final int MUTED = Color.rgb(190, 198, 210);
    static final int ACCENT = Color.rgb(0, 207, 174);
    static final int DANGER = Color.rgb(226, 88, 88);
    static final int CONTROL_TEXT = Color.rgb(20, 24, 32);

    private final Context context;

    QuestionnaireScreenBuilder(Context context) {
        this.context = context;
    }

    LanguageScreen languageScreen() {
        BaseScreen base = base("Questionnaire", false);
        body(base.content, "Choose language.");
        Button english = button("English", true);
        english.setContentDescription("language.english");
        base.content.addView(english);
        Button deutsch = button("Deutsch", true);
        deutsch.setContentDescription("language.deutsch");
        base.content.addView(deutsch);
        return new LanguageScreen(base.root, english, deutsch);
    }

    DemographicsScreen demographicsScreen(QuestionnaireData.LocalizedUiText uiText, DemographicsFixture fixture) {
        BaseScreen base = base(uiText.consent, true);

        EditText nameInput = editText(uiText.inputName);
        nameInput.setContentDescription("demographics.name");
        if (fixture != null) {
            nameInput.setText(fixture.name);
        }
        base.content.addView(label(uiText.inputName));
        base.content.addView(nameInput);

        EditText ageInput = editText(uiText.inputAge);
        ageInput.setContentDescription("demographics.age");
        ageInput.setInputType(InputType.TYPE_CLASS_NUMBER);
        if (fixture != null && fixture.age > 0) {
            ageInput.setText(Integer.toString(fixture.age));
        }
        base.content.addView(label(uiText.inputAge));
        base.content.addView(ageInput);

        base.content.addView(label(uiText.gender));
        RadioGroup genderGroup = new RadioGroup(context);
        genderGroup.setContentDescription("demographics.gender");
        genderGroup.setOrientation(RadioGroup.VERTICAL);
        String[] genders = {uiText.genderFemale, uiText.genderMale, uiText.genderOther, uiText.genderPreferNotToSay};
        for (int i = 0; i < genders.length; i++) {
            RadioButton radio = radio(genders[i]);
            radio.setContentDescription("demographics.gender." + i);
            radio.setLayoutParams(new RadioGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
            genderGroup.addView(radio);
            if (fixture != null && genders[i].equals(fixture.gender)) {
                radio.setChecked(true);
            }
        }
        base.content.addView(genderGroup);

        CheckBox consent = new CheckBox(context);
        consent.setContentDescription("demographics.consent");
        consent.setText(uiText.consentText);
        consent.setTextColor(TEXT);
        consent.setTextSize(20);
        consent.setMinHeight(dp(56));
        if (fixture != null) {
            consent.setChecked(fixture.consent);
        }
        base.content.addView(consent);

        Button submit = button(uiText.submit, true);
        submit.setContentDescription("submit");
        submit.setEnabled(fixture != null && fixture.submitEnabled);
        base.footer.addView(submit, footerButtonLayout(false));
        return new DemographicsScreen(base.root, base.backButton, nameInput, ageInput, genderGroup, consent, submit);
    }

    MaiaScreen maiaScreen(String question, int index, int total, int selectedScore, boolean nextEnabled) {
        BaseScreen base = base("MAIA-2", true);
        body(base.content, String.format(Locale.US, "%d / %d", index + 1, total));
        question(base.content, question);

        RadioGroup scores = new RadioGroup(context);
        scores.setContentDescription("maia.score");
        scores.setOrientation(RadioGroup.VERTICAL);
        String[] labels = {"0 Never", "1", "2", "3", "4", "5 Always"};
        for (int i = 0; i <= 5; i++) {
            RadioButton radio = radio(labels[i]);
            radio.setContentDescription("maia.score." + i);
            radio.setLayoutParams(new RadioGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
            scores.addView(radio);
            if (i == selectedScore) {
                radio.setChecked(true);
            }
        }
        base.content.addView(scores);

        Button next = button(index == total - 1 ? "Continue" : "Next", true);
        next.setContentDescription("maia.next");
        next.setEnabled(nextEnabled);
        base.footer.addView(next, footerButtonLayout(false));
        return new MaiaScreen(base.root, base.backButton, scores, next);
    }

    PictographicScreen pictographicScreen(
        QuestionnaireData.RuntimePictographicPrompt prompt,
        String language,
        Bitmap bitmap,
        int index,
        int total,
        String selectedChoice,
        boolean nextEnabled) {

        BaseScreen base = base("Pictographic Scale", true);
        body(base.content, String.format(Locale.US, "%d / %d", index + 1, total));
        question(base.content, prompt.promptForLanguage(language));

        ImageView image = new ImageView(context);
        image.setContentDescription("pictographic.image." + prompt.id);
        image.setAdjustViewBounds(true);
        image.setMaxHeight(dp(380));
        image.setBackgroundColor(Color.WHITE);
        image.setPadding(dp(8), dp(8), dp(8), dp(8));
        image.setTag(prompt.imageFileName);
        if (bitmap != null) {
            image.setImageBitmap(bitmap);
        }
        base.content.addView(image, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        RadioGroup choices = new RadioGroup(context);
        choices.setContentDescription("pictographic.choice");
        choices.setOrientation(RadioGroup.HORIZONTAL);
        for (String choice : prompt.choices) {
            RadioButton radio = radio(choice);
            radio.setContentDescription("pictographic.choice." + choice);
            radio.setLayoutParams(new RadioGroup.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
            choices.addView(radio);
            if (choice.equals(selectedChoice)) {
                radio.setChecked(true);
            }
        }
        base.content.addView(choices);

        Button next = button(index == total - 1 ? "Continue" : "Next", true);
        next.setContentDescription("pictographic.next");
        next.setEnabled(nextEnabled);
        base.footer.addView(next, footerButtonLayout(false));
        return new PictographicScreen(base.root, base.backButton, image, choices, next);
    }

    SliderScreen sliderScreen(QuestionnaireData.LocalizedUiText uiText, String itemText, int index, int total, int value, boolean answered) {
        return sliderScreen(uiText, itemText, index, total, value, answered, null, null);
    }

    SliderScreen sliderScreen(
        QuestionnaireData.LocalizedUiText uiText,
        String itemText,
        int index,
        int total,
        int value,
        boolean answered,
        String leftAnchorText,
        String rightAnchorText) {

        BaseScreen base = base(uiText.pleaseAnswer, true);
        body(base.content, String.format(Locale.US, "%d / %d", index + 1, total));
        question(base.content, itemText);

        TextView valueText = body(base.content, Integer.toString(value));
        valueText.setContentDescription("slider.value.label");
        valueText.setGravity(Gravity.CENTER);
        valueText.setTextSize(34);

        SeekBar seekBar = new SeekBar(context);
        seekBar.setContentDescription("slider.value");
        seekBar.setMax(100);
        seekBar.setProgress(value);
        base.content.addView(seekBar, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(72)));

        LinearLayout anchors = new LinearLayout(context);
        anchors.setOrientation(LinearLayout.HORIZONTAL);
        TextView left = label(anchorOrDefault(leftAnchorText, uiText.notAtAll));
        left.setContentDescription("slider.anchor.left");
        TextView right = label(anchorOrDefault(rightAnchorText, uiText.extremely));
        right.setContentDescription("slider.anchor.right");
        right.setGravity(Gravity.RIGHT);
        anchors.addView(left, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        anchors.addView(right, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        base.content.addView(anchors);

        Button useCurrent = button("Use current value", false);
        useCurrent.setContentDescription("slider.use-current");
        Button next = button(index == total - 1 ? "Save" : "Next", true);
        next.setContentDescription("slider.next");
        next.setEnabled(answered);
        base.content.addView(useCurrent);
        base.footer.addView(next, footerButtonLayout(false));
        return new SliderScreen(base.root, base.backButton, valueText, seekBar, useCurrent, next);
    }

    SavedScreen savedScreen(String title, String message) {
        BaseScreen base = base(title, false);
        body(base.content, message);
        return new SavedScreen(base.root);
    }

    BlackScreen blackScreen() {
        LinearLayout root = new LinearLayout(context);
        root.setContentDescription("finished-black");
        root.setBackgroundColor(Color.BLACK);
        return new BlackScreen(root);
    }

    ErrorScreen errorScreen(String title, String message) {
        BaseScreen base = base(title, false);
        warning(base.content, message == null ? "Unknown error." : message);
        Button retry = button("Back to language selection", true);
        retry.setContentDescription("error.retry");
        base.content.addView(retry);
        return new ErrorScreen(base.root, retry);
    }

    ManualHardwareGateScreen manualHardwareGateScreen() {
        BaseScreen base = base("Input validation", true);
        body(base.content, "Ready");

        Button controllerTarget = button("Target 1", true);
        controllerTarget.setContentDescription("manual-gate.controller-target");
        base.content.addView(controllerTarget);

        Button handTarget = button("Target 2", true);
        handTarget.setContentDescription("manual-gate.hand-target");
        base.content.addView(handTarget);

        EditText keyboardInput = editText("Keyboard");
        keyboardInput.setContentDescription("manual-gate.keyboard");
        base.content.addView(label("Keyboard"));
        base.content.addView(keyboardInput);

        TextView joystickValue = body(base.content, "50");
        joystickValue.setContentDescription("manual-gate.joystick-value");
        joystickValue.setGravity(Gravity.CENTER);
        joystickValue.setTextSize(30);

        SeekBar joystickSlider = new SeekBar(context);
        joystickSlider.setContentDescription("manual-gate.joystick-slider");
        joystickSlider.setMax(100);
        joystickSlider.setProgress(50);
        base.content.addView(joystickSlider, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(72)));

        Button done = button("Done", true);
        done.setContentDescription("manual-gate.done");
        base.footer.addView(done, footerButtonLayout(false));
        return new ManualHardwareGateScreen(base.root, base.backButton, controllerTarget, handTarget, keyboardInput, joystickValue, joystickSlider, done);
    }

    private BaseScreen base(String title, boolean showBack) {
        LinearLayout root = new LinearLayout(context);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BACKGROUND);
        root.setPadding(dp(32), dp(24), dp(32), dp(24));

        TextView heading = new TextView(context);
        heading.setContentDescription("screen.heading");
        heading.setText(title);
        heading.setTextColor(TEXT);
        heading.setTextSize(30);
        heading.setGravity(Gravity.LEFT);
        heading.setPadding(0, 0, 0, dp(18));
        root.addView(heading, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        ScrollView scroll = new ScrollView(context);
        scroll.setContentDescription("screen.scroll");
        scroll.setFillViewport(false);
        LinearLayout content = new LinearLayout(context);
        content.setContentDescription("screen.content");
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(20), dp(20), dp(20), dp(20));
        content.setBackgroundColor(PANEL);
        scroll.addView(content);
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        Button back = null;
        LinearLayout footer = null;
        if (showBack) {
            footer = new LinearLayout(context);
            footer.setOrientation(LinearLayout.HORIZONTAL);
            back = button("Back", false);
            back.setContentDescription("navigation.back");
            footer.addView(back, footerButtonLayout(true));
            root.addView(footer, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(82)));
        }

        return new BaseScreen(root, content, footer, back);
    }

    private TextView body(LinearLayout parent, String text) {
        TextView view = label(text);
        view.setTextColor(MUTED);
        view.setPadding(0, 0, 0, dp(14));
        parent.addView(view);
        return view;
    }

    private void question(LinearLayout parent, String text) {
        TextView view = label(text);
        view.setContentDescription("screen.question");
        view.setTextColor(TEXT);
        view.setTextSize(23);
        view.setPadding(0, dp(8), 0, dp(20));
        parent.addView(view);
    }

    private void warning(LinearLayout parent, String text) {
        TextView view = label(text);
        view.setTextColor(DANGER);
        parent.addView(view);
    }

    private TextView label(String text) {
        TextView view = new TextView(context);
        view.setText(text);
        view.setTextColor(TEXT);
        view.setTextSize(20);
        view.setLineSpacing(2f, 1.08f);
        view.setPadding(0, dp(8), 0, dp(8));
        return view;
    }

    private EditText editText(String hint) {
        EditText input = new EditText(context);
        input.setHint(hint);
        input.setTextSize(20);
        input.setSingleLine(true);
        input.setMinHeight(dp(58));
        input.setTextColor(CONTROL_TEXT);
        input.setHintTextColor(Color.rgb(90, 96, 108));
        input.setBackgroundColor(Color.WHITE);
        input.setPadding(dp(16), 0, dp(16), 0);
        return input;
    }

    private RadioButton radio(String text) {
        RadioButton button = new RadioButton(context);
        button.setText(text);
        button.setTextColor(TEXT);
        button.setTextSize(20);
        button.setMinHeight(dp(56));
        button.setPadding(0, 0, dp(18), 0);
        return button;
    }

    private Button button(String text, boolean primary) {
        Button button = new Button(context);
        button.setText(text);
        button.setAllCaps(false);
        button.setTextSize(20);
        button.setMinHeight(dp(58));
        button.setTextColor(primary ? CONTROL_TEXT : TEXT);
        button.setBackgroundColor(primary ? ACCENT : Color.rgb(62, 70, 88));
        LinearLayout.LayoutParams layout = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(62));
        layout.setMargins(0, dp(10), 0, dp(10));
        button.setLayoutParams(layout);
        return button;
    }

    private LinearLayout.LayoutParams footerButtonLayout(boolean left) {
        LinearLayout.LayoutParams layout = new LinearLayout.LayoutParams(0, dp(62), 1f);
        layout.setMargins(left ? 0 : dp(8), dp(10), left ? dp(8) : 0, dp(10));
        return layout;
    }

    private int dp(float value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }

    private static String anchorOrDefault(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }
        return value;
    }

    static final class DemographicsFixture {
        String name = "";
        int age;
        String gender = "";
        boolean consent;
        boolean submitEnabled;
    }

    private static final class BaseScreen {
        final LinearLayout root;
        final LinearLayout content;
        final LinearLayout footer;
        final Button backButton;

        BaseScreen(LinearLayout root, LinearLayout content, LinearLayout footer, Button backButton) {
            this.root = root;
            this.content = content;
            this.footer = footer;
            this.backButton = backButton;
        }
    }

    static final class LanguageScreen {
        final LinearLayout root;
        final Button english;
        final Button deutsch;

        LanguageScreen(LinearLayout root, Button english, Button deutsch) {
            this.root = root;
            this.english = english;
            this.deutsch = deutsch;
        }
    }

    static final class DemographicsScreen {
        final LinearLayout root;
        final Button backButton;
        final EditText nameInput;
        final EditText ageInput;
        final RadioGroup genderGroup;
        final CheckBox consent;
        final Button submit;

        DemographicsScreen(LinearLayout root, Button backButton, EditText nameInput, EditText ageInput, RadioGroup genderGroup, CheckBox consent, Button submit) {
            this.root = root;
            this.backButton = backButton;
            this.nameInput = nameInput;
            this.ageInput = ageInput;
            this.genderGroup = genderGroup;
            this.consent = consent;
            this.submit = submit;
        }
    }

    static final class MaiaScreen {
        final LinearLayout root;
        final Button backButton;
        final RadioGroup scores;
        final Button next;

        MaiaScreen(LinearLayout root, Button backButton, RadioGroup scores, Button next) {
            this.root = root;
            this.backButton = backButton;
            this.scores = scores;
            this.next = next;
        }
    }

    static final class PictographicScreen {
        final LinearLayout root;
        final Button backButton;
        final ImageView image;
        final RadioGroup choices;
        final Button next;

        PictographicScreen(LinearLayout root, Button backButton, ImageView image, RadioGroup choices, Button next) {
            this.root = root;
            this.backButton = backButton;
            this.image = image;
            this.choices = choices;
            this.next = next;
        }
    }

    static final class SliderScreen {
        final LinearLayout root;
        final Button backButton;
        final TextView valueText;
        final SeekBar seekBar;
        final Button useCurrent;
        final Button next;

        SliderScreen(LinearLayout root, Button backButton, TextView valueText, SeekBar seekBar, Button useCurrent, Button next) {
            this.root = root;
            this.backButton = backButton;
            this.valueText = valueText;
            this.seekBar = seekBar;
            this.useCurrent = useCurrent;
            this.next = next;
        }
    }

    static final class SavedScreen {
        final LinearLayout root;

        SavedScreen(LinearLayout root) {
            this.root = root;
        }
    }

    static final class BlackScreen {
        final LinearLayout root;

        BlackScreen(LinearLayout root) {
            this.root = root;
        }
    }

    static final class ErrorScreen {
        final LinearLayout root;
        final Button retry;

        ErrorScreen(LinearLayout root, Button retry) {
            this.root = root;
            this.retry = retry;
        }
    }

    static final class ManualHardwareGateScreen {
        final LinearLayout root;
        final Button visibleBack;
        final Button controllerTarget;
        final Button handTarget;
        final EditText keyboardInput;
        final TextView joystickValue;
        final SeekBar joystickSlider;
        final Button done;

        ManualHardwareGateScreen(
            LinearLayout root,
            Button visibleBack,
            Button controllerTarget,
            Button handTarget,
            EditText keyboardInput,
            TextView joystickValue,
            SeekBar joystickSlider,
            Button done) {
            this.root = root;
            this.visibleBack = visibleBack;
            this.controllerTarget = controllerTarget;
            this.handTarget = handTarget;
            this.keyboardInput = keyboardInput;
            this.joystickValue = joystickValue;
            this.joystickSlider = joystickSlider;
            this.done = done;
        }
    }
}
