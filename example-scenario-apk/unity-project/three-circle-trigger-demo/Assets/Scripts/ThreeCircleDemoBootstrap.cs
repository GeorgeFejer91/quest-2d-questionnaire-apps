using System;
using System.Collections.Generic;
using System.Globalization;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.XR;

public static class ThreeCircleDemoBootstrap
{
    [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
    private static void InstallScene()
    {
        CircleSceneProfile profile;
        if (!CircleSceneProfile.TryGet(SceneManager.GetActiveScene().name, out profile))
        {
            return;
        }

        GameObject controller = new GameObject("Three Circle Trigger Demo Controller");
        CircleSceneController sceneController = controller.AddComponent<CircleSceneController>();
        sceneController.Configure(profile);
    }
}

public struct CircleSceneProfile
{
    public string sceneName;
    public string nextSceneName;
    public string triggerId;
    public Color color;

    public static bool TryGet(string activeSceneName, out CircleSceneProfile profile)
    {
        if (activeSceneName.Contains("Green"))
        {
            profile = new CircleSceneProfile
            {
                sceneName = "01_GreenCircle",
                nextSceneName = "02_BlueCircle",
                triggerId = "trigger_1_complete",
                color = new Color(0.05f, 0.9f, 0.1f, 1f)
            };
            return true;
        }
        if (activeSceneName.Contains("Blue"))
        {
            profile = new CircleSceneProfile
            {
                sceneName = "02_BlueCircle",
                nextSceneName = "03_RedCircle",
                triggerId = "trigger_2_complete",
                color = new Color(0.05f, 0.25f, 1f, 1f)
            };
            return true;
        }
        if (activeSceneName.Contains("Red"))
        {
            profile = new CircleSceneProfile
            {
                sceneName = "03_RedCircle",
                nextSceneName = "",
                triggerId = "trigger_3_complete",
                color = new Color(1f, 0.05f, 0.03f, 1f)
            };
            return true;
        }

        profile = default(CircleSceneProfile);
        return false;
    }
}

public sealed class CircleSceneController : MonoBehaviour
{
    private readonly List<InputDevice> xrDevices = new List<InputDevice>();
    private CircleSceneProfile profile;
    private bool hasFired;
    private float armedAt;

    public void Configure(CircleSceneProfile configuredProfile)
    {
        profile = configuredProfile;
    }

    private void Start()
    {
        EnsureCamera();
        CreateCircle();
        armedAt = Time.unscaledTime + 0.35f;
    }

    private void Update()
    {
        if (hasFired || Time.unscaledTime < armedAt)
        {
            return;
        }

        if (Input.GetKeyDown(KeyCode.Space)
            || Input.GetKeyDown(KeyCode.Return)
            || Input.GetMouseButtonDown(0)
            || Input.touchCount > 0
            || AnyQuestButtonPressed())
        {
            FireTrigger();
        }
    }

    private void FireTrigger()
    {
        hasFired = true;
        CircleDemoQuestionnaireBridge.LaunchQuestionnaireTrigger(profile.triggerId, TriggerExtras());
        if (!string.IsNullOrEmpty(profile.nextSceneName))
        {
            SceneManager.LoadScene(profile.nextSceneName);
        }
    }

    private Dictionary<string, string> TriggerExtras()
    {
        DateTime utcNow = DateTime.UtcNow;
        return new Dictionary<string, string>
        {
            ["mq.triggerSource"] = "three-circle-unity-demo",
            ["mq.triggerTimestampUtc"] = utcNow.ToString("o"),
            ["mq.triggerTimestampUnixMs"] = ToUnixMilliseconds(utcNow).ToString(CultureInfo.InvariantCulture),
            ["mq.scenarioId"] = "quest-questionnaire-three-circle-trigger-demo",
            ["mq.finishBehavior"] = "resumeCaller",
            ["mq.autoCloseDelayMs"] = "1000"
        };
    }

    private static long ToUnixMilliseconds(DateTime utcTime)
    {
        DateTime epoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        return (long)(utcTime - epoch).TotalMilliseconds;
    }

    private bool AnyQuestButtonPressed()
    {
        xrDevices.Clear();
        InputDevices.GetDevicesWithCharacteristics(
            InputDeviceCharacteristics.Controller | InputDeviceCharacteristics.HeldInHand,
            xrDevices);
        for (int i = 0; i < xrDevices.Count; i++)
        {
            if (ButtonPressed(xrDevices[i], CommonUsages.primaryButton)
                || ButtonPressed(xrDevices[i], CommonUsages.triggerButton)
                || ButtonPressed(xrDevices[i], CommonUsages.gripButton))
            {
                return true;
            }

            float axisValue;
            if (xrDevices[i].TryGetFeatureValue(CommonUsages.trigger, out axisValue) && axisValue >= 0.75f)
            {
                return true;
            }
        }
        return false;
    }

    private static bool ButtonPressed(InputDevice device, InputFeatureUsage<bool> usage)
    {
        bool value;
        return device.TryGetFeatureValue(usage, out value) && value;
    }

    private static void EnsureCamera()
    {
        Camera camera = Camera.main;
        if (camera == null)
        {
            GameObject cameraObject = new GameObject("Main Camera");
            camera = cameraObject.AddComponent<Camera>();
            camera.tag = "MainCamera";
        }

        camera.transform.position = new Vector3(0f, 0f, -10f);
        camera.transform.rotation = Quaternion.identity;
        camera.orthographic = true;
        camera.orthographicSize = 4f;
        camera.clearFlags = CameraClearFlags.SolidColor;
        camera.backgroundColor = Color.black;
    }

    private void CreateCircle()
    {
        GameObject circle = new GameObject(profile.sceneName + " Display");
        MeshFilter meshFilter = circle.AddComponent<MeshFilter>();
        MeshRenderer meshRenderer = circle.AddComponent<MeshRenderer>();
        meshFilter.sharedMesh = BuildCircleMesh(2.65f, 128);
        Shader shader = Shader.Find("Unlit/Color");
        if (shader == null)
        {
            shader = Shader.Find("Standard");
        }
        Material material = new Material(shader);
        material.color = profile.color;
        meshRenderer.sharedMaterial = material;
    }

    private static Mesh BuildCircleMesh(float radius, int segmentCount)
    {
        Vector3[] vertices = new Vector3[segmentCount + 1];
        int[] triangles = new int[segmentCount * 3];
        vertices[0] = Vector3.zero;
        for (int index = 0; index < segmentCount; index++)
        {
            float angle = (Mathf.PI * 2f * index) / segmentCount;
            vertices[index + 1] = new Vector3(Mathf.Cos(angle) * radius, Mathf.Sin(angle) * radius, 0f);
        }
        for (int index = 0; index < segmentCount; index++)
        {
            int offset = index * 3;
            triangles[offset] = 0;
            triangles[offset + 1] = index + 1;
            triangles[offset + 2] = index == segmentCount - 1 ? 1 : index + 2;
        }

        Mesh mesh = new Mesh();
        mesh.name = "Runtime Circle";
        mesh.vertices = vertices;
        mesh.triangles = triangles;
        mesh.RecalculateBounds();
        return mesh;
    }
}
