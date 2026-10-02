#!/usr/bin/env sh
UNITY_ANDROID_ROOT="${UNITY_ANDROID_ROOT:-/c/Users/cogpsy-vrlab/Unity/Hub/Editor/6000.2.7f2/Editor/Data/PlaybackEngines/AndroidPlayer}"
JAVA_HOME="${JAVA_HOME:-$UNITY_ANDROID_ROOT/OpenJDK}"
ANDROID_HOME="${ANDROID_HOME:-$UNITY_ANDROID_ROOT/SDK}"
GRADLE_LAUNCHER="$UNITY_ANDROID_ROOT/Tools/gradle/lib/gradle-launcher-8.11.jar"

exec "$JAVA_HOME/bin/java" -classpath "$GRADLE_LAUNCHER" org.gradle.launcher.GradleMain "$@"
