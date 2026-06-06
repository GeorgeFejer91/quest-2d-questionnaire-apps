@echo off
setlocal

if "%UNITY_ANDROID_ROOT%"=="" set "UNITY_ANDROID_ROOT=C:\Users\cogpsy-vrlab\Unity\Hub\Editor\6000.2.7f2\Editor\Data\PlaybackEngines\AndroidPlayer"
if "%JAVA_HOME%"=="" set "JAVA_HOME=%UNITY_ANDROID_ROOT%\OpenJDK"
if "%ANDROID_HOME%"=="" set "ANDROID_HOME=%UNITY_ANDROID_ROOT%\SDK"

set "GRADLE_LAUNCHER=%UNITY_ANDROID_ROOT%\Tools\gradle\lib\gradle-launcher-8.11.jar"

if not exist "%JAVA_HOME%\bin\java.exe" (
  echo Java not found at "%JAVA_HOME%\bin\java.exe"
  exit /b 1
)

if not exist "%GRADLE_LAUNCHER%" (
  echo Gradle launcher not found at "%GRADLE_LAUNCHER%"
  exit /b 1
)

"%JAVA_HOME%\bin\java.exe" -classpath "%GRADLE_LAUNCHER%" org.gradle.launcher.GradleMain %*
exit /b %ERRORLEVEL%
