using System.Collections.Generic;
using UnityEngine;

public static class QuestQuestionnaireChainBridge
{
    public const string QuestionnairePackage = "org.viscereality.questionnaires2d";
    public const string QuestionnaireActivity = "org.viscereality.questionnaires2d.MainActivity";
    public const string TemporalTracerPackage = "org.viscereality.temporaltracer2d";
    public const string TemporalTracerActivity = "org.viscereality.temporaltracer2d.MainActivity";
    public const string BrokerActivity = "org.viscereality.questionnaires2d.QuestChainBrokerActivity";
    public const string ChainLinkPackage = "org.viscereality.chainlink";
    public const string ChainLinkActivity = "org.viscereality.chainlink.ChainLinkActivity";
    public const string RunAction = "org.viscereality.questionnaires2d.RUN";
    public const string TemporalTracerRunAction = "org.viscereality.temporaltracer2d.RUN";
    public const string BrokerAction = "org.viscereality.questionnaires2d.BROKER";
    public const string ChainLinkCommandAction = "org.viscereality.chainlink.COMMAND";
    public const string BrokerActionExtra = "mq.brokerAction";
    public const string BrokerPackageExtra = "mq.brokerPackage";
    public const string BrokerActivityExtra = "mq.brokerActivity";
    public const string ChainLinkCommandExtra = "mq.command";
    public const string ChainLinkNextBlockCommand = "nextBlock";
    public const string ChainLinkTriggerCommand = "trigger";
    public const string HandoffSchemaExtra = "mq.handoffSchema";
    public const string ReturnPendingIntentExtra = "mq.returnPendingIntent";
    public const string HandoffSchemaV1 = "mq.handoff.v1";
    private const int FlagActivityReorderToFront = 0x00020000;
    private const int FlagActivityNewTask = 0x10000000;
    private const int FlagActivitySingleTop = 0x20000000;
    private const int PendingIntentFlagUpdateCurrent = 0x08000000;
    private const int PendingIntentFlagMutable = 0x02000000;

    public static void LaunchQuestionnaire(Dictionary<string, string> extras)
    {
        LaunchPanel(QuestionnairePackage, QuestionnaireActivity, RunAction, extras);
    }

    public static void LaunchTemporalTracer(Dictionary<string, string> extras)
    {
        LaunchPanel(TemporalTracerPackage, TemporalTracerActivity, TemporalTracerRunAction, extras);
    }

