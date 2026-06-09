using System;
using System.Collections.Generic;
using UnityEngine;

public static class CircleDemoQuestionnaireBridge
{
    private const string TriggerReceiverPackageExtra = "mq.triggerReceiverPackage";
    private const string TriggerReceiverActivityExtra = "mq.triggerReceiverActivity";
    private const string TriggerReceiverActionExtra = "mq.triggerReceiverAction";
    private const int FlagActivityReorderToFront = 0x00020000;
    private const int FlagActivitySingleTop = 0x20000000;

    private static readonly HashSet<string> PassiveMetadataExtraSet =
        new HashSet<string>(StringComparer.Ordinal)
        {
            "mq.sessionId",
            "mq.invocationId",
            "mq.experimentId",
            "mq.scenarioId",
            "mq.trialId",
            "mq.chainId",
            "mq.participantId",
            "mq.participantName",
            "mq.language",
            "mq.triggerSource",
            "mq.triggerTimestampUtc",
            "mq.triggerTimestampUnixMs"
        };

    public static void EmitTrigger(string triggerId, Dictionary<string, string> extras)
    {
        Dictionary<string, string> payload = FilterPassiveMetadata(extras);
        payload["mq.triggerId"] = triggerId ?? "";
        payload["mq.handoffSchema"] = "mq.handoff.v1";
        EmitTriggerIntent(payload);
    }

    private static void EmitTriggerIntent(Dictionary<string, string> extras)
    {
#if UNITY_ANDROID && !UNITY_EDITOR
        using (AndroidJavaClass unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
        using (AndroidJavaObject currentActivity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity"))
        {
            TriggerReceiver receiver = ResolveTriggerReceiver(currentActivity);
            if (!receiver.IsValid())
            {
                Debug.LogWarning("CircleDemoQuestionnaireBridge has no questionnaire trigger receiver. Launch this demo from the generated questionnaire APK so it can supply mq.triggerReceiver* extras.");
                return;
            }
            using (AndroidJavaObject intent = new AndroidJavaObject("android.content.Intent", receiver.action))
            {
                string callerPackage = currentActivity.Call<string>("getPackageName");
                string callerActivity = currentActivity.Call<AndroidJavaObject>("getClass").Call<string>("getName");
                intent.Call<AndroidJavaObject>("setClassName", receiver.packageName, receiver.activityName);
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
        }
#else
        Debug.Log("CircleDemoQuestionnaireBridge would emit passive trigger "
            + (extras != null && extras.ContainsKey("mq.triggerId") ? extras["mq.triggerId"] : ""));
#endif
    }

#if UNITY_ANDROID && !UNITY_EDITOR
    private sealed class TriggerReceiver
    {
        public string packageName;
        public string activityName;
        public string action;

        public bool IsValid()
        {
            return !string.IsNullOrEmpty(packageName)
                && !string.IsNullOrEmpty(activityName)
                && !string.IsNullOrEmpty(action);
        }
    }

    private static TriggerReceiver ResolveTriggerReceiver(AndroidJavaObject currentActivity)
    {
        string packageName = GetLaunchIntentExtra(currentActivity, TriggerReceiverPackageExtra);
        string activityName = GetLaunchIntentExtra(currentActivity, TriggerReceiverActivityExtra);
        string action = GetLaunchIntentExtra(currentActivity, TriggerReceiverActionExtra);

        return new TriggerReceiver
        {
            packageName = packageName,
            activityName = NormalizeActivity(packageName, activityName),
            action = action
        };
    }

    private static string GetLaunchIntentExtra(AndroidJavaObject currentActivity, string key)
    {
        using (AndroidJavaObject launchIntent = currentActivity.Call<AndroidJavaObject>("getIntent"))
        {
            return launchIntent == null ? "" : launchIntent.Call<string>("getStringExtra", key);
        }
    }
#endif

    private static Dictionary<string, string> FilterPassiveMetadata(Dictionary<string, string> extras)
    {
        Dictionary<string, string> payload = new Dictionary<string, string>();
        if (extras == null)
        {
            return payload;
        }

        foreach (KeyValuePair<string, string> pair in extras)
        {
            if (PassiveMetadataExtraSet.Contains(pair.Key))
            {
                payload[pair.Key] = pair.Value ?? "";
            }
        }
        return payload;
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
