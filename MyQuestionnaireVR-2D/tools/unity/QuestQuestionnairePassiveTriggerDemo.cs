using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using UnityEngine;

public sealed class QuestQuestionnairePassiveTriggerDemo : MonoBehaviour
{
    [Serializable]
    public sealed class PassiveTriggerStep
    {
        public string triggerId = "trigger_1_complete";
        public float delaySeconds = 10f;
    }

    public enum PassiveTriggerAction
    {
        LaunchQuestionnaire,
        ChainLinkTrigger
    }

    [Header("Demo trigger sequence")]
    public bool armOnStart = true;
    public bool useRealtime = true;
    public PassiveTriggerAction action = PassiveTriggerAction.LaunchQuestionnaire;
    public List<PassiveTriggerStep> triggers = new List<PassiveTriggerStep>
    {
        new PassiveTriggerStep { triggerId = "trigger_1_complete", delaySeconds = 10f },
        new PassiveTriggerStep { triggerId = "trigger_2_complete", delaySeconds = 10f }
    };

    [Header("Launch metadata")]
    public string finishBehavior = "resumeCaller";
    public string callerPackage = "";
    public string callerActivity = "";
    public string autoCloseDelayMs = "2000";

    [Header("Session metadata")]
    public string sessionId = "";
    public string experimentId = "";
    public string scenarioId = "";
    public string trialId = "";
    public string participantId = "";
    public string participantName = "";
    public string language = "";

    private Coroutine sequenceCoroutine;

    private void Start()
    {
        if (armOnStart)
        {
            Arm();
        }
    }

    private void OnDisable()
    {
        Disarm();
    }

    [ContextMenu("Arm Passive Trigger Demo")]
    public void Arm()
    {
        Disarm();
        sequenceCoroutine = StartCoroutine(RunSequence());
    }

    [ContextMenu("Disarm Passive Trigger Demo")]
    public void Disarm()
    {
        if (sequenceCoroutine == null)
        {
            return;
        }

        StopCoroutine(sequenceCoroutine);
        sequenceCoroutine = null;
    }

    private IEnumerator RunSequence()
    {
        for (int index = 0; index < triggers.Count; index++)
        {
            PassiveTriggerStep step = triggers[index];
            yield return WaitForConfiguredDelay(step == null ? 0f : step.delaySeconds);
            Fire(step == null ? "" : step.triggerId, index + 1);
        }

        sequenceCoroutine = null;
    }

    private IEnumerator WaitForConfiguredDelay(float delaySeconds)
    {
        delaySeconds = Mathf.Max(0f, delaySeconds);
        if (!useRealtime)
        {
            yield return new WaitForSeconds(delaySeconds);
            yield break;
        }

        float endTime = Time.realtimeSinceStartup + delaySeconds;
        while (Time.realtimeSinceStartup < endTime)
        {
            yield return null;
        }
    }

    private void Fire(string triggerId, int sequenceNumber)
    {
        Dictionary<string, string> extras = BuildExtras(triggerId, sequenceNumber);
        if (action == PassiveTriggerAction.ChainLinkTrigger)
        {
            QuestQuestionnaireChainBridge.SendChainLinkTrigger(triggerId, extras);
        }
        else
        {
            QuestQuestionnaireChainBridge.LaunchQuestionnaireTrigger(triggerId, extras);
        }

        Debug.Log("QuestQuestionnairePassiveTriggerDemo emitted passive trigger "
            + triggerId
            + " sequence="
            + sequenceNumber.ToString(CultureInfo.InvariantCulture));
    }

    private Dictionary<string, string> BuildExtras(string triggerId, int sequenceNumber)
    {
        DateTime utcNow = DateTime.UtcNow;
        Dictionary<string, string> extras = new Dictionary<string, string>
        {
            ["mq.triggerId"] = triggerId ?? "",
            ["mq.triggerSource"] = "unity-passive-trigger-demo",
            ["mq.triggerTimestampUtc"] = utcNow.ToString("o"),
            ["mq.triggerTimestampUnixMs"] = ToUnixMilliseconds(utcNow).ToString(CultureInfo.InvariantCulture),
            ["mq.triggerSequence"] = sequenceNumber.ToString(CultureInfo.InvariantCulture),
            ["mq.finishBehavior"] = finishBehavior,
            ["mq.autoCloseDelayMs"] = autoCloseDelayMs
        };

        AddIfSet(extras, "mq.callerPackage", callerPackage);
        AddIfSet(extras, "mq.callerActivity", callerActivity);
        AddIfSet(extras, "mq.sessionId", sessionId);
        AddIfSet(extras, "mq.experimentId", experimentId);
        AddIfSet(extras, "mq.scenarioId", scenarioId);
        AddIfSet(extras, "mq.trialId", trialId);
        AddIfSet(extras, "mq.participantId", participantId);
        AddIfSet(extras, "mq.participantName", participantName);
        AddIfSet(extras, "mq.language", language);
        return extras;
    }

    private static void AddIfSet(Dictionary<string, string> extras, string key, string value)
    {
        if (!string.IsNullOrEmpty(value))
        {
            extras[key] = value;
        }
    }

    private static long ToUnixMilliseconds(DateTime utcTime)
    {
        DateTime epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        return (long)(utcTime - epoch).TotalMilliseconds;
    }
}