    private static void LaunchPanel(string packageName, string activityName, string action, Dictionary<string, string> extras)
    {
#if UNITY_ANDROID && !UNITY_EDITOR
        using (var unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
        using (var currentActivity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity"))
        using (var intent = new AndroidJavaObject("android.content.Intent", action))
        {
            intent.Call<AndroidJavaObject>("setClassName", packageName, activityName);
            intent.Call<AndroidJavaObject>("addFlags", FlagActivityReorderToFront | FlagActivitySingleTop);
            intent.Call<AndroidJavaObject>("putExtra", HandoffSchemaExtra, HandoffSchemaV1);
            if (extras != null)
            {
                foreach (var pair in extras)
                {
                    intent.Call<AndroidJavaObject>("putExtra", pair.Key, pair.Value ?? "");
                }
            }
            using (var returnPendingIntent = CreateReturnPendingIntent(currentActivity, extras))
            {
                intent.Call<AndroidJavaObject>("putExtra", ReturnPendingIntentExtra, returnPendingIntent);
                currentActivity.Call("startActivity", intent);
            }
        }
#else
        Debug.Log("QuestQuestionnaireChainBridge panel launches only run on Android device builds.");
#endif
    }

    public static void SendBrokerCommand(string command, Dictionary<string, string> extras = null)
    {
#if UNITY_ANDROID && !UNITY_EDITOR
        string brokerAction = GetExtraOrDefault(extras, BrokerActionExtra, BrokerAction);
        string brokerPackage = GetExtraOrDefault(extras, BrokerPackageExtra, QuestionnairePackage);
        string brokerActivity = GetExtraOrDefault(extras, BrokerActivityExtra, BrokerActivity);
        using (var unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
        using (var currentActivity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity"))
        using (var intent = new AndroidJavaObject("android.content.Intent", brokerAction))
        {
            intent.Call<AndroidJavaObject>("setClassName", brokerPackage, NormalizeActivity(brokerPackage, brokerActivity));
            intent.Call<AndroidJavaObject>("addFlags", 0x00020000 | 0x20000000);
            intent.Call<AndroidJavaObject>("putExtra", "mq.brokerCommand", command ?? "ping");
            if (extras != null)
            {
                foreach (var pair in extras)
                {
                    intent.Call<AndroidJavaObject>("putExtra", pair.Key, pair.Value ?? "");
                }
            }
            currentActivity.Call("startActivity", intent);
        }
#else
        Debug.Log("QuestQuestionnaireChainBridge broker commands only launch on Android device builds.");
#endif
    }

    public static void SendChainLinkCommand(string command, Dictionary<string, string> extras = null)
    {
#if UNITY_ANDROID && !UNITY_EDITOR
        using (var unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
        using (var currentActivity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity"))
        using (var intent = new AndroidJavaObject("android.content.Intent", ChainLinkCommandAction))
        {
            intent.Call<AndroidJavaObject>("setClassName", ChainLinkPackage, ChainLinkActivity);
            intent.Call<AndroidJavaObject>("addFlags", FlagActivityReorderToFront | FlagActivitySingleTop);
            intent.Call<AndroidJavaObject>("putExtra", "mq.sourcePackage", currentActivity.Call<string>("getPackageName"));
            intent.Call<AndroidJavaObject>("putExtra", "mq.sourceActivity", currentActivity.Call<AndroidJavaObject>("getClass").Call<string>("getName"));
            if (extras != null)
            {
                foreach (var pair in extras)
                {
                    intent.Call<AndroidJavaObject>("putExtra", pair.Key, pair.Value ?? "");
                }
            }
            intent.Call<AndroidJavaObject>("putExtra", ChainLinkCommandExtra, string.IsNullOrEmpty(command) ? ChainLinkNextBlockCommand : command);
            currentActivity.Call("startActivity", intent);
        }
#else
        Debug.Log("QuestQuestionnaireChainBridge ChainLink commands only launch on Android device builds.");
#endif
    }

    public static void SendChainLinkNextBlock(Dictionary<string, string> extras = null)
    {
        SendChainLinkCommand(ChainLinkNextBlockCommand, extras);
    }

    public static void SendChainLinkTrigger(string triggerId, Dictionary<string, string> extras = null)
    {
        var allExtras = extras == null
            ? new Dictionary<string, string>()
            : new Dictionary<string, string>(extras);
        allExtras["mq.triggerId"] = triggerId ?? "";
        SendChainLinkCommand(ChainLinkTriggerCommand, allExtras);
    }

    public static void StartBrokerPlan(string chainPlanJson, Dictionary<string, string> extras = null)
    {
        var allExtras = extras == null
            ? new Dictionary<string, string>()
            : new Dictionary<string, string>(extras);
        allExtras["mq.chainPlanJson"] = chainPlanJson ?? "";
        SendBrokerCommand("startPlan", allExtras);
    }

    public static void ContinueBrokerPlan(Dictionary<string, string> extras = null)
    {
        SendBrokerCommand("continuePlan", extras);
    }

    public static Dictionary<string, string> CreateBrokerCallbackExtras()
    {
        return new Dictionary<string, string>
        {
            [BrokerActionExtra] = BrokerAction,
            [BrokerPackageExtra] = QuestionnairePackage,
            [BrokerActivityExtra] = BrokerActivity
        };
    }

    public static Dictionary<string, string> ReadQuestionnaireResult()
    {
        var result = new Dictionary<string, string>();
#if UNITY_ANDROID && !UNITY_EDITOR
        using (var unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
        using (var currentActivity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity"))
        using (var intent = currentActivity.Call<AndroidJavaObject>("getIntent"))
        {
            CopyStringExtra(intent, result, "mq.resultStatus");
            CopyStringExtra(intent, result, "mq.handoffSchema");
            CopyStringExtra(intent, result, "mq.triggerId");
            CopyStringExtra(intent, result, "mq.runId");
            CopyStringExtra(intent, result, "mq.sessionId");
            CopyStringExtra(intent, result, "mq.chainId");
            CopyStringExtra(intent, result, "mq.chainStepId");
            CopyIntExtra(intent, result, "mq.chainStepIndex");
            CopyStringExtra(intent, result, "mq.timestampUtc");
            CopyStringExtra(intent, result, "mq.exportJsonPath");
            CopyStringExtra(intent, result, "mq.exportCsvPath");
            CopyStringExtra(intent, result, "mq.exportSvgPath");
            CopyStringExtra(intent, result, "mq.questionnaireConfigId");
            CopyStringExtra(intent, result, "mq.tracerConfigId");
        }
#endif
        return result;
    }

    public static void ClearQuestionnaireResult()
    {
#if UNITY_ANDROID && !UNITY_EDITOR
        using (var unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
        using (var currentActivity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity"))
        using (var clearedIntent = new AndroidJavaObject("android.content.Intent"))
        {
            clearedIntent.Call<AndroidJavaObject>(
                "setClassName",
                currentActivity.Call<string>("getPackageName"),
                currentActivity.Call<AndroidJavaObject>("getClass").Call<string>("getName"));
            currentActivity.Call("setIntent", clearedIntent);
        }
#endif
    }

    public static Dictionary<string, string> ReadValidationExtras()
    {
        var result = new Dictionary<string, string>();
#if UNITY_ANDROID && !UNITY_EDITOR
        using (var unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
        using (var currentActivity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity"))
        using (var intent = currentActivity.Call<AndroidJavaObject>("getIntent"))
        {
            CopyStringExtra(intent, result, "mq.validationAutoTrace");
            CopyStringExtra(intent, result, "mq.validationFastVideo");
            CopyStringExtra(intent, result, "mq.validationVideoEndAfterSeconds");
        }
#endif
        return result;
    }

    public static Dictionary<string, string> ReadChainHookCommand()
    {
        var result = new Dictionary<string, string>();
#if UNITY_ANDROID && !UNITY_EDITOR
        using (var unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
        using (var currentActivity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity"))
        using (var intent = currentActivity.Call<AndroidJavaObject>("getIntent"))
        {
            CopyStringExtra(intent, result, "mq.hookCommand");
            CopyStringExtra(intent, result, "mq.chainId");
            CopyStringExtra(intent, result, "mq.chainStepId");
            CopyIntExtra(intent, result, "mq.chainStepIndex");
            CopyStringExtra(intent, result, "mq.brokerAction");
            CopyStringExtra(intent, result, "mq.brokerPackage");
            CopyStringExtra(intent, result, "mq.brokerActivity");
            CopyStringExtra(intent, result, "mq.sessionId");
            CopyStringExtra(intent, result, "mq.experimentId");
            CopyStringExtra(intent, result, "mq.scenarioId");
            CopyStringExtra(intent, result, "mq.trialId");
            CopyStringExtra(intent, result, "mq.participantId");
            CopyStringExtra(intent, result, "mq.participantName");
            CopyStringExtra(intent, result, "mq.language");
            CopyStringExtra(intent, result, "scenarioId");
            CopyStringExtra(intent, result, "trialId");
        }
#endif
        return result;
    }

#if UNITY_ANDROID && !UNITY_EDITOR
    private static AndroidJavaObject CreateReturnPendingIntent(AndroidJavaObject currentActivity, Dictionary<string, string> extras)
    {
        string callerPackage = GetExtraOrDefault(extras, "mq.callerPackage", currentActivity.Call<string>("getPackageName"));
        string callerActivity = GetExtraOrDefault(extras, "mq.callerActivity", currentActivity.Call<AndroidJavaObject>("getClass").Call<string>("getName"));
        using (var returnIntent = new AndroidJavaObject("android.content.Intent"))
        using (var pendingIntentClass = new AndroidJavaClass("android.app.PendingIntent"))
        using (var buildVersion = new AndroidJavaClass("android.os.Build$VERSION"))
        {
            returnIntent.Call<AndroidJavaObject>("setClassName", callerPackage, NormalizeActivity(callerPackage, callerActivity));
            returnIntent.Call<AndroidJavaObject>("addFlags", FlagActivityReorderToFront | FlagActivitySingleTop | FlagActivityNewTask);
            returnIntent.Call<AndroidJavaObject>("putExtra", HandoffSchemaExtra, HandoffSchemaV1);
            string requestKey = callerPackage
                + "/"
                + callerActivity
                + "/"
                + GetExtraOrDefault(extras, "mq.triggerId", "")
                + "/"
                + GetExtraOrDefault(extras, "mq.chainStepId", "")
                + "/"
                + GetExtraOrDefault(extras, "mq.blockId", "");
            returnIntent.Call<AndroidJavaObject>("putExtra", "mq.pendingIntentRequestKey", requestKey);
            int flags = PendingIntentFlagUpdateCurrent;
            if (buildVersion.GetStatic<int>("SDK_INT") >= 31)
            {
                flags |= PendingIntentFlagMutable;
            }
            int requestCode = Mathf.Abs(requestKey.GetHashCode());
            return pendingIntentClass.CallStatic<AndroidJavaObject>("getActivity", currentActivity, requestCode, returnIntent, flags);
        }
    }

    private static void CopyStringExtra(AndroidJavaObject intent, Dictionary<string, string> result, string key)
    {
        string value = intent.Call<string>("getStringExtra", key);
        if (!string.IsNullOrEmpty(value))
        {
            result[key] = value;
        }
    }

    private static void CopyIntExtra(AndroidJavaObject intent, Dictionary<string, string> result, string key)
    {
        int value = intent.Call<int>("getIntExtra", key, -1);
        if (value >= 0)
        {
            result[key] = value.ToString();
        }
    }
#endif

    private static string GetExtraOrDefault(Dictionary<string, string> extras, string key, string fallback)
    {
        if (extras != null && extras.TryGetValue(key, out var value) && !string.IsNullOrEmpty(value))
        {
            return value;
        }
        return fallback;
    }

    private static string NormalizeActivity(string packageName, string activityName)
    {
        if (!string.IsNullOrEmpty(activityName) && activityName.StartsWith("."))
        {
            return packageName + activityName;
        }
        return activityName;
    }
}
