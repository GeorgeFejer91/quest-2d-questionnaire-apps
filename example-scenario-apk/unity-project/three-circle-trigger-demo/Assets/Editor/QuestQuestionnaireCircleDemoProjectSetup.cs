#if UNITY_EDITOR
using UnityEditor;
using UnityEditor.Build;
using UnityEngine.XR.OpenXR;
using UnityEngine.XR.OpenXR.Features;
using UnityEngine.XR.OpenXR.Features.Interactions;

[InitializeOnLoad]
public static class QuestQuestionnaireCircleDemoProjectSetup
{
    private const string PackageName = "org.questquestionnaire.circletriggerdemo";
    private const string ProductName = "Three Circle Trigger Demo";

    static QuestQuestionnaireCircleDemoProjectSetup()
    {
        EditorApplication.delayCall += Apply;
    }

    public static void Apply()
    {
        PlayerSettings.productName = ProductName;
#if UNITY_2021_2_OR_NEWER
        PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, PackageName);
#else
        PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.Android, PackageName);
#endif
        EditorBuildSettings.scenes = new[]
        {
            new EditorBuildSettingsScene("Assets/Scenes/01_GreenCircle.unity", true),
            new EditorBuildSettingsScene("Assets/Scenes/02_BlueCircle.unity", true),
            new EditorBuildSettingsScene("Assets/Scenes/03_RedCircle.unity", true)
        };
        ApplyOpenXRProfiles();
    }

    private static void ApplyOpenXRProfiles()
    {
        SetOpenXRFeature(OculusTouchControllerProfile.featureId, true);
        SetOpenXRFeature(HandInteractionProfile.featureId, true);
    }

    private static void SetOpenXRFeature(string featureId, bool enabled)
    {
        OpenXRSettings settings = OpenXRSettings.GetSettingsForBuildTargetGroup(BuildTargetGroup.Android);
        if (settings == null)
        {
            return;
        }

        foreach (OpenXRFeature feature in settings.GetFeatures<OpenXRFeature>())
        {
            if (feature.featureId == featureId)
            {
                feature.enabled = enabled;
                EditorUtility.SetDirty(feature);
            }
        }
        EditorUtility.SetDirty(settings);
    }
}
#endif
