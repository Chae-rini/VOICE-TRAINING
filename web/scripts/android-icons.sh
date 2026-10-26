#!/bin/sh
# 안드로이드 앱 아이콘과 시작 화면을 iOS 앱 아이콘(VoicePractice/Assets.xcassets/AppIcon.appiconset/AppIcon.png, 1024px) 하나로 만든다.
# 아이콘을 바꾸면 다시 돌린다: sh web/scripts/android-icons.sh (Mac에 기본으로 있는 sips를 쓴다)
# - ic_launcher·ic_launcher_round: 아이콘 전체 (예전 안드로이드용)
# - ic_launcher_foreground: 안드로이드 8 이상의 모양 맞춤 아이콘. 기기가 가장자리를 원·둥근 사각형으로 잘라 내므로,
#   그림이 가운데 안전 구역(108dp 중 66dp)에 들어가게 80%로 줄여 바탕색 가운데에 둔다 (배경색도 같은 색, values/ic_launcher_background.xml)
# - splash: 시작할 때 잠깐 보이는 화면. Capacitor 기본 로고 대신 바탕색 가운데에 울림 아이콘 (짧은 변의 40%)
# 바탕색은 아이콘 바탕과 같은 #FEFEFE다 (순수한 흰색으로 채우면 아이콘 둘레에 옅은 네모가 보인다).
set -e
BACKGROUND=FEFEFE
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/VoicePractice/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
RES="$ROOT/web/android/app/src/main/res"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 아이콘을 `size`로 줄이고 `width`×`height` 바탕 가운데에 둔다
place() { # place <size> <width> <height> <out>
  sips -z "$1" "$1" "$SOURCE" --out "$TMP/icon.png" >/dev/null
  # sips가 바탕색을 쓸 때 색 정보(CGColor)를 찍어서 감춘다
  sips --padToHeightWidth "$3" "$2" --padColor "$BACKGROUND" "$TMP/icon.png" --out "$4" >/dev/null 2>&1
}

for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density=${pair%%:*}; size=${pair##*:}
  sips -z "$size" "$size" "$SOURCE" --out "$RES/mipmap-$density/ic_launcher.png" >/dev/null
  cp "$RES/mipmap-$density/ic_launcher.png" "$RES/mipmap-$density/ic_launcher_round.png"
done

for pair in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  density=${pair%%:*}; size=${pair##*:}
  place $((size * 80 / 100)) "$size" "$size" "$RES/mipmap-$density/ic_launcher_foreground.png"
done

for file in "$RES"/drawable*/splash.png; do
  width=$(sips -g pixelWidth "$file" | awk '/pixelWidth/{print $2}')
  height=$(sips -g pixelHeight "$file" | awk '/pixelHeight/{print $2}')
  short=$((width < height ? width : height))
  place $((short * 40 / 100)) "$width" "$height" "$file"
done
echo "아이콘·시작 화면을 만들었어요: $RES"
