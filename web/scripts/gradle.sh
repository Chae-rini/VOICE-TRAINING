#!/bin/sh
# 안드로이드 프로젝트(web/android)의 Gradle을 돌린다. 예: sh scripts/gradle.sh assembleDebug
# JDK는 21을 쓴다: 이 프로젝트의 Gradle 8.14.3은 Java 24까지만 돈다 (Java 25는 Gradle 9.1부터, Gradle 공식 호환 표).
# Android Studio 2026.2에 든 JDK는 25라서 그대로는 안 된다. JDK 21은 Homebrew(`brew install openjdk@21`, 2026-10-26 설치)나
# Android Studio의 Settings → Build Tools → Gradle → Gradle JDK → Download JDK(21)로 받는다. 둘 다 아래에서 찾는다.
# SDK는 Android Studio가 받는 기본 위치를 쓴다. 다른 곳에 있으면 JAVA_HOME·ANDROID_HOME을 먼저 정해 둔다.
set -e
BREW_JDK21=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
if [ -z "$JAVA_HOME" ]; then
  if [ -x "$BREW_JDK21/bin/java" ]; then
    JAVA_HOME=$BREW_JDK21
  else
    JAVA_HOME=$(/usr/libexec/java_home -v 21 2>/dev/null) || {
      echo "JDK 21을 찾지 못했어요. 'brew install openjdk@21'로 설치하거나 Android Studio → Settings → Build Tools → Gradle → Gradle JDK → Download JDK에서 21을 받아 주세요." >&2
      exit 1
    }
  fi
fi
: "${ANDROID_HOME:=$HOME/Library/Android/sdk}"
export JAVA_HOME ANDROID_HOME
if [ ! -d "$ANDROID_HOME/platforms" ]; then
  echo "안드로이드 SDK를 찾지 못했어요: $ANDROID_HOME (Android Studio 설치 마법사에서 SDK를 받았는지 확인)" >&2
  exit 1
fi
cd "$(dirname "$0")/../android"
exec ./gradlew "$@"
