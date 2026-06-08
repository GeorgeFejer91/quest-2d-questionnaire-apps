using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using UnityEngine;

public sealed class ChainLinkTimedTrigger : MonoBehaviour
{
    public enum TimedChainAction
    {
        ContinueBrokerPlan,
        ChainLinkNextBlock,
        ChainLinkCommand,
        LaunchQuestionnaire
    }

    [Header("Timing")]
    public bool enableTrigger = true;
    public bool armOnStart = true;
    public bool useRealtime = true;
    public float initialDelaySeconds = 60f;
    public bool repeat = false;
    public float repeatIntervalSeconds = 60f;
    public int maxSends = 1;

    [Header("Action")]
    public TimedChainAction action = TimedChainAction.ContinueBrokerPlan;
    public string chainLinkCommand = "nextBlock";

    [Header("Passive questionnaire trigger")]
    public string triggerId = "";
    public string finishBehavior = "resumeCaller";
    public string callerPackage = "";
    public string callerActivity = "";
    public string autoCloseDelayMs = "2000";

    [Header("Legacy/dev questionnaire fallback")]
    public string questionnaireMode = "";

    [Header("Experiment metadata")]
    public bool copyIncomingChainExtras = true;
    public string chainId = "";
    public string sessionId = "";
    public string experimentId = "";
    public string scenarioId = "";
    public string trialId = "";
    public string participantId = "";
    public string participantName = "";
    public string language = "";
    public string blockNumber = "";
    public string blockId = "";
    public string triggerSource = "unity-timed-trigger";

    private Coroutine timerCoroutine;
    private int sentCount;

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

    [ContextMenu("Arm Timed Chain Trigger")]
    public void Arm()
    {
        if (!enableTrigger)
        {
            return;
        }

        Disarm();
        timerCoroutine = StartCoroutine(TimerLoop());
    }

    [ContextMenu("Disarm Timed Chain Trigger")]
    public void Disarm()
    {
        if (timerCoroutine == null)
        {
            return;
        }

        StopCoroutine(timerCoroutine);
        timerCoroutine = null;
    }

    [ContextMenu("Fire Timed Chain Trigger Now")]
    public void FireNow()
    {
        if (!enableTrigger || !CanSendMore())
        {
            return;
        }

        SendConfiguredAction();
    }

