package org.questquestionnaire.questionnaires2d;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

final class Maia2Scoring {
    private static final Group[] GROUPS = {
        new Group("Noticing", new int[] {1, 2, 3, 4}),
        new Group("Not-Distracting", new int[] {5, 6, 7, 8, 9, 10}),
        new Group("Not-Worrying", new int[] {11, 12, 13, 14, 15}),
        new Group("Attention Regulation", new int[] {16, 17, 18, 19, 20, 21, 22}),
        new Group("Emotional Awareness", new int[] {23, 24, 25, 26, 27}),
        new Group("Self-Regulation", new int[] {28, 29, 30, 31}),
        new Group("Body Listening", new int[] {32, 33, 34}),
        new Group("Trusting", new int[] {35, 36, 37})
    };

    private static final Set<Integer> REVERSED_QUESTIONS = new HashSet<>();

    static {
        int[] reversed = {5, 6, 7, 8, 9, 10, 11, 12, 15};
        for (int question : reversed) {
            REVERSED_QUESTIONS.add(question);
        }
    }

    private Maia2Scoring() {
    }

    static List<QuestionnaireData.Maia2ScaleScore> calculate(List<QuestionnaireData.Maia2Answer> answers) {
        List<QuestionnaireData.Maia2ScaleScore> result = new ArrayList<>();
        if (answers == null || answers.size() < 37) {
            return result;
        }

        Map<Integer, Integer> byOrder = new HashMap<>();
        for (QuestionnaireData.Maia2Answer answer : answers) {
            byOrder.put(answer.order, clamp(answer.score, 0, 5));
        }

        for (Group group : GROUPS) {
            float sum = 0f;
            for (int question : group.questions) {
                int score = byOrder.containsKey(question) ? byOrder.get(question) : 0;
                sum += REVERSED_QUESTIONS.contains(question) ? 5 - score : score;
            }

            QuestionnaireData.Maia2ScaleScore scaleScore = new QuestionnaireData.Maia2ScaleScore();
            scaleScore.scaleName = group.name;
            scaleScore.score = sum / group.questions.length;
            result.add(scaleScore);
        }

        return result;
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static final class Group {
        final String name;
        final int[] questions;

        Group(String name, int[] questions) {
            this.name = name;
            this.questions = questions;
        }
    }
}
