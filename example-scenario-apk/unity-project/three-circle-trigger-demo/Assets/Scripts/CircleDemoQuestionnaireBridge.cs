using System.Collections.Generic;
using UnityEngine;

public static class CircleDemoQuestionnaireBridge
{
    private const string QuestionnairePackage = "org.questquestionnaire.questionnaires2d";
    private const string QuestionnaireActivity = "org.questquestionnaire.questionnaires2d.MainActivity";
    private const string QuestionnaireAction = "org.questquestionnaire.questionnaires2d.RUN";
    private const int FlagActivityReorderToFront = 0x00020000;
    private const int FlagActivitySingleTop = 0x20000000;

    public static void LaunchQuestionnaireTrigger(string triggerId, Dictionary<string, string> extras)
    {
        Dictionary<string, string> payload = extras == null
            ? new Dictionary<string, string>()
            : new Dictionary<string, string>(extras);
        payload["mq.triggerId"] = triggerId ?? "";
        payload["mq.handoffSchema"] = "mq.handoff.v1";
        LaunchQuestionnaire(payload);
    }

    private static void LaunchQuestionnaire(Dictionary<string, string> extras)
    {
#if UNITY_ANDROID && !UNITY_EDITOR
        using (AndroidJavaClass unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
        using (AndroidJavaObject currentActivity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity"))
        using (AndroidJavaObject intent = new AndroidJavaObject("android.content.Intent", QuestionnaireAction))
        {
            string callerPackage = currentActivity.Call<string>("getPackageName");
            string callerActivity = currentActivity.Call<AndroidJavaObject>("getClass").Call<string>("getName");
            intent.Call<AndroidJavaObject>("setClassName", QuestionnairePackage, QuestionnaireActivity);
            intent.Call<AndroidJavaObject>("addFlags", FlagActivityReorderToFront | FlagActivitySingleTop);
            intent.Call<AndroidJavaObject>("putExtra", "mq.callerPackage", callerPackage);
            intent.Call<AndroidJavaObject>("putExtra", "mq.callerActivity", callerActivity);
            if (extras != null)
            {
                foreach (KeyValuePair<string, string> pair in extras)
                {
                    intent.Call<AndroidJavaObject>("putExtra", pair.Key, pair.Value ?? "");
                }
            }
            currentActivity.Call("startActivity", intent);
        }
#else
        Debug.Log("CircleDemoQuestionnaireBridge would launch questionnaire with trigger "
            + (extras != null && extras.ContainsKey("mq.triggerId") ? extras["mq.triggerId"] : ""));
#endif
    }
}
