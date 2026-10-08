#!/bin/sh
# Installs Godot's Android build template (android/build, not committed) and pins
# the SDK levels Google Play requires. `godot --install-android-build-template`
# hangs headless on this Mac, so this does the same by hand.
set -e
cd "$(dirname "$0")/.."
TPL="$HOME/Library/Application Support/Godot/export_templates/4.6.stable"
rm -rf android
mkdir -p android/build
unzip -q -o "$TPL/android_source.zip" -d android/build
cp "$TPL/version.txt" android/.build_version
touch android/build/.gdignore
chmod +x android/build/gradlew
# Google Play requires new apps to target Android 16 (API 36) from 31 August 2026.
sed -i '' 's/compileSdk         : 35,/compileSdk         : 36,/; s/targetSdk          : 35,/targetSdk          : 36,/' android/build/config.gradle
grep -E "compileSdk|targetSdk|buildTools|ndkVersion" android/build/config.gradle | head -4
