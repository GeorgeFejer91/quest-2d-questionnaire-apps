package org.questquestionnaire.questionnaires2d;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.util.Log;
import android.view.Gravity;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.CompoundButton;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.RadioButton;
import android.widget.RadioGroup;
import android.widget.ScrollView;
import android.widget.SeekBar;
import android.widget.TextView;

import java.io.File;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public final class MainActivity extends Activity {
    private static final int BACKGROUND = Color.rgb(18, 21, 28);
    private static final int PANEL = Color.rgb(31, 36, 48);
    private static final int TEXT = Color.rgb(245, 248, 250);
    private static final int MUTED = Color.rgb(190, 198, 210);
    private static final int ACCENT = Color.rgb(0, 207, 174);
    private static final int DANGER = Color.rgb(226, 88, 88);
    private static final int CONTROL_TEXT = Color.rgb(20, 24, 32);
    private static final float JOYSTICK_LOG_THRESHOLD = 0.25f;
    private static final long JOYSTICK_LOG_INTERVAL_MS = 350L;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private QuestionnaireData.RuntimeConfig runtimeConfig;
    private QuestionnaireData.LocalizedUiText uiText;
    private QuestionnaireData.ParticipantInfo participant;
    private List<String> maiaQuestions = new ArrayList<>();
    private List<String> sliderQuestions = new ArrayList<>();
    private List<QuestionnaireData.RuntimePictographicPrompt> pictographicPrompts = new ArrayList<>();
    private final List<QuestionnaireData.Maia2Answer> maia2Answers = new ArrayList<>();
    private final List<QuestionnaireData.PictographicSelection> pictographicSelections = new ArrayList<>();
    private final List<QuestionnaireData.QuestionnaireAnswer> questionnaireAnswers = new ArrayList<>();
    private QuestionnaireScreenBuilder screenBuilder;
    private int currentMaiaIndex;
    private int currentPictographicIndex;
    private int currentQuestionIndex;
    private String currentScreen = "boot";
    private QuestionnaireScreenBuilder.LanguageScreen activeLanguageScreen;
    private QuestionnaireScreenBuilder.DemographicsScreen activeDemographicsScreen;
    private QuestionnaireScreenBuilder.MaiaScreen activeMaiaScreen;
    private QuestionnaireScreenBuilder.PictographicScreen activePictographicScreen;
    private QuestionnaireScreenBuilder.SliderScreen activeSliderScreen;
    private long lastJoystickLogMillis;
    private QuestionnaireLaunchContext launchContext;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        screenBuilder = new QuestionnaireScreenBuilder(this);
        startSessionFromIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        startSessionFromIntent(intent);
    }

    private void startSessionFromIntent(Intent intent) {
        handler.removeCallbacksAndMessages(null);
        try {
            runtimeConfig = QuestionnaireLoader.loadRuntimeConfig(this);
            setTitle(runtimeConfig.displayTitle());
            screenBuilder.setAppTitle(runtimeConfig.displayTitle());
            launchContext = QuestionnaireLaunchContext.fromIntent(intent, runtimeConfig);
            resetSessionState();
            maiaQuestions = runtimeConfig.findBlock("maia2") != null
                ? QuestionnaireLoader.loadMaia2Questions(this)
                : new ArrayList<>();
            pictographicPrompts = loadPictographicPrompts();
            updateDraftQuietly("launched");

            AutoSessionRunner.Mode autoMode = AutoSessionRunner.detect(getExternalFilesDir(null));
            if (autoMode != null) {
                runCommandReplayThroughUi(autoMode);
                return;
            }

            File manualGateMarker = AutoSessionRunner.manualHardwareGateMarker(getExternalFilesDir(null));
            if (manualGateMarker != null && manualGateMarker.exists()) {
                showManualHardwareGate(manualGateMarker);
                return;
            }

            if (launchContext != null && !isBlank(launchContext.language)) {
                Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_CHAIN_LAUNCH runId=" + launchContext.runId
                    + " finishBehavior=" + launchContext.finishBehavior
                    + " language=" + launchContext.language);
                loadLanguage(launchContext.language);
            } else {
                showLanguageSelection();
            }
        } catch (Exception exception) {
            Log.e(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_BOOT_ERROR " + exception.getMessage(), exception);
            showError("Questionnaire setup error", exception.getMessage());
        }
    }

    @Override
    public void onBackPressed() {
        logUiInput("Back", "hardware-back");
        handleBack();
    }

    @Override
    public boolean dispatchTouchEvent(MotionEvent event) {
        if (event.getActionMasked() == MotionEvent.ACTION_DOWN) {
            Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_INPUT_TOUCH action=down screen=" + currentScreen
                + " sourceFlags=" + sourceFlags(event.getSource())
                + " toolType=" + toolTypeName(event.getToolType(0)));
        }
        return super.dispatchTouchEvent(event);
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (event.getAction() == KeyEvent.ACTION_DOWN) {
            Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_INPUT_KEY action=down screen=" + currentScreen
                + " keyCode=" + event.getKeyCode()
                + " keyName=" + KeyEvent.keyCodeToString(event.getKeyCode())
                + " sourceFlags=" + sourceFlags(event.getSource()));
        }
        return super.dispatchKeyEvent(event);
    }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent event) {
        if (event.getActionMasked() == MotionEvent.ACTION_MOVE
            && (event.getSource() & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK) {
            float x = event.getAxisValue(MotionEvent.AXIS_X);
            float y = event.getAxisValue(MotionEvent.AXIS_Y);
            if (Math.abs(x) >= JOYSTICK_LOG_THRESHOLD || Math.abs(y) >= JOYSTICK_LOG_THRESHOLD) {
                long now = event.getEventTime();
                if (now - lastJoystickLogMillis >= JOYSTICK_LOG_INTERVAL_MS) {
                    lastJoystickLogMillis = now;
                    Log.i(AutoSessionRunner.TAG, String.format(Locale.US,
                        "MYQUESTIONNAIRE_INPUT_JOYSTICK action=move screen=%s x=%.3f y=%.3f sourceFlags=%s",
                        currentScreen,
                        x,
                        y,
                        sourceFlags(event.getSource())));
                }
            }
        }
        return super.dispatchGenericMotionEvent(event);
    }

    private List<QuestionnaireData.RuntimePictographicPrompt> loadPictographicPrompts() {
        QuestionnaireData.RuntimeBlock block = runtimeConfig != null ? runtimeConfig.findBlock("pictographic") : null;
        if (block != null && !block.prompts.isEmpty()) {
            return block.prompts;
        }

        return new ArrayList<>();
    }

    private void runCommandReplayThroughUi(AutoSessionRunner.Mode mode) throws Exception {
        if (mode.commandReplay) {
            Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_COMMAND_REPLAY_START language=" + mode.language);
        } else {
            Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_AUTO_VALIDATION_START language=" + mode.language);
        }

        AutoSessionRunner.Plan plan = AutoSessionRunner.readPlan(mode);
        QuestionnaireScreenBuilder.LanguageScreen languageScreen = showLanguageSelection();
        logReplayCommand("Activate", "language-" + mode.language);
        if ("Deutsch".equals(mode.language)) {
            languageScreen.deutsch.performClick();
        } else {
            languageScreen.english.performClick();
        }

        if ("demographics".equals(currentScreen)) {
            fillDemographicsForReplay(plan);
            activeDemographicsScreen.submit.performClick();
        }

        while ("maia".equals(currentScreen)) {
            int score = AutoSessionRunner.valueAt(plan.maiaScores, currentMaiaIndex, currentMaiaIndex % 6, 0, 5);
            RadioButton choice = (RadioButton) activeMaiaScreen.scores.getChildAt(score);
            logReplayCommand("TriggerSelect", "maia2-" + (currentMaiaIndex + 1) + "-score-" + score);
            choice.performClick();
            activeMaiaScreen.next.performClick();
        }

        while ("pictographic".equals(currentScreen)) {
            QuestionnaireData.RuntimePictographicPrompt prompt = pictographicPrompts.get(currentPictographicIndex);
            String selectedChoice = AutoSessionRunner.choiceAt(plan.pictographicChoices, currentPictographicIndex, prompt.choices);
            selectRadioByText(activePictographicScreen.choices, selectedChoice);
            logReplayCommand("TriggerSelect", "pictographic-" + prompt.id + "-" + selectedChoice);
            activePictographicScreen.next.performClick();
        }

        while ("slider".equals(currentScreen)) {
            int score = AutoSessionRunner.valueAt(plan.questionnaireScores, currentQuestionIndex, (currentQuestionIndex * 7) % 101, 0, 100);
            activeSliderScreen.seekBar.setProgress(score);
            logReplayCommand("TriggerSelect", "slider-" + (currentQuestionIndex + 1) + "-score-" + score);
            activeSliderScreen.useCurrent.performClick();
            activeSliderScreen.next.performClick();
        }

        if (mode.commandReplay) {
            Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_COMMAND_REPLAY_EXPORT_MATCH participant=" + participant.name + " language=" + participant.language);
            Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_NAVIGATION_SUMMARY status=pass mode=command-replay commands=" + replayCommandCount());
        }
        AutoSessionRunner.tryDelete(mode.markerFile);
    }

    private void fillDemographicsForReplay(AutoSessionRunner.Plan plan) {
        logReplayCommand("TextInput", "demographics-name");
        activeDemographicsScreen.nameInput.setText(plan.participantName);
        logReplayCommand("TextInput", "demographics-age");
        activeDemographicsScreen.ageInput.setText(Integer.toString(plan.age));
        selectRadioByText(activeDemographicsScreen.genderGroup, plan.gender);
        logReplayCommand("TriggerSelect", "demographics-gender-" + plan.gender);
        activeDemographicsScreen.consent.performClick();
        logReplayCommand("TriggerSelect", "demographics-consent");
    }

    private void selectRadioByText(RadioGroup group, String text) {
        String wanted = text == null ? "" : text.trim();
        for (int i = 0; i < group.getChildCount(); i++) {
            View child = group.getChildAt(i);
            if (child instanceof RadioButton) {
                RadioButton radio = (RadioButton) child;
                if (radio.getText().toString().trim().equalsIgnoreCase(wanted)) {
                    radio.performClick();
                    return;
                }
            }
        }

        if (group.getChildCount() > 0 && group.getChildAt(0) instanceof RadioButton) {
            ((RadioButton) group.getChildAt(0)).performClick();
        }
    }

    private int replayCommandCount() {
        return 1 + 4 + maiaQuestions.size() + pictographicPrompts.size() + sliderQuestions.size();
    }

    private void logReplayCommand(String command, String source) {
        Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_COMMAND command=" + command + " source=" + source);
    }

    private void logUiInput(String action, String source) {
        Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_INPUT action=" + action + " source=" + source + " screen=" + currentScreen);
    }

    private void logVisualStage(String stage, String screenId) {
        Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_VISUAL_STAGE stage=" + stage + " screen=" + screenId);
    }

    private void logManualGateEvent(String event, String source) {
        Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_MANUAL_GATE_EVENT event=" + event + " source=" + source + " screen=" + currentScreen);
    }

    private void showManualHardwareGate(File markerFile) {
        currentScreen = "manual-hardware-gate";
        Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_MANUAL_GATE_START marker=\"" + markerFile.getAbsolutePath() + "\"");
        AutoSessionRunner.tryDelete(markerFile);

        QuestionnaireScreenBuilder.ManualHardwareGateScreen screen = screenBuilder.manualHardwareGateScreen();
        screen.controllerTarget.setOnClickListener(v -> {
            logUiInput("Activate", "manual-gate-controller-target");
            logManualGateEvent("controller-target", "manual-gate-controller-target");
        });
        screen.handTarget.setOnClickListener(v -> {
            logUiInput("Activate", "manual-gate-hand-target");
            logManualGateEvent("hand-target", "manual-gate-hand-target");
        });
        if (screen.visibleBack != null) {
            screen.visibleBack.setOnClickListener(v -> {
                logUiInput("Back", "manual-gate-visible-back");
                logManualGateEvent("visible-back", "manual-gate-visible-back");
            });
        }
        screen.keyboardInput.setOnClickListener(v -> {
            logUiInput("TextFocus", "manual-gate-keyboard");
            logManualGateEvent("keyboard-focus", "manual-gate-keyboard");
        });
        screen.keyboardInput.setOnFocusChangeListener((view, hasFocus) -> {
            if (hasFocus) {
                logUiInput("TextFocus", "manual-gate-keyboard");
                logManualGateEvent("keyboard-focus", "manual-gate-keyboard");
            }
        });
        screen.joystickSlider.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar bar, int progress, boolean fromUser) {
                screen.joystickValue.setText(Integer.toString(progress));
                logUiInput("SliderAdjust", "manual-gate-slider-" + progress);
                logManualGateEvent("slider-adjust", "manual-gate-slider-" + progress);
            }

            @Override
            public void onStartTrackingTouch(SeekBar bar) {
                logUiInput("SliderTouchStart", "manual-gate-slider");
            }

            @Override
            public void onStopTrackingTouch(SeekBar bar) {
                logUiInput("SliderTouchStop", "manual-gate-slider-" + bar.getProgress());
            }
        });
        screen.done.setOnClickListener(v -> {
            logUiInput("Activate", "manual-gate-done");
            logManualGateEvent("done", "manual-gate-done");
            Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_MANUAL_GATE_READY status=operator-window-complete");
        });
        setContentView(screen.root);
        logVisualStage("manual-hardware-gate", "manual-hardware-gate");
    }

    private QuestionnaireScreenBuilder.LanguageScreen showLanguageSelection() {
        currentScreen = "language";
        QuestionnaireScreenBuilder.LanguageScreen screen = screenBuilder.languageScreen();
        activeLanguageScreen = screen;
        screen.english.setOnClickListener(v -> {
            logUiInput("Activate", "language-English");
            loadLanguage("English");
        });
        screen.deutsch.setOnClickListener(v -> {
            logUiInput("Activate", "language-Deutsch");
            loadLanguage("Deutsch");
        });
        setContentView(screen.root);
        logVisualStage("language", "language");
        return screen;
    }

    private void loadLanguage(String language) {
        try {
            String normalized = QuestionnaireLoader.normalizeLanguage(language);
            uiText = QuestionnaireLoader.loadUiText(this, normalized);
            sliderQuestions = runtimeConfig.findBlock("custom_slider") != null
                ? QuestionnaireLoader.loadQuestions(this, normalized)
                : new ArrayList<>();
            participant = new QuestionnaireData.ParticipantInfo();
            participant.language = normalized;
            participant.participantId = launchContext != null ? launchContext.participantIdOrRunId() : TimeUtil.newRunId();
            if (launchContext != null && !isBlank(launchContext.participantName)) {
                participant.name = launchContext.participantName;
            }
            maia2Answers.clear();
            pictographicSelections.clear();
            questionnaireAnswers.clear();
            updateDraftQuietly("language-selected");
            if (launchContext != null && !launchContext.shouldRunDemographics()) {
                if (isBlank(participant.name)) {
                    participant.name = launchContext.participantIdOrRunId();
                }
                showNextConfiguredModule(null);
                return;
            }
            showParticipantForm();
        } catch (Exception exception) {
            Log.e(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_LANGUAGE_LOAD_ERROR " + exception.getMessage(), exception);
            showError("Could not load questionnaire", exception.getMessage());
        }
    }

    private QuestionnaireScreenBuilder.DemographicsScreen showParticipantForm() {
        currentScreen = "demographics";
        QuestionnaireScreenBuilder.DemographicsFixture fixture = null;
        if (participant != null && !isBlank(participant.name)) {
            fixture = new QuestionnaireScreenBuilder.DemographicsFixture();
            fixture.name = participant.name;
        }
        QuestionnaireScreenBuilder.DemographicsScreen screen =
            screenBuilder.demographicsScreen(uiText, fixture);
        activeDemographicsScreen = screen;
        if (screen.backButton != null) {
            screen.backButton.setOnClickListener(v -> {
                logUiInput("Back", "demographics-visible-back");
                handleBack();
            });
        }

        Runnable validate = () -> {
            boolean hasName = screen.nameInput.getText().toString().trim().length() > 0;
            boolean validAge = parseAge(screen.ageInput.getText().toString()) > 0;
            boolean validGender = screen.genderGroup.getCheckedRadioButtonId() != View.NO_ID;
            screen.submit.setEnabled(hasName && validAge && validGender && screen.consent.isChecked());
        };

        TextWatcher watcher = new SimpleWatcher(validate);
        screen.nameInput.addTextChangedListener(watcher);
        screen.ageInput.addTextChangedListener(watcher);
        screen.genderGroup.setOnCheckedChangeListener((group, checkedId) -> {
            RadioButton selected = findViewById(checkedId);
            if (selected != null) {
                logUiInput("RadioSelect", "demographics-gender-" + selected.getText());
            }
            validate.run();
        });
        screen.consent.setOnCheckedChangeListener((buttonView, isChecked) -> {
            logUiInput("CheckBox", "demographics-consent-" + isChecked);
            validate.run();
        });

        screen.submit.setOnClickListener(v -> {
            logUiInput("Activate", "demographics-submit");
            RadioButton selectedGender = findViewById(screen.genderGroup.getCheckedRadioButtonId());
            if (isBlank(participant.participantId)) {
                participant.participantId = launchContext != null ? launchContext.participantIdOrRunId() : TimeUtil.newRunId();
            }
            participant.name = screen.nameInput.getText().toString().trim();
            participant.age = parseAge(screen.ageInput.getText().toString());
            participant.gender = selectedGender != null ? selectedGender.getText().toString() : "";
            participant.consent = screen.consent.isChecked();
            currentMaiaIndex = 0;
            currentPictographicIndex = 0;
            currentQuestionIndex = 0;
            updateDraftQuietly("demographics-complete");
            showFirstAnswerScreen();
        });
        setContentView(screen.root);
        logVisualStage("demographics", "demographics");
        return screen;
    }

    private QuestionnaireScreenBuilder.MaiaScreen showMaiaQuestion() {
        if (maiaQuestions.isEmpty()) {
            showAfterMaia();
            return null;
        }

        currentScreen = "maia";
        QuestionnaireScreenBuilder.MaiaScreen screen = screenBuilder.maiaScreen(
            maiaQuestions.get(currentMaiaIndex),
            currentMaiaIndex,
            maiaQuestions.size(),
            -1,
            false);
        activeMaiaScreen = screen;
        if (screen.backButton != null) {
            screen.backButton.setOnClickListener(v -> {
                logUiInput("Back", "maia-visible-back");
                handleBack();
            });
        }
        screen.scores.setOnCheckedChangeListener((group, checkedId) -> {
            int score = group.indexOfChild(findViewById(checkedId));
            if (score >= 0) {
                logUiInput("RadioSelect", "maia2-" + (currentMaiaIndex + 1) + "-score-" + score);
            }
            screen.next.setEnabled(checkedId != View.NO_ID);
        });
        screen.next.setOnClickListener(v -> {
            logUiInput("Activate", "maia-next");
            int score = screen.scores.indexOfChild(findViewById(screen.scores.getCheckedRadioButtonId()));
            trimMaiaAnswersTo(currentMaiaIndex);
            QuestionnaireData.Maia2Answer answer = new QuestionnaireData.Maia2Answer();
            answer.order = currentMaiaIndex + 1;
            answer.itemText = maiaQuestions.get(currentMaiaIndex);
            answer.score = Math.max(0, score);
            answer.responseTimestampUtc = TimeUtil.utcIsoNowMillis();
            answer.responseTimestampUnixMs = TimeUtil.unixMillisNow();
            maia2Answers.add(answer);
            updateDraftQuietly("maia2-" + (currentMaiaIndex + 1));
            currentMaiaIndex++;
            if (currentMaiaIndex >= maiaQuestions.size()) {
                showAfterMaia();
            } else {
                showMaiaQuestion();
            }
        });
        setContentView(screen.root);
        logVisualStage("maia2", currentMaiaIndex == 0 ? "maia2-first" : "maia2-" + (currentMaiaIndex + 1));
        return screen;
    }

    private QuestionnaireScreenBuilder.PictographicScreen showPictographicQuestion() {
        if (pictographicPrompts.isEmpty()) {
            showAfterPictographic();
            return null;
        }

        currentScreen = "pictographic";
        QuestionnaireData.RuntimePictographicPrompt prompt = pictographicPrompts.get(currentPictographicIndex);
        Bitmap bitmap = null;
        try {
            bitmap = QuestionnaireLoader.loadPictographicBitmap(this, prompt.imageFileName);
        } catch (Exception exception) {
            Log.w(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_PICTOGRAPHIC_IMAGE_LOAD_FAILED " + prompt.imageFileName + " " + exception.getMessage());
        }

        QuestionnaireScreenBuilder.PictographicScreen screen = screenBuilder.pictographicScreen(
            prompt,
            participant.language,
            bitmap,
            currentPictographicIndex,
            pictographicPrompts.size(),
            null,
            false);
        activePictographicScreen = screen;
        if (screen.backButton != null) {
            screen.backButton.setOnClickListener(v -> {
                logUiInput("Back", "pictographic-visible-back");
                handleBack();
            });
        }
        screen.choices.setOnCheckedChangeListener((group, checkedId) -> {
            RadioButton selected = findViewById(checkedId);
            if (selected != null) {
                logUiInput("RadioSelect", "pictographic-" + prompt.id + "-" + selected.getText());
            }
            screen.next.setEnabled(checkedId != View.NO_ID);
        });
        screen.next.setOnClickListener(v -> {
            logUiInput("Activate", "pictographic-next");
            RadioButton selected = findViewById(screen.choices.getCheckedRadioButtonId());
            trimPictographicSelectionsTo(currentPictographicIndex);
            QuestionnaireData.PictographicSelection selection = new QuestionnaireData.PictographicSelection();
            selection.order = currentPictographicIndex + 1;
            selection.promptId = prompt.id;
            selection.promptText = prompt.promptForLanguage(participant.language);
            selection.selectedChoice = selected != null ? selected.getText().toString() : "";
            selection.responseTimestampUtc = TimeUtil.utcIsoNowMillis();
            selection.responseTimestampUnixMs = TimeUtil.unixMillisNow();
            pictographicSelections.add(selection);
            updateDraftQuietly("pictographic-" + (currentPictographicIndex + 1));
            currentPictographicIndex++;
            if (currentPictographicIndex >= pictographicPrompts.size()) {
                showAfterPictographic();
            } else {
                showPictographicQuestion();
            }
        });
        setContentView(screen.root);
        logVisualStage("pictographic", currentPictographicIndex == 0 ? "pictographic" : "pictographic-" + (currentPictographicIndex + 1));
        return screen;
    }

    private QuestionnaireScreenBuilder.SliderScreen showSliderQuestion() {
        if (sliderQuestions.isEmpty()) {
            saveSession();
            return null;
        }

        currentScreen = "slider";
        QuestionnaireScreenBuilder.SliderScreen screen = screenBuilder.sliderScreen(
            uiText,
            sliderQuestions.get(currentQuestionIndex),
            currentQuestionIndex,
            sliderQuestions.size(),
            50,
            false,
            sliderAnchorLeft(),
            sliderAnchorRight());
        activeSliderScreen = screen;
        if (screen.backButton != null) {
            screen.backButton.setOnClickListener(v -> {
                logUiInput("Back", "slider-visible-back");
                handleBack();
            });
        }
        final boolean[] answered = {false};
        SeekBar.OnSeekBarChangeListener listener = new SeekBar.OnSeekBarChangeListener() {
            @Override
            public void onProgressChanged(SeekBar bar, int progress, boolean fromUser) {
                screen.valueText.setText(Integer.toString(progress));
                if (fromUser) {
                    logUiInput("SliderAdjust", "slider-" + (currentQuestionIndex + 1) + "-value-" + progress);
                    answered[0] = true;
                    screen.next.setEnabled(true);
                }
            }

            @Override
            public void onStartTrackingTouch(SeekBar bar) {
                logUiInput("SliderTouchStart", "slider-" + (currentQuestionIndex + 1));
                answered[0] = true;
                screen.next.setEnabled(true);
            }

            @Override
            public void onStopTrackingTouch(SeekBar bar) {
                logUiInput("SliderTouchStop", "slider-" + (currentQuestionIndex + 1) + "-value-" + bar.getProgress());
                answered[0] = true;
                screen.next.setEnabled(true);
            }
        };
        screen.seekBar.setOnSeekBarChangeListener(listener);
        screen.useCurrent.setOnClickListener(v -> {
            logUiInput("Activate", "slider-use-current");
            answered[0] = true;
            screen.next.setEnabled(true);
        });

        screen.next.setOnClickListener(v -> {
            logUiInput("Activate", "slider-next");
            if (!answered[0]) {
                return;
            }

            trimQuestionnaireAnswersTo(currentQuestionIndex);
            QuestionnaireData.QuestionnaireAnswer answer = new QuestionnaireData.QuestionnaireAnswer();
            answer.order = currentQuestionIndex + 1;
            answer.itemText = sliderQuestions.get(currentQuestionIndex);
            answer.score = screen.seekBar.getProgress();
            answer.responseTimestampUtc = TimeUtil.utcIsoNowMillis();
            answer.responseTimestampUnixMs = TimeUtil.unixMillisNow();
            questionnaireAnswers.add(answer);
            updateDraftQuietly("slider-" + (currentQuestionIndex + 1));
            currentQuestionIndex++;
            if (currentQuestionIndex >= sliderQuestions.size()) {
                saveSession();
            } else {
                showSliderQuestion();
            }
        });
        setContentView(screen.root);
        logVisualStage("slider", currentQuestionIndex == 0 ? "slider-first" : "slider-" + (currentQuestionIndex + 1));
        return screen;
    }

    private void showFirstAnswerScreen() {
        showNextConfiguredModule(QuestionnaireLaunchContext.MODULE_DEMOGRAPHICS);
    }

    private void showAfterMaia() {
        showNextConfiguredModule(QuestionnaireLaunchContext.MODULE_MAIA2);
    }

    private void showAfterPictographic() {
        showNextConfiguredModule(QuestionnaireLaunchContext.MODULE_PICTOGRAPHIC);
    }

    private void showNextConfiguredModule(String completedModule) {
        List<String> sequence = launchContext != null ? launchContext.questionnaireSequence : new ArrayList<>();
        boolean takeNext = completedModule == null;
        for (String module : sequence) {
            if (!takeNext) {
                if (module.equals(completedModule)) {
                    takeNext = true;
                }
                continue;
            }

            if (QuestionnaireLaunchContext.MODULE_DEMOGRAPHICS.equals(module)) {
                if (!"demographics".equals(currentScreen)) {
                    showParticipantForm();
                    return;
                }
                continue;
            }

            if (QuestionnaireLaunchContext.MODULE_MAIA2.equals(module) && !maiaQuestions.isEmpty()) {
                currentMaiaIndex = 0;
                showMaiaQuestion();
                return;
            }

            if (QuestionnaireLaunchContext.MODULE_PICTOGRAPHIC.equals(module) && !pictographicPrompts.isEmpty()) {
                currentPictographicIndex = 0;
                showPictographicQuestion();
                return;
            }

            if (QuestionnaireLaunchContext.MODULE_SLIDER.equals(module) && !sliderQuestions.isEmpty()) {
                currentQuestionIndex = 0;
                showSliderQuestion();
                return;
            }
        }

        saveSession();
    }

    private void saveSession() {
        try {
            QuestionnaireData.SessionRecord record = buildSessionRecord();
            QuestionnaireExporter.ExportResult export = QuestionnaireExporter.writeSession(this, record);
            Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_EXPORT_COMPLETE csv=\"" + export.csvFile.getAbsolutePath()
                + "\" json=\"" + export.jsonFile.getAbsolutePath()
                + "\" combinedCsv=\"" + (export.combinedCsvFile != null ? export.combinedCsvFile.getAbsolutePath() : "") + "\"");
            showSavedConfirmation(export);
            handlePostExport(export, record);
        } catch (Exception exception) {
            Log.e(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_EXPORT_ERROR " + exception.getMessage(), exception);
            showError("Could not save questionnaire", exception.getMessage());
        }
    }

    private QuestionnaireData.SessionRecord buildSessionRecord() {
        QuestionnaireData.SessionRecord record = new QuestionnaireData.SessionRecord();
        record.runId = launchContext != null ? launchContext.runId : TimeUtil.newRunId();
        record.timestampUtc = TimeUtil.utcIsoNow();
        record.sessionId = launchContext != null ? launchContext.sessionId : "";
        record.invocationId = launchContext != null ? launchContext.invocationId : record.runId;
        record.experimentId = launchContext != null ? launchContext.experimentId : "";
        record.scenarioId = launchContext != null ? launchContext.scenarioId : "";
        record.trialId = launchContext != null ? launchContext.trialId : "";
        record.chainId = launchContext != null ? launchContext.chainId : "";
        record.chainStepId = launchContext != null ? launchContext.chainStepId : "";
        record.chainStepIndex = launchContext != null ? launchContext.chainStepIndex : -1;
        record.triggerId = launchContext != null ? launchContext.triggerId : "";
        record.finishBehavior = launchContext != null ? launchContext.finishBehavior : QuestionnaireLaunchContext.FINISH_STAY_SAVED;
        record.callerPackage = launchContext != null ? launchContext.callerPackage : "";
        record.callerActivity = launchContext != null ? launchContext.callerActivity : "";
        record.nextPackage = launchContext != null ? launchContext.nextPackage : "";
        record.nextActivity = launchContext != null ? launchContext.nextActivity : "";
        record.questionnaireMode = launchContext != null ? launchContext.questionnaireMode : QuestionnaireLaunchContext.MODE_FULL;
        record.questionnaireSequence = launchContext != null ? launchContext.questionnaireSequenceCsv() : "";
        record.blockNumber = launchContext != null ? launchContext.blockNumber : "";
        record.blockId = launchContext != null ? launchContext.blockId : "";
        record.saveNamespace = launchContext != null ? launchContext.saveNamespace : "";
        record.appVersion = runtimeConfig.appVersion;
        record.sourceRepository = runtimeConfig.sourceRepository;
        record.sourceCommit = runtimeConfig.sourceCommit;
        record.maia2SourcePath = runtimeConfig.maia2SourcePath;
        record.questionnaireConfigId = runtimeConfig.questionnaireId;
        record.questionnaireConfigVersion = runtimeConfig.questionnaireVersion;
        record.participant = participant;
        record.maia2Answers.addAll(maia2Answers);
        record.maia2Scores.addAll(Maia2Scoring.calculate(record.maia2Answers));
        record.pictographicSelections.addAll(pictographicSelections);
        record.questionnaireAnswers.addAll(questionnaireAnswers);
        return record;
    }

    private void handlePostExport(QuestionnaireExporter.ExportResult export, QuestionnaireData.SessionRecord record) {
        long delay = launchContext != null ? launchContext.autoCloseDelayMs : 2000L;
        if (launchContext != null && !launchContext.shouldStaySaved()
                && (launchContext.hasReturnPendingIntent() || launchContext.shouldResumeCaller() || launchContext.shouldOpenNext())) {
            handler.postDelayed(() -> launchCompletionTarget(export, record), delay);
            return;
        }

        if (launchContext != null && launchContext.chained && launchContext.shouldStaySaved()) {
            Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_CHAIN_COMPLETE_STAY_SAVED runId=" + record.runId);
            return;
        }

        handler.postDelayed(this::showBlackScreen, delay);
    }

    private void launchCompletionTarget(QuestionnaireExporter.ExportResult export, QuestionnaireData.SessionRecord record) {
        if (launchContext.hasReturnPendingIntent()) {
            try {
                launchContext.sendReturnPendingIntent(this, export, record);
                Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_CHAIN_RETURN_PENDING_INTENT runId=" + record.runId
                    + " triggerId=" + record.triggerId
                    + " finishBehavior=" + launchContext.finishBehavior);
                finish();
                return;
            } catch (Exception exception) {
                Log.e(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_CHAIN_RETURN_PENDING_INTENT_FAILED " + exception.getMessage(), exception);
            }
        }

        Intent intent = launchContext.completionIntent(this, export, record);
        if (intent == null) {
            Log.w(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_CHAIN_TARGET_MISSING finishBehavior=" + launchContext.finishBehavior + " runId=" + record.runId);
            return;
        }

        try {
            startActivity(intent);
            Log.i(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_CHAIN_RETURN finishBehavior=" + launchContext.finishBehavior
                + " runId=" + record.runId
                + " targetPackage=" + intent.getPackage()
                + " component=" + intent.getComponent());
            finish();
        } catch (Exception exception) {
            Log.e(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_CHAIN_RETURN_FAILED " + exception.getMessage(), exception);
        }
    }

    private void showSavedConfirmation(QuestionnaireExporter.ExportResult export) {
        currentScreen = "saved";
        QuestionnaireScreenBuilder.SavedScreen screen = screenBuilder.savedScreen(
            uiText != null ? uiText.thankYou : "Saved",
            "Questionnaire data saved locally on the headset.\n\nCSV:\n" +
                export.csvFile.getAbsolutePath() + "\n\nSession CSV:\n" +
                (export.combinedCsvFile != null ? export.combinedCsvFile.getAbsolutePath() : "") +
                "\n\nJSON:\n" + export.jsonFile.getAbsolutePath());
        setContentView(screen.root);
        logVisualStage("saved-confirmation", "saved-confirmation");
    }

    private void showBlackScreen() {
        currentScreen = "black";
        setContentView(screenBuilder.blackScreen().root);
        logVisualStage("finished-black", "finished-black");
    }

    private void updateDraftQuietly(String status) {
        if (runtimeConfig == null || launchContext == null) {
            return;
        }

        try {
            QuestionnaireExporter.writeDraft(this, buildSessionRecord(), status);
        } catch (Exception exception) {
            Log.w(AutoSessionRunner.TAG, "MYQUESTIONNAIRE_DRAFT_WRITE_FAILED status=" + status + " " + exception.getMessage());
        }
    }

    private void resetSessionState() {
        participant = null;
        uiText = null;
        maiaQuestions = new ArrayList<>();
        sliderQuestions = new ArrayList<>();
        pictographicPrompts = new ArrayList<>();
        maia2Answers.clear();
        pictographicSelections.clear();
        questionnaireAnswers.clear();
        currentMaiaIndex = 0;
        currentPictographicIndex = 0;
        currentQuestionIndex = 0;
        currentScreen = "boot";
        activeLanguageScreen = null;
        activeDemographicsScreen = null;
        activeMaiaScreen = null;
        activePictographicScreen = null;
        activeSliderScreen = null;
        lastJoystickLogMillis = 0L;
    }

    private void showError(String title, String message) {
        currentScreen = "error";
        QuestionnaireScreenBuilder.ErrorScreen screen = screenBuilder.errorScreen(title, message);
        screen.retry.setOnClickListener(v -> {
            logUiInput("Activate", "error-retry");
            showLanguageSelection();
        });
        setContentView(screen.root);
        logVisualStage("error", "error");
    }

    private LinearLayout setBase(String title, boolean showBack) {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BACKGROUND);
        root.setPadding(dp(32), dp(24), dp(32), dp(24));

        TextView heading = new TextView(this);
        heading.setText(title);
        heading.setTextColor(TEXT);
        heading.setTextSize(30);
        heading.setGravity(Gravity.LEFT);
        heading.setPadding(0, 0, 0, dp(18));
        root.addView(heading, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(false);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(dp(20), dp(20), dp(20), dp(20));
        content.setBackgroundColor(PANEL);
        scroll.addView(content);
        root.addView(scroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        if (showBack) {
            Button back = makeButton("Back", false);
            back.setOnClickListener(v -> handleBack());
            root.addView(back, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(60)));
        }

        setContentView(root);
        return content;
    }

    private TextView addBody(LinearLayout parent, String text) {
        TextView view = label(text);
        view.setTextColor(MUTED);
        view.setPadding(0, 0, 0, dp(14));
        parent.addView(view);
        return view;
    }

    private void addQuestion(LinearLayout parent, String text) {
        TextView view = label(text);
        view.setTextColor(TEXT);
        view.setTextSize(23);
        view.setPadding(0, dp(8), 0, dp(20));
        parent.addView(view);
    }

    private void addWarning(LinearLayout parent, String text) {
        TextView view = label(text);
        view.setTextColor(DANGER);
        parent.addView(view);
    }

    private TextView label(String text) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextColor(TEXT);
        view.setTextSize(20);
        view.setLineSpacing(2f, 1.08f);
        view.setPadding(0, dp(8), 0, dp(8));
        return view;
    }

    private EditText makeEditText(String hint) {
        EditText input = new EditText(this);
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

    private RadioButton makeRadio(String text) {
        RadioButton button = new RadioButton(this);
        button.setText(text);
        button.setTextColor(TEXT);
        button.setTextSize(20);
        button.setMinHeight(dp(56));
        button.setPadding(0, 0, dp(18), 0);
        return button;
    }

    private Button makeButton(String text, boolean primary) {
        Button button = new Button(this);
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

    private boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    private int parseAge(String value) {
        try {
            int age = Integer.parseInt(value.trim());
            return age > 0 && age < 130 ? age : -1;
        } catch (Exception ignored) {
            return -1;
        }
    }

    private void handleBack() {
        if ("manual-hardware-gate".equals(currentScreen)) {
            logManualGateEvent("hardware-back", "hardware-back");
            return;
        }

        if ("demographics".equals(currentScreen)) {
            showLanguageSelection();
            return;
        }

        if ("maia".equals(currentScreen)) {
            if (currentMaiaIndex > 0) {
                currentMaiaIndex--;
                trimMaiaAnswersTo(currentMaiaIndex);
                showMaiaQuestion();
            } else {
                showPreviousConfiguredModule(QuestionnaireLaunchContext.MODULE_MAIA2);
            }
            return;
        }

        if ("pictographic".equals(currentScreen)) {
            if (currentPictographicIndex > 0) {
                currentPictographicIndex--;
                trimPictographicSelectionsTo(currentPictographicIndex);
                showPictographicQuestion();
            } else {
                showPreviousConfiguredModule(QuestionnaireLaunchContext.MODULE_PICTOGRAPHIC);
            }
            return;
        }

        if ("slider".equals(currentScreen)) {
            if (currentQuestionIndex > 0) {
                currentQuestionIndex--;
                trimQuestionnaireAnswersTo(currentQuestionIndex);
                showSliderQuestion();
            } else {
                showPreviousConfiguredModule(QuestionnaireLaunchContext.MODULE_SLIDER);
            }
            return;
        }

        showLanguageSelection();
    }

    private void showPreviousConfiguredModule(String currentModule) {
        String previousModule = previousConfiguredModule(currentModule);
        if (QuestionnaireLaunchContext.MODULE_DEMOGRAPHICS.equals(previousModule)) {
            showParticipantForm();
            return;
        }

        if (QuestionnaireLaunchContext.MODULE_MAIA2.equals(previousModule) && !maiaQuestions.isEmpty()) {
            currentMaiaIndex = Math.max(0, maiaQuestions.size() - 1);
            trimMaiaAnswersTo(currentMaiaIndex);
            showMaiaQuestion();
            return;
        }

        if (QuestionnaireLaunchContext.MODULE_PICTOGRAPHIC.equals(previousModule) && !pictographicPrompts.isEmpty()) {
            currentPictographicIndex = Math.max(0, pictographicPrompts.size() - 1);
            trimPictographicSelectionsTo(currentPictographicIndex);
            showPictographicQuestion();
            return;
        }

        if (QuestionnaireLaunchContext.MODULE_SLIDER.equals(previousModule) && !sliderQuestions.isEmpty()) {
            currentQuestionIndex = Math.max(0, sliderQuestions.size() - 1);
            trimQuestionnaireAnswersTo(currentQuestionIndex);
            showSliderQuestion();
            return;
        }

        showLanguageSelection();
    }

    private String previousConfiguredModule(String currentModule) {
        if (launchContext == null) {
            return "";
        }

        String previousModule = "";
        for (String module : launchContext.questionnaireSequence) {
            if (currentModule.equals(module)) {
                return previousModule;
            }
            if (canDisplayConfiguredModule(module)) {
                previousModule = module;
            }
        }
        return "";
    }

    private boolean canDisplayConfiguredModule(String module) {
        if (QuestionnaireLaunchContext.MODULE_DEMOGRAPHICS.equals(module)) {
            return launchContext != null && launchContext.shouldRunDemographics();
        }
        if (QuestionnaireLaunchContext.MODULE_MAIA2.equals(module)) {
            return !maiaQuestions.isEmpty();
        }
        if (QuestionnaireLaunchContext.MODULE_PICTOGRAPHIC.equals(module)) {
            return !pictographicPrompts.isEmpty();
        }
        if (QuestionnaireLaunchContext.MODULE_SLIDER.equals(module)) {
            return !sliderQuestions.isEmpty();
        }
        return false;
    }

    private void trimMaiaAnswersTo(int count) {
        while (maia2Answers.size() > count) {
            maia2Answers.remove(maia2Answers.size() - 1);
        }
    }

    private void trimPictographicSelectionsTo(int count) {
        while (pictographicSelections.size() > count) {
            pictographicSelections.remove(pictographicSelections.size() - 1);
        }
    }

    private void trimQuestionnaireAnswersTo(int count) {
        while (questionnaireAnswers.size() > count) {
            questionnaireAnswers.remove(questionnaireAnswers.size() - 1);
        }
    }

    private String sliderAnchorLeft() {
        QuestionnaireData.RuntimeBlock block = runtimeConfig != null ? runtimeConfig.findBlock("custom_slider") : null;
        if (block == null || block.anchors == null || block.anchors.left == null || block.anchors.left.trim().isEmpty()) {
            return uiText != null ? uiText.notAtAll : "";
        }
        return block.anchors.left;
    }

    private String sliderAnchorRight() {
        QuestionnaireData.RuntimeBlock block = runtimeConfig != null ? runtimeConfig.findBlock("custom_slider") : null;
        if (block == null || block.anchors == null || block.anchors.right == null || block.anchors.right.trim().isEmpty()) {
            return uiText != null ? uiText.extremely : "";
        }
        return block.anchors.right;
    }

    private String sourceFlags(int source) {
        List<String> flags = new ArrayList<>();
        if ((source & InputDevice.SOURCE_TOUCHSCREEN) == InputDevice.SOURCE_TOUCHSCREEN) {
            flags.add("touchscreen");
        }
        if ((source & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE) {
            flags.add("mouse");
        }
        if ((source & InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK) {
            flags.add("joystick");
        }
        if ((source & InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD) {
            flags.add("gamepad");
        }
        if ((source & InputDevice.SOURCE_KEYBOARD) == InputDevice.SOURCE_KEYBOARD) {
            flags.add("keyboard");
        }
        if (flags.isEmpty()) {
            flags.add("0x" + Integer.toHexString(source));
        }
        return String.join("|", flags);
    }

    private String toolTypeName(int toolType) {
        switch (toolType) {
            case MotionEvent.TOOL_TYPE_FINGER:
                return "finger";
            case MotionEvent.TOOL_TYPE_MOUSE:
                return "mouse";
            case MotionEvent.TOOL_TYPE_STYLUS:
                return "stylus";
            case MotionEvent.TOOL_TYPE_ERASER:
                return "eraser";
            default:
                return "unknown";
        }
    }

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private static final class SimpleWatcher implements TextWatcher {
        private final Runnable onChanged;

        SimpleWatcher(Runnable onChanged) {
            this.onChanged = onChanged;
        }

        @Override
        public void beforeTextChanged(CharSequence s, int start, int count, int after) {
        }

        @Override
        public void onTextChanged(CharSequence s, int start, int before, int count) {
            onChanged.run();
        }

        @Override
        public void afterTextChanged(Editable s) {
        }
    }
}