    private IEnumerator TimerLoop()
    {
        yield return WaitForConfiguredDelay(initialDelaySeconds);

        while (enableTrigger && CanSendMore())
        {
            SendConfiguredAction();

            if (!repeat || !CanSendMore())
            {
                break;
            }

            yield return WaitForConfiguredDelay(repeatIntervalSeconds);
        }

        timerCoroutine = null;
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

    private bool CanSendMore()
    {
        return maxSends <= 0 || sentCount < maxSends;
    }

    private void SendConfiguredAction()
    {
        var extras = BuildTriggerExtras();
        switch (action)
        {
            case TimedChainAction.ContinueBrokerPlan:
                extras["mq.resultStatus"] = "scenarioTimedTrigger";
                QuestQuestionnaireChainBridge.ContinueBrokerPlan(extras);
                break;
            case TimedChainAction.ChainLinkNextBlock:
                if (string.IsNullOrEmpty(triggerId))
                {
                    QuestQuestionnaireChainBridge.SendChainLinkNextBlock(extras);
                }
                else
                {
                    QuestQuestionnaireChainBridge.SendChainLinkTrigger(triggerId, extras);
                }
                break;
            case TimedChainAction.ChainLinkCommand:
                QuestQuestionnaireChainBridge.SendChainLinkCommand(chainLinkCommand, extras);
                break;
            case TimedChainAction.LaunchQuestionnaire:
                AddQuestionnaireLaunchExtras(extras);
                if (string.IsNullOrEmpty(triggerId))
                {
                    QuestQuestionnaireChainBridge.LaunchQuestionnaire(extras);
                }
                else
                {
                    QuestQuestionnaireChainBridge.LaunchQuestionnaireTrigger(triggerId, extras);
                }
                break;
            default:
                Debug.LogWarning("ChainLinkTimedTrigger has no action configured.");
                return;
        }

        sentCount++;
        Debug.Log("ChainLinkTimedTrigger fired action=" + action
            + " sequence=" + sentCount.ToString(CultureInfo.InvariantCulture)
            + " triggerSource=" + extras["mq.triggerSource"]);
    }

    public Dictionary<string, string> BuildTriggerExtras()
    {
        var extras = new Dictionary<string, string>();

        if (copyIncomingChainExtras)
        {
            CopyIncomingChainExtras(extras);
        }

        DateTime utcNow = DateTime.UtcNow;
        extras["mq.triggerSource"] = string.IsNullOrEmpty(triggerSource) ? "unity-timed-trigger" : triggerSource;
        extras["mq.triggerTimestampUtc"] = utcNow.ToString("o");
        extras["mq.triggerTimestampUnixMs"] = ToUnixMilliseconds(utcNow).ToString(CultureInfo.InvariantCulture);
        extras["mq.commandSource"] = "unity-timed-hook";
        extras["mq.triggerDelaySeconds"] = initialDelaySeconds.ToString("0.###", CultureInfo.InvariantCulture);
        extras["mq.triggerSequence"] = (sentCount + 1).ToString(CultureInfo.InvariantCulture);

        AddIfSet(extras, "mq.chainId", chainId);
        AddIfSet(extras, "mq.sessionId", sessionId);
        AddIfSet(extras, "mq.experimentId", experimentId);
        AddIfSet(extras, "mq.scenarioId", scenarioId);
        AddIfSet(extras, "mq.trialId", trialId);
        AddIfSet(extras, "mq.participantId", participantId);
        AddIfSet(extras, "mq.participantName", participantName);
        AddIfSet(extras, "mq.language", language);
        AddIfSet(extras, "mq.triggerId", triggerId);
        AddIfSet(extras, "mq.blockNumber", blockNumber);
        AddIfSet(extras, "mq.blockId", blockId);

        return extras;
    }

    private void AddQuestionnaireLaunchExtras(Dictionary<string, string> extras)
    {
        AddIfSet(extras, "mq.questionnaireMode", questionnaireMode);
        AddIfSet(extras, "mq.finishBehavior", finishBehavior);
        AddIfSet(extras, "mq.callerPackage", callerPackage);
        AddIfSet(extras, "mq.callerActivity", callerActivity);
        AddIfSet(extras, "mq.autoCloseDelayMs", autoCloseDelayMs);
    }

    private static void CopyIncomingChainExtras(Dictionary<string, string> extras)
    {
        var incoming = QuestQuestionnaireChainBridge.ReadChainHookCommand();
        CopyIfPresent(incoming, extras, "mq.chainId");
        CopyIfPresent(incoming, extras, "mq.chainStepId");
        CopyIfPresent(incoming, extras, "mq.chainStepIndex");
        CopyIfPresent(incoming, extras, "mq.brokerAction");
        CopyIfPresent(incoming, extras, "mq.brokerPackage");
        CopyIfPresent(incoming, extras, "mq.brokerActivity");
        CopyIfPresent(incoming, extras, "mq.sessionId");
        CopyIfPresent(incoming, extras, "mq.experimentId");
        CopyIfPresent(incoming, extras, "mq.scenarioId");
        CopyIfPresent(incoming, extras, "mq.trialId");
        CopyIfPresent(incoming, extras, "mq.participantId");
        CopyIfPresent(incoming, extras, "mq.participantName");
        CopyIfPresent(incoming, extras, "mq.language");
        CopyIfPresent(incoming, extras, "scenarioId");
        CopyIfPresent(incoming, extras, "trialId");
    }

    private static void CopyIfPresent(Dictionary<string, string> source, Dictionary<string, string> destination, string key)
    {
        if (source != null && source.TryGetValue(key, out var value) && !string.IsNullOrEmpty(value))
        {
            destination[key] = value;
        }
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
        var epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        return (long)(utcTime - epoch).TotalMilliseconds;
    }
}
