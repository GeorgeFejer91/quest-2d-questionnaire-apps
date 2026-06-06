using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.XR;

public sealed class ChainLinkControllerHook : MonoBehaviour
{
    public enum LeftControllerButton
    {
        PrimaryButton,
        SecondaryButton,
        TriggerButton,
        GripButton,
        MenuButton
    }

    [Header("ChainLink trigger")]
    public bool enableHook = true;
    public LeftControllerButton button = LeftControllerButton.SecondaryButton;
    public float debounceSeconds = 0.75f;
    public bool sendOnlyOnce = false;

    [Header("Experiment metadata")]
    public string chainId = "";
    public string experimentId = "";
    public string scenarioId = "";
    public string trialId = "";
    public string participantId = "";
    public string participantName = "";
    public string language = "";
    public string blockNumber = "";
    public string blockId = "";
    public string triggerSource = "unity-left-controller";

    [Header("Editor fallback")]
    public bool allowEditorFallbackKey = true;
    public KeyCode editorFallbackKey = KeyCode.N;

    private InputDevice leftController;
    private bool wasPressed;
    private float nextAllowedSendTime;
    private int sentCount;

    private void Update()
    {
        if (!enableHook)
        {
            wasPressed = false;
            return;
        }

        bool pressed = IsButtonPressed();
        bool risingEdge = pressed && !wasPressed;
        wasPressed = pressed;

        if (!risingEdge || Time.unscaledTime < nextAllowedSendTime)
        {
            return;
        }

        if (sendOnlyOnce && sentCount > 0)
        {
            return;
        }

        SendNextBlock();
    }

    [ContextMenu("Send ChainLink Next Block")]
    public void SendNextBlock()
    {
        var extras = BuildTriggerExtras();
        QuestQuestionnaireChainBridge.SendChainLinkNextBlock(extras);
        sentCount++;
        nextAllowedSendTime = Time.unscaledTime + Math.Max(0.05f, debounceSeconds);
        Debug.Log("ChainLinkControllerHook sent nextBlock to ChainLink.");
    }

    public Dictionary<string, string> BuildTriggerExtras()
    {
        DateTime utcNow = DateTime.UtcNow;
        var extras = new Dictionary<string, string>
        {
            ["mq.triggerSource"] = string.IsNullOrEmpty(triggerSource) ? "unity-left-controller" : triggerSource,
            ["mq.triggerButton"] = button.ToString(),
            ["mq.triggerTimestampUtc"] = utcNow.ToString("o"),
            ["mq.triggerTimestampUnixMs"] = ToUnixMilliseconds(utcNow).ToString(),
            ["mq.commandSource"] = "unity-foreground-hook"
        };

        AddIfSet(extras, "mq.chainId", chainId);
        AddIfSet(extras, "mq.experimentId", experimentId);
        AddIfSet(extras, "mq.scenarioId", scenarioId);
        AddIfSet(extras, "mq.trialId", trialId);
        AddIfSet(extras, "mq.participantId", participantId);
        AddIfSet(extras, "mq.participantName", participantName);
        AddIfSet(extras, "mq.language", language);
        AddIfSet(extras, "mq.blockNumber", blockNumber);
        AddIfSet(extras, "mq.blockId", blockId);

        return extras;
    }

    private bool IsButtonPressed()
    {
#if UNITY_EDITOR
        if (allowEditorFallbackKey && Input.GetKey(editorFallbackKey))
        {
            return true;
        }
#endif

        if (!TryEnsureLeftController())
        {
            return false;
        }

        bool buttonValue;
        switch (button)
        {
            case LeftControllerButton.PrimaryButton:
                return leftController.TryGetFeatureValue(CommonUsages.primaryButton, out buttonValue) && buttonValue;
            case LeftControllerButton.SecondaryButton:
                return leftController.TryGetFeatureValue(CommonUsages.secondaryButton, out buttonValue) && buttonValue;
            case LeftControllerButton.TriggerButton:
                if (leftController.TryGetFeatureValue(CommonUsages.triggerButton, out buttonValue) && buttonValue)
                {
                    return true;
                }
                float triggerValue;
                return leftController.TryGetFeatureValue(CommonUsages.trigger, out triggerValue) && triggerValue >= 0.75f;
            case LeftControllerButton.GripButton:
                if (leftController.TryGetFeatureValue(CommonUsages.gripButton, out buttonValue) && buttonValue)
                {
                    return true;
                }
                float gripValue;
                return leftController.TryGetFeatureValue(CommonUsages.grip, out gripValue) && gripValue >= 0.75f;
            case LeftControllerButton.MenuButton:
                return leftController.TryGetFeatureValue(CommonUsages.menuButton, out buttonValue) && buttonValue;
            default:
                return false;
        }
    }

    private bool TryEnsureLeftController()
    {
        if (leftController.isValid)
        {
            return true;
        }

        leftController = InputDevices.GetDeviceAtXRNode(XRNode.LeftHand);
        if (leftController.isValid)
        {
            return true;
        }

        var devices = new List<InputDevice>();
        InputDevices.GetDevicesWithCharacteristics(
            InputDeviceCharacteristics.Left | InputDeviceCharacteristics.Controller,
            devices);
        if (devices.Count > 0)
        {
            leftController = devices[0];
            return leftController.isValid;
        }

        return false;
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
