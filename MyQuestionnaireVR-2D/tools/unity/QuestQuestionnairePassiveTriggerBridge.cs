using System;
using System.Collections.Generic;
using System.Globalization;
using UnityEngine;

public static class QuestQuestionnairePassiveTriggerBridge
{
    public const string TriggerReceiverPackageExtra = "mq.triggerReceiverPackage";
    public const string TriggerReceiverActivityExtra = "mq.triggerReceiverActivity";
    public const string TriggerReceiverActionExtra = "mq.triggerReceiverAction";
    public const string TriggerIdExtra = "mq.triggerId";
    public const string HandoffSchemaExtra = "mq.handoffSchema";
    public const string HandoffSchemaV1 = "mq.handoff.v1";

    private const int FlagActivityReorderToFront = 0x00020000;
    private const int FlagActivitySingleTop = 0x20000000;

    private static readonly string[] MetadataExtras =
    {
        "mq.sessionId",
        "mq.invocationId",
        "mq.experimentId",
        "mq.scenarioId",
        "mq.trialId",
        "mq.chainId",
        "mq.participantId",
        "mq.participantName",
        "mq.language"
    };

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

    public static bool EmitTrigger(string triggerId)
    {
        return EmitTrigger(triggerId, null);
    }

    public static bool EmitTrigger(string triggerId, Dictionary<string, string> extras)
    {
        Dictionary<string, string> payload = FilterPassiveMetadata(extras);
        payload[TriggerIdExtra] = triggerId ?? "";
        payload[HandoffSchemaExtra] = HandoffSchemaV1;

        DateTime utcNow = DateTime.UtcNow;
        if (!payload.ContainsKey("mq.triggerTimestampUtc"))
        {
            payload["mq.triggerTimestampUtc"] = utcNow.ToString("o");
        }
        if (!payload.ContainsKey("mq.triggerTimestampUnixMs"))
        {
            payload["mq.triggerTimestampUnixMs"] = ToUnixMilliseconds(utcNow).ToString(CultureInfo.InvariantCulture);
        }
        if (!payload.ContainsKey("mq.triggerSource"))
        {
            payload["mq.triggerSource"] = "unity-passive-trigger";
        }

#if UNITY_ANDROID && !UNITY_EDITOR
        using (AndroidJavaClass unityPlayer = new AndroidJavaClass("com.unity3d.player.UnityPlayer"))
        using (AndroidJavaObject currentActivity = unityPlayer.GetStatic<AndroidJavaObject>("currentActivity"))
        {
            TriggerReceiver receiver = ResolveTriggerReceiver(currentActivity);
            if (!receiver.IsValid())
            {
                Debug.LogWarning("QuestQuestionnairePassiveTriggerBridge has no mq.triggerReceiver* target. Launch Unity from the generated questionnaire APK before emitting questionnaire triggers.");
                return false;
            }

            CopyIncomingMetadata(currentActivity, payload);

            using (AndroidJavaObject intent = new AndroidJavaObject("android.content.Intent", receiver.action))
            {
                string callerPackage = currentActivity.Call<string>("getPackageName");
                string callerActivity = currentActivity.Call<AndroidJavaObject>("getClass").Call<string>("getName");
                intent.Call<AndroidJavaObject>("setClassName", receiver.packageName, receiver.activityName);
                intent.Call<AndroidJavaObject>("addFlags", FlagActivityReorderToFront | FlagActivitySingleTop);
                intent.Call<AndroidJavaObject>("putExtra", "mq.callerPackage", callerPackage);
                intent.Call<AndroidJavaObject>("putExtra", "mq.callerActivity", callerActivity);

                foreach (KeyValuePair<string, string> pair in payload)
                {
                    intent.Call<AndroidJavaObject>("putExtra", pair.Key, pair.Value ?? "");
                }

                currentActivity.Call("startActivity", intent);
                return true;
            }
        }
#else
        Debug.Log("QuestQuestionnairePassiveTriggerBridge would emit trigger "
            + (payload.ContainsKey(TriggerIdExtra) ? payload[TriggerIdExtra] : ""));
        return false;
#endif
    }

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

    private static void CopyIncomingMetadata(AndroidJavaObject currentActivity, Dictionary<string, string> payload)
    {
        for (int index = 0; index < MetadataExtras.Length; index++)
        {
            string key = MetadataExtras[index];
            if (payload.ContainsKey(key))
            {
                continue;
            }

            string value = GetLaunchIntentExtra(currentActivity, key);
            if (!string.IsNullOrEmpty(value))
            {
                payload[key] = value;
            }
        }
    }

    private static string GetLaunchIntentExtra(AndroidJavaObject currentActivity, string key)
    {
        using (AndroidJavaObject launchIntent = currentActivity.Call<AndroidJavaObject>("getIntent"))
        {
            return launchIntent == null ? "" : launchIntent.Call<string>("getStringExtra", key);
        }
    }
#endif

    private static string NormalizeActivity(string packageName, string activityName)
    {
        if (!string.IsNullOrEmpty(activityName) && activityName.StartsWith("."))
        {
            return packageName + activityName;
        }
        return activityName;
    }

    private static long ToUnixMilliseconds(DateTime utcTime)
    {
        DateTime epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        return (long)(utcTime - epoch).TotalMilliseconds;
    }
}
