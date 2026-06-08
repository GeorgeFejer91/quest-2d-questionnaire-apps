package org.questquestionnaire.questionnaires2d;

import android.content.Context;
import android.content.res.AssetManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

import org.json.JSONArray;
import org.json.JSONException;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

final class QuestionnaireLoader {
    static final String ASSET_ROOT = "questionnaire";

    private QuestionnaireLoader() {
    }

    static QuestionnaireData.RuntimeConfig loadRuntimeConfig(Context context) throws IOException, JSONException {
        return QuestionnaireData.RuntimeConfig.fromJson(loadTextAsset(context, "QuestionnaireConfig.json"));
    }

    static List<String> loadQuestions(Context context, String language) throws IOException {
        return parseNonEmptyLines(loadTextAsset(context, "Questions_" + normalizeLanguage(language) + ".txt"));
    }

    static QuestionnaireData.LocalizedUiText loadUiText(Context context, String language) throws IOException {
        return parseUiText(loadTextAsset(context, "UIText.txt"), normalizeLanguage(language));
    }

    static List<String> loadMaia2Questions(Context context) throws IOException, JSONException {
        return parseMaia2Questions(loadTextAsset(context, "MAIA2_Questions.json"));
    }

    static Bitmap loadPictographicBitmap(Context context, String imageFileName) throws IOException {
        AssetManager assets = context.getAssets();
        String path = ASSET_ROOT + "/PictographicScales/" + imageFileName;
        try (InputStream input = assets.open(path)) {
            return BitmapFactory.decodeStream(input);
        }
    }

    static String loadTextAsset(Context context, String relativePath) throws IOException {
        String path = ASSET_ROOT + "/" + relativePath;
        try (InputStream input = context.getAssets().open(path)) {
            return readAll(input);
        }
    }

    static String readAll(InputStream input) throws IOException {
        StringBuilder builder = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                builder.append(line).append('\n');
            }
        }

        return builder.toString();
    }

    static List<String> parseNonEmptyLines(String text) {
        List<String> lines = new ArrayList<>();
        if (text == null) {
            return lines;
        }

        String[] split = text.replace("\r\n", "\n").replace('\r', '\n').split("\n");
        for (String line : split) {
            String trimmed = line.trim();
            if (!trimmed.isEmpty()) {
                lines.add(trimmed);
            }
        }

        return lines;
    }

    static List<String> parseMaia2Questions(String json) throws JSONException {
        JSONArray array = new JSONArray(json.trim());
        List<String> questions = new ArrayList<>();
        for (int i = 0; i < array.length(); i++) {
            String question = normalizeTextEncoding(array.optString(i, "").trim());
            if (!question.isEmpty()) {
                questions.add(question);
            }
        }

        return questions;
    }

    static QuestionnaireData.LocalizedUiText parseUiText(String text, String language) {
        return QuestionnaireData.LocalizedUiText.fromOriginalLines(extractLanguageBlock(text, normalizeLanguage(language)));
    }

    static List<String> extractLanguageBlock(String text, String language) {
        List<String> result = new ArrayList<>();
        if (text == null) {
            return result;
        }

        String activeHeader = normalizeLanguage(language) + ":";
        boolean inBlock = false;
        String[] split = text.replace("\r\n", "\n").replace('\r', '\n').split("\n");
        for (String line : split) {
            String trimmed = line.trim();
            if ("Deutsch:".equals(trimmed) || "English:".equals(trimmed)) {
                if (inBlock) {
                    break;
                }

                inBlock = trimmed.equals(activeHeader);
                continue;
            }

            if (inBlock && !trimmed.isEmpty()) {
                result.add(trimmed);
            }
        }

        return result;
    }

    static String normalizeLanguage(String language) {
        if ("Deutsch".equalsIgnoreCase(language) || "German".equalsIgnoreCase(language)) {
            return "Deutsch";
        }

        return "English";
    }

    private static String normalizeTextEncoding(String text) {
        return text
            .replace("ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢", "'")
            .replace("ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ", "\"")
            .replace("ÃƒÂ¢Ã¢â€šÂ¬\u009d", "\"")
            .replace("ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“", "-");
    }
}
