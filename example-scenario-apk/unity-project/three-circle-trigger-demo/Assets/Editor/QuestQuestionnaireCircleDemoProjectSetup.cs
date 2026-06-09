#if UNITY_EDITOR
using System;
using System.Reflection;
using UnityEditor;
using UnityEditor.Android;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEditor.XR.Management;
using UnityEditor.XR.Management.Metadata;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.XR.Management;
using UnityEngine.XR.OpenXR;
using UnityEngine.XR.OpenXR.Features;
using UnityEngine.XR.OpenXR.Features.Interactions;

[InitializeOnLoad]
public static class QuestQuestionnaireCircleDemoProjectSetup
{
    private const string PackageName = "org.questquestionnaire.circletriggerdemo";
    private const string ProductName = "Three Circle Trigger Demo";
    private const string OpenXRLoaderTypeName = "UnityEngine.XR.OpenXR.OpenXRLoader";
    private const string OpenXRSettingsKey = "com.unity.xr.openxr.settings4";

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
        EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.Android, BuildTarget.Android);
        PlayerSettings.colorSpace = ColorSpace.Linear;
        PlayerSettings.SetUseDefaultGraphicsAPIs(BuildTarget.Android, false);
        PlayerSettings.SetGraphicsAPIs(BuildTarget.Android, new[] { GraphicsDeviceType.Vulkan });
        PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel24;
        PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
        PlayerSettings.SetScriptingBackend(NamedBuildTarget.Android, ScriptingImplementation.IL2CPP);
        EnsureXRSettings();
        ApplyOpenXRProfiles();
        AssetDatabase.SaveAssets();
    }

    public static void BuildAndroid()
    {
        Apply();
        string outputPath = "Builds/QuestQuestionnaireThreeCircleTriggerDemo.apk";
        System.IO.Directory.CreateDirectory("Builds");
        BuildPlayerOptions options = new BuildPlayerOptions
        {
            scenes = new[]
            {
                "Assets/Scenes/01_GreenCircle.unity",
                "Assets/Scenes/02_BlueCircle.unity",
                "Assets/Scenes/03_RedCircle.unity"
            },
            locationPathName = outputPath,
            target = BuildTarget.Android,
            options = BuildOptions.None
        };
        BuildReport report = BuildPipeline.BuildPlayer(options);
        if (report.summary.result != BuildResult.Succeeded)
        {
            throw new System.Exception("Three Circle Trigger Demo Android build failed: " + report.summary.result);
        }
    }

    private static void ApplyOpenXRProfiles()
    {
        SetOpenXRFeature(OculusTouchControllerProfile.featureId, true);
        SetOpenXRFeature(HandInteractionProfile.featureId, true);
        SetOpenXRFeatureByTypeName("UnityEngine.XR.OpenXR.Features.MetaQuestSupport.MetaQuestFeature", true);
        SetOpenXRFeatureByTypeName("UnityEngine.XR.OpenXR.Features.Interactions.MetaQuestTouchPlusControllerProfile", true);
        SetOpenXRFeatureByTypeName("UnityEngine.XR.OpenXR.Features.Interactions.MetaQuestTouchProControllerProfile", true);
    }

    private static void EnsureXRSettings()
    {
        XRGeneralSettingsPerBuildTarget buildTargetSettings = GetOrCreateXRGeneralSettings();
        if (!buildTargetSettings.HasSettingsForBuildTarget(BuildTargetGroup.Android))
        {
            buildTargetSettings.CreateDefaultSettingsForBuildTarget(BuildTargetGroup.Android);
        }
        if (!buildTargetSettings.HasManagerSettingsForBuildTarget(BuildTargetGroup.Android))
        {
            buildTargetSettings.CreateDefaultManagerSettingsForBuildTarget(BuildTargetGroup.Android);
        }

        XRGeneralSettings androidSettings = buildTargetSettings.SettingsForBuildTarget(BuildTargetGroup.Android);
        if (androidSettings != null && androidSettings.Manager != null)
        {
            XRPackageMetadataStore.AssignLoader(androidSettings.Manager, OpenXRLoaderTypeName, BuildTargetGroup.Android);
            EditorUtility.SetDirty(androidSettings.Manager);
            EditorUtility.SetDirty(androidSettings);
        }

        EditorBuildSettings.AddConfigObject(XRGeneralSettings.k_SettingsKey, buildTargetSettings, true);
        RegisterOpenXRPackageSettings();
        EditorUtility.SetDirty(buildTargetSettings);
    }

    private static XRGeneralSettingsPerBuildTarget GetOrCreateXRGeneralSettings()
    {
        XRGeneralSettingsPerBuildTarget buildTargetSettings = null;
        EditorBuildSettings.TryGetConfigObject(XRGeneralSettings.k_SettingsKey, out buildTargetSettings);
        if (buildTargetSettings != null)
        {
            return buildTargetSettings;
        }

        string[] guids = AssetDatabase.FindAssets("t:XRGeneralSettingsPerBuildTarget");
        if (guids.Length > 0)
        {
            string path = AssetDatabase.GUIDToAssetPath(guids[0]);
            buildTargetSettings = AssetDatabase.LoadAssetAtPath<XRGeneralSettingsPerBuildTarget>(path);
        }
        if (buildTargetSettings != null)
        {
            EditorBuildSettings.AddConfigObject(XRGeneralSettings.k_SettingsKey, buildTargetSettings, true);
            return buildTargetSettings;
        }

        EnsureAssetFolder("Assets", "XR");
        buildTargetSettings = ScriptableObject.CreateInstance<XRGeneralSettingsPerBuildTarget>();
        buildTargetSettings.name = "XRGeneralSettingsPerBuildTarget";
        AssetDatabase.CreateAsset(buildTargetSettings, "Assets/XR/XRGeneralSettingsPerBuildTarget.asset");
        EditorBuildSettings.AddConfigObject(XRGeneralSettings.k_SettingsKey, buildTargetSettings, true);
        AssetDatabase.SaveAssets();
        return buildTargetSettings;
    }

    private static void EnsureAssetFolder(string parent, string child)
    {
        string path = parent + "/" + child;
        if (!AssetDatabase.IsValidFolder(path))
        {
            AssetDatabase.CreateFolder(parent, child);
        }
    }

    private static void RegisterOpenXRPackageSettings()
    {
        UnityEngine.Object settingsObject = GetOrCreateOpenXRPackageSettings();
        if (settingsObject != null)
        {
            EditorBuildSettings.AddConfigObject(OpenXRSettingsKey, settingsObject, true);
            EditorUtility.SetDirty(settingsObject);
        }
    }

    private static UnityEngine.Object GetOrCreateOpenXRPackageSettings()
    {
        Type settingsType = null;
        foreach (Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            settingsType = assembly.GetType("UnityEditor.XR.OpenXR.OpenXRPackageSettings");
            if (settingsType != null)
            {
                break;
            }
        }
        if (settingsType == null)
        {
            return null;
        }

        MethodInfo factory = settingsType.GetMethod("GetOrCreateInstance", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic);
        if (factory != null)
        {
            return factory.Invoke(null, null) as UnityEngine.Object;
        }

        string[] guids = AssetDatabase.FindAssets("t:" + settingsType.Name);
        if (guids.Length > 0)
        {
            string path = AssetDatabase.GUIDToAssetPath(guids[0]);
            return AssetDatabase.LoadAssetAtPath(path, settingsType) as UnityEngine.Object;
        }
        return null;
    }

    private static void SetOpenXRFeature<TFeature>(bool enabled) where TFeature : OpenXRFeature
    {
        OpenXRSettings settings = OpenXRSettings.GetSettingsForBuildTargetGroup(BuildTargetGroup.Android);
        if (settings == null)
        {
            return;
        }

        OpenXRFeature directFeature = settings.GetFeature(typeof(TFeature));
        if (directFeature != null)
        {
            directFeature.enabled = enabled;
            EditorUtility.SetDirty(directFeature);
        }

        foreach (OpenXRFeature feature in settings.GetFeatures<TFeature>())
        {
            feature.enabled = enabled;
            EditorUtility.SetDirty(feature);
        }
        EditorUtility.SetDirty(settings);
    }

    private static void SetOpenXRFeature(string featureId, bool enabled)
    {
        OpenXRSettings settings = OpenXRSettings.GetSettingsForBuildTargetGroup(BuildTargetGroup.Android);
        if (settings == null || string.IsNullOrEmpty(featureId))
        {
            return;
        }

        foreach (OpenXRFeature feature in settings.GetFeatures<OpenXRFeature>())
        {
            if (GetOpenXRFeatureId(feature) == featureId)
            {
                feature.enabled = enabled;
                EditorUtility.SetDirty(feature);
            }
        }
        EditorUtility.SetDirty(settings);
    }

    private static string GetOpenXRFeatureId(OpenXRFeature feature)
    {
        if (feature == null)
        {
            return "";
        }

        Type featureType = feature.GetType();
        PropertyInfo publicProperty = featureType.GetProperty("featureId", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        if (publicProperty != null)
        {
            object value = publicProperty.GetValue(feature);
            if (value != null)
            {
                return value.ToString();
            }
        }

        FieldInfo field = featureType.GetField("featureIdInternal", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        if (field != null)
        {
            object value = field.GetValue(feature);
            if (value != null)
            {
                return value.ToString();
            }
        }
        return "";
    }

    private static void SetOpenXRFeatureByTypeName(string typeName, bool enabled)
    {
        OpenXRSettings settings = OpenXRSettings.GetSettingsForBuildTargetGroup(BuildTargetGroup.Android);
        if (settings == null)
        {
            return;
        }

        foreach (OpenXRFeature feature in settings.GetFeatures<OpenXRFeature>())
        {
            Type featureType = feature.GetType();
            if (featureType.FullName == typeName || featureType.Name == typeName)
            {
                feature.enabled = enabled;
                EditorUtility.SetDirty(feature);
            }
        }
        EditorUtility.SetDirty(settings);
    }
}
#endif
