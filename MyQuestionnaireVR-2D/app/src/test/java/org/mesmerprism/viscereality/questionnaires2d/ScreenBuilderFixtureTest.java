package org.mesmerprism.viscereality.questionnaires2d;

import android.content.Context;
import android.view.View;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;

import java.util.List;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public final class ScreenBuilderFixtureTest {
    @Test
    public void buildsAllRequiredStagesForBothLanguages() throws Exception {
        Context context = RuntimeEnvironment.getApplication();
        QuestionnaireData.RuntimeConfig config = QuestionnaireLoader.loadRuntimeConfig(context);
        QuestionnaireData.RuntimeBlock maiaBlock = config.findBlock("maia2");
        List<String> maia = maiaBlock != null ? QuestionnaireLoader.loadMaia2Questions(context) : java.util.Collections.emptyList();
        QuestionnaireData.RuntimeBlock pictographicBlock = config.findBlock("pictographic");
        List<QuestionnaireData.RuntimePictographicPrompt> prompts = pictographicBlock != null ? pictographicBlock.prompts : java.util.Collections.emptyList();
        QuestionnaireData.RuntimeBlock sliderBlock = config.findBlock("viscereality");
        QuestionnaireScreenBuilder builder = new QuestionnaireScreenBuilder(context);

        assertNotNull(builder.languageScreen().root);
        assertNotNull(builder.blackScreen().root);
        QuestionnaireScreenBuilder.ManualHardwareGateScreen manualGate = builder.manualHardwareGateScreen();
        assertNotNull(manualGate.root);
        assertNotNull(manualGate.controllerTarget);
        assertNotNull(manualGate.handTarget);
        assertNotNull(manualGate.visibleBack);
        assertNotNull(manualGate.keyboardInput);
        assertEquals(50, manualGate.joystickSlider.getProgress());

        for (String language : new String[] {"English", "Deutsch"}) {
            QuestionnaireData.LocalizedUiText uiText = QuestionnaireLoader.loadUiText(context, language);
            List<String> sliders = QuestionnaireLoader.loadQuestions(context, language);
            QuestionnaireScreenBuilder.DemographicsFixture demographics = new QuestionnaireScreenBuilder.DemographicsFixture();
            demographics.name = "George";
            demographics.age = 33;
            demographics.gender = uiText.genderFemale;
            demographics.consent = true;
            demographics.submitEnabled = true;

            QuestionnaireScreenBuilder.DemographicsScreen demographicsScreen = builder.demographicsScreen(uiText, demographics);
            QuestionnaireScreenBuilder.SliderScreen sliderScreen = builder.sliderScreen(
                uiText,
                sliders.get(0),
                0,
                sliders.size(),
                75,
                true,
                sliderBlock != null && sliderBlock.anchors != null ? sliderBlock.anchors.left : null,
                sliderBlock != null && sliderBlock.anchors != null ? sliderBlock.anchors.right : null);
            QuestionnaireScreenBuilder.SavedScreen savedScreen = builder.savedScreen(uiText.thankYou, "Saved fixture");

            assertTrue(demographicsScreen.submit.isEnabled());
            if (!maia.isEmpty()) {
                QuestionnaireScreenBuilder.MaiaScreen maiaScreen = builder.maiaScreen(maia.get(0), 0, maia.size(), 4, true);
                assertEquals(View.VISIBLE, maiaScreen.root.getVisibility());
                assertEquals(6, maiaScreen.scores.getChildCount());
            }
            if (!prompts.isEmpty()) {
                QuestionnaireScreenBuilder.PictographicScreen pictographicScreen = builder.pictographicScreen(
                    prompts.get(0),
                    language,
                    QuestionnaireLoader.loadPictographicBitmap(context, prompts.get(0).imageFileName),
                    0,
                    prompts.size(),
                    prompts.get(0).choices.get(0),
                    true);
                assertEquals(prompts.get(0).choices.size(), pictographicScreen.choices.getChildCount());
                assertTrue(pictographicScreen.next.isEnabled());
            }
            assertEquals(75, sliderScreen.seekBar.getProgress());
            assertTrue(sliderScreen.next.isEnabled());
            assertNotNull(savedScreen.root);
        }
    }
}
