# Build And Packaging

## Project Layout

Keep each APK-producing app as its own Android project:

```text
MyQuestionnaireVR-2D/
TemporalExperienceTracerVR-2D/
```

Generated Gradle state and transient validation output should not be committed:

```text
.gradle/
build/
artifacts/
Builds/
local.properties
```

Curated installable APKs belong in the repository-level `apks/` folder.

## Toolchain

The known-good local toolchain is Unity 6000.2.7f2's bundled Android runtime:

```text
C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer
```

That provides:

- OpenJDK
- Android SDK
- Gradle launcher 8.11

The custom `gradlew.bat` uses Unity's Gradle launcher rather than the standard
`gradle-wrapper.jar`, so Android Studio is not required on the development
machine.

## Build Commands

Demographic questionnaire:

```powershell
cd MyQuestionnaireVR-2D
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-apk.ps1
```

Temporal tracer:

```powershell
cd TemporalExperienceTracerVR-2D
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-apk.ps1
```

The build scripts write `local.properties` with the SDK path and copy the debug
APK to each project's ignored `Builds\` directory.

## Config-To-APK Flow

For configurable questionnaires, treat the JSON config as the source of truth.
The builder path is:

```text
static builder UI -> JSON config -> asset validation -> Gradle build -> APK -> render preview -> Quest replay/export
```

Useful commands in `MyQuestionnaireVR-2D`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-questionnaire-builder.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\generate-questionnaire-apk.ps1 -ConfigPath .\QuestionnaireConfigs\examples\custom-presence-check.config.json -RenderPreview
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-questionnaire-pipeline.ps1 -ConfigPath .\QuestionnaireConfigs\examples\custom-presence-check.config.json -SkipQuest
```

For the temporal tracer, edit:

```text
TemporalExperienceTracerVR-2D\app\src\main\assets\tracer\TemporalTracerConfig.json
```

Then run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\validate-temporal-tracer-assets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\render-temporal-tracer-visuals.ps1 -Sizes "1280x800"
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-apk.ps1
```

## Release Hygiene

Before committing APKs:

1. Copy only intentional release APKs into `apks/`.
2. Keep legacy Unity/scenario APKs over 100 MB out of normal git history.
3. Update `apks/checksums.sha256`.
4. Confirm the largest committed file is below GitHub's 100 MB file limit.
5. Run `git status -sb` and inspect the staged file list before pushing.

