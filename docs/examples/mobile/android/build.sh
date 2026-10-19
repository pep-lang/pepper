#!/usr/bin/env bash
# Build the prototype Android app and run it in the emulator:
#
#   bash build.sh <pep-build> <output-dir> [<adb-serial>]
#
# Builds ../greeter.pep as a static library for arm64 Android, links it with
# jni.c into libgreeter.so using the NDK's clang, compiles MainActivity.java
# and packages an APK with the SDK's own tools (javac, d8, aapt2, zipalign,
# apksigner; no Gradle), signed with a throwaway key. With an emulator's adb
# serial, installs it, starts the activity, and checks its log.
#
# Needs ANDROID_HOME (the Android SDK, with an NDK, a platform and
# build-tools) and a JDK (JAVA_HOME, else Android Studio's own).
set -euo pipefail

compiler=${1:?usage: build.sh <pep-build> <output-dir> [<adb-serial>]}
out=${2:?usage: build.sh <pep-build> <output-dir> [<adb-serial>]}
serial=${3:-}
here=$(cd "$(dirname "$0")" && pwd)

export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
newest() { ls "$1" | sort -V | tail -1; }
ndk="$ANDROID_HOME/ndk/$(newest "$ANDROID_HOME/ndk")"
tools="$ANDROID_HOME/build-tools/$(newest "$ANDROID_HOME/build-tools")"
platform="$ANDROID_HOME/platforms/$(newest "$ANDROID_HOME/platforms")"
clang=$(ls -d "$ndk"/toolchains/llvm/prebuilt/*/bin/clang | head -1)
if [ -z "${JAVA_HOME:-}" ]; then
  export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
fi
export PATH="$JAVA_HOME/bin:$PATH"

rm -rf "$out"
mkdir -p "$out/pepper" "$out/apk/lib/arm64-v8a" "$out/classes" "$out/dex"

# The native library: Pepper's code plus the JNI functions. The header's
# first lines name the C libraries the static library needs (-lm).
"$compiler" --target aarch64-linux-android --sysroot "$ndk" --lib static "$here/../greeter.pep" \
  -o "$out/pepper/libgreeter.a" --build "$out/pepper/build"
libraries=$(sed -nE 's|^/\* Link the static library with: (.*) \*/$|\1|p' "$out/pepper/greeter.h")
"$clang" --target=aarch64-linux-android30 -shared -fPIC -O2 -I "$out/pepper" "$here/jni.c" \
  "$out/pepper/libgreeter.a" $libraries -o "$out/apk/lib/arm64-v8a/libgreeter.so"

# The Java code, as dex.
javac --release 11 -classpath "$platform/android.jar" -d "$out/classes" \
  "$here/src/dev/pepper/demo/MainActivity.java"
"$tools/d8" --release --min-api 30 --lib "$platform/android.jar" --output "$out/dex" \
  $(find "$out/classes" -name '*.class')
cp "$out/dex/classes.dex" "$out/apk/"

# The APK: the manifest, then the dex and the native library.
"$tools/aapt2" link -o "$out/unaligned.apk" -I "$platform/android.jar" \
  --manifest "$here/AndroidManifest.xml"
(cd "$out/apk" && zip -qr "$out/unaligned.apk" classes.dex lib)
"$tools/zipalign" -f -p 4 "$out/unaligned.apk" "$out/aligned.apk"
keytool -genkeypair -keystore "$out/debug.keystore" -storepass android -keypass android \
  -alias pepper -dname "CN=Pepper Demo" -keyalg RSA -keysize 2048 -validity 1 > /dev/null 2>&1
"$tools/apksigner" sign --ks "$out/debug.keystore" --ks-pass pass:android \
  --out "$out/PepperDemo.apk" "$out/aligned.apk"
echo "built $out/PepperDemo.apk"
[ -n "$serial" ] || exit 0

adb="$ANDROID_HOME/platform-tools/adb"
"$adb" -s "$serial" install -r "$out/PepperDemo.apk"
"$adb" -s "$serial" logcat -c
"$adb" -s "$serial" shell am start -W -n dev.pepper.demo/.MainActivity
expected="Hello, Android, from Pepper"
waited=0
until "$adb" -s "$serial" logcat -d -s PepperDemo:I > "$out/log.txt" && grep -q "$expected" "$out/log.txt"; do
  sleep 1
  waited=$((waited + 1))
  if [ "$waited" -ge 60 ]; then
    echo "the app did not log '$expected'; the log:"
    "$adb" -s "$serial" logcat -d | tail -60
    "$adb" -s "$serial" uninstall dev.pepper.demo || true
    exit 1
  fi
done
cat "$out/log.txt"
grep -q "fibonacci(50) = 12586269025" "$out/log.txt"
grep -q "words: 4" "$out/log.txt"
"$adb" -s "$serial" exec-out screencap -p > "$out/screenshot.png" || true
"$adb" -s "$serial" uninstall dev.pepper.demo
echo "android app: ok"
